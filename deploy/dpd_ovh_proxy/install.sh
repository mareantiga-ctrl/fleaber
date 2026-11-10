#!/usr/bin/env bash
# Instala proxy HTTPS DPD no VPS OVH Fleaber ONLY.
# Host esperado: vps-27d76f35 / 135.125.254.159 — NÃO correr no Biscateiro (152.228.173.97).
# Uso: sudo bash install.sh dpd-proxy.fleaber.pt
set -euo pipefail

DOMAIN="${1:-}"
EXPECTED_IP="${FLEABER_DPD_EXPECTED_IP:-135.125.254.159}"
if [[ -z "$DOMAIN" ]]; then
  echo "Uso: $0 <dominio-tls>   ex: dpd-proxy.fleaber.pt"
  exit 1
fi

# Guard: recusar se este host for o VPS errado
SELF_IP="$(curl -4 -fsS --max-time 10 https://api.ipify.org || true)"
HN="$(hostname -f 2>/dev/null || hostname || true)"
if [[ "$SELF_IP" == "152.228.173.97" ]] || [[ "$HN" == *b84a0381* ]]; then
  echo "ABORT: este host parece Biscateiro ($HN / $SELF_IP). Não instalar."
  exit 2
fi
if [[ -n "$SELF_IP" && "$SELF_IP" != "$EXPECTED_IP" ]]; then
  echo "ABORT: egress/IP $SELF_IP != esperado $EXPECTED_IP. Confirma VPS Fleaber."
  exit 2
fi
echo "OK host check: hn=$HN ip=$SELF_IP"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx ufw fail2ban curl jq certbot python3-certbot-nginx openssl

# --- secret Bearer (só no servidor) ---
SECRET_FILE=/etc/fleaber-dpd/proxy_bearer
mkdir -p /etc/fleaber-dpd /var/www/fleaber-dpd-proxy /var/log/fleaber-dpd
chmod 750 /etc/fleaber-dpd
if [[ ! -f "$SECRET_FILE" ]]; then
  openssl rand -hex 32 > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
  echo "Gerado Bearer em $SECRET_FILE (copiar para Supabase secret; NÃO para o git)"
fi

# --- CGI/php-less forwarder via nginx + small python? Use openresty? Keep simple: nginx auth_request + lua hard.
# Prefer: Caddy or nginx + a tiny Go/Python service.
# Python stdlib reverse forwarder as systemd unit:

cat > /usr/local/bin/fleaber-dpd-proxy.py << 'PY'
#!/usr/bin/env python3
"""HTTPS upstream forwarder: Edge → this host → allowlisted DPD hosts only."""
from __future__ import annotations
import json, os, ssl, urllib.error, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BEARER_PATH = "/etc/fleaber-dpd/proxy_bearer"
# Preencher hosts DPD DEV/PROD quando a DPD indicar; vazio = só health + egress.
ALLOWED_HOSTS = set(
    h.strip().lower()
    for h in os.environ.get("FLEABER_DPD_ALLOWED_HOSTS", "").split(",")
    if h.strip()
)
LISTEN = ("127.0.0.1", 8088)

def load_bearer() -> str:
    with open(BEARER_PATH, "r", encoding="utf-8") as f:
        return f.read().strip()

BEARER = load_bearer()

def redact(s: str) -> str:
    # não logar Authorization / passwords
    return s

class Handler(BaseHTTPRequestHandler):
    server_version = "FleaberDpdProxy/1.0"

    def log_message(self, fmt: str, *args) -> None:
        # access log mínimo sem query/body
        sys_stderr = __import__("sys").stderr
        print("%s %s" % (self.address_string(), fmt % args), file=sys_stderr)

    def _json(self, code: int, obj: dict) -> None:
        body = json.dumps(obj, separators=(",", ":")).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self) -> bool:
        h = self.headers.get("Authorization", "")
        if not h.startswith("Bearer "):
            return False
        token = h[7:].strip()
        return token == BEARER and len(token) >= 32

    def do_GET(self) -> None:
        if self.path in ("/health", "/healthz"):
            self._json(200, {"ok": True, "service": "fleaber-dpd-proxy"})
            return
        if self.path == "/egress":
            if not self._auth():
                self._json(401, {"ok": False, "error": "unauthorized"})
                return
            try:
                with urllib.request.urlopen("https://api.ipify.org?format=json", timeout=10) as r:
                    data = json.loads(r.read().decode())
                self._json(200, {"ok": True, "egress_ip": data.get("ip")})
            except Exception as e:
                self._json(502, {"ok": False, "error": "egress_probe_failed", "detail": type(e).__name__})
            return
        self._json(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:
        if self.path != "/forward":
            self._json(404, {"ok": False, "error": "not_found"})
            return
        if not self._auth():
            self._json(401, {"ok": False, "error": "unauthorized"})
            return
        if not ALLOWED_HOSTS:
            self._json(503, {"ok": False, "error": "allowed_hosts_empty"})
            return
        n = int(self.headers.get("Content-Length", "0") or 0)
        if n <= 0 or n > 2_000_000:
            self._json(400, {"ok": False, "error": "bad_body_size"})
            return
        try:
            req = json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            self._json(400, {"ok": False, "error": "invalid_json"})
            return
        url = str(req.get("url") or "")
        method = str(req.get("method") or "POST").upper()
        headers_in = req.get("headers") or {}
        body = req.get("body")
        from urllib.parse import urlparse
        p = urlparse(url)
        if p.scheme != "https" or not p.hostname:
            self._json(400, {"ok": False, "error": "https_required"})
            return
        host = p.hostname.lower()
        if host not in ALLOWED_HOSTS:
            self._json(403, {"ok": False, "error": "host_not_allowed"})
            return
        if method not in ("GET", "POST", "PUT"):
            self._json(400, {"ok": False, "error": "method"})
            return
        out_headers = {}
        if isinstance(headers_in, dict):
            for k, v in headers_in.items():
                lk = str(k).lower()
                if lk in ("host", "content-length", "connection", "transfer-encoding"):
                    continue
                # Authorization DPD (e outros) vêm do Edge; não são escritos nos logs
                out_headers[str(k)] = str(v)
        data = None
        if body is not None and method != "GET":
            data = body if isinstance(body, (bytes, bytearray)) else (
                body.encode("utf-8") if isinstance(body, str) else json.dumps(body).encode("utf-8")
            )
        ureq = urllib.request.Request(url, data=data, method=method, headers=out_headers)
        ctx = ssl.create_default_context()
        try:
            with urllib.request.urlopen(ureq, timeout=45, context=ctx) as resp:
                raw = resp.read()
                # não devolver headers sensíveis upstream na totalidade ao log
                self._json(200, {
                    "ok": True,
                    "status": getattr(resp, "status", 200),
                    "body_b64": __import__("base64").b64encode(raw).decode("ascii"),
                    "content_type": resp.headers.get("Content-Type"),
                })
        except urllib.error.HTTPError as e:
            raw = e.read() if hasattr(e, "read") else b""
            self._json(200, {
                "ok": True,
                "status": e.code,
                "body_b64": __import__("base64").b64encode(raw).decode("ascii"),
                "content_type": e.headers.get("Content-Type") if e.headers else None,
            })
        except Exception as e:
            self._json(502, {"ok": False, "error": "upstream_failed", "detail": type(e).__name__})

if __name__ == "__main__":
    ThreadingHTTPServer(LISTEN, Handler).serve_forever()
PY
chmod 755 /usr/local/bin/fleaber-dpd-proxy.py

cat > /etc/systemd/system/fleaber-dpd-proxy.service << EOF
[Unit]
Description=Fleaber DPD HTTPS forward proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=FLEABER_DPD_ALLOWED_HOSTS=
ExecStart=/usr/bin/python3 /usr/local/bin/fleaber-dpd-proxy.py
Restart=always
RestartSec=3
User=www-data
Group=www-data
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/log/fleaber-dpd
ReadOnlyPaths=/etc/fleaber-dpd
AmbientCapabilities=
CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
EOF

# www-data precisa ler o bearer
chgrp www-data /etc/fleaber-dpd /etc/fleaber-dpd/proxy_bearer
chmod 640 /etc/fleaber-dpd/proxy_bearer
chmod 750 /etc/fleaber-dpd

systemctl daemon-reload
systemctl enable --now fleaber-dpd-proxy.service

# nginx HTTP primeiro (certbot injeta TLS)
mkdir -p /var/www/html
cat > /etc/nginx/sites-available/fleaber-dpd-proxy << NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    server_tokens off;
    client_max_body_size 2m;
    access_log /var/log/fleaber-dpd/access.log;
    error_log  /var/log/fleaber-dpd/error.log warn;

    location /.well-known/acme-challenge/ { root /var/www/html; }

    location = /health {
        proxy_pass http://127.0.0.1:8088/health;
    }
    location = /egress {
        proxy_pass http://127.0.0.1:8088/egress;
        proxy_set_header Authorization \$http_authorization;
    }
    location = /forward {
        proxy_pass http://127.0.0.1:8088/forward;
        proxy_set_header Authorization \$http_authorization;
        proxy_read_timeout 60s;
    }
    location / { return 404; }
}
NGINX

ln -sfn /etc/nginx/sites-available/fleaber-dpd-proxy /etc/nginx/sites-enabled/fleaber-dpd-proxy
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# UFW
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# TLS Let's Encrypt
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect
nginx -t
systemctl reload nginx

# smoke tests (sem DPD real)
systemctl --no-pager --full status fleaber-dpd-proxy | head -20
curl -fsS "http://127.0.0.1:8088/health"
echo
BEARER="$(cat /etc/fleaber-dpd/proxy_bearer)"
curl -fsS -H "Authorization: Bearer ${BEARER}" "http://127.0.0.1:8088/egress"
echo
curl -fsS -H "Authorization: Bearer ${BEARER}" "https://${DOMAIN}/egress"
echo
# /forward sem allowlist → 503 esperado
curl -sS -o /tmp/fwd.json -w "forward_http=%{http_code}\n" -H "Authorization: Bearer ${BEARER}" -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/","method":"GET"}' "https://${DOMAIN}/forward" || true
cat /tmp/fwd.json; echo

EGRESS=$(curl -fsS https://api.ipify.org || true)
echo "EGRESS_IP_MEASURED=${EGRESS}"
echo "DOMAIN=${DOMAIN}"
echo "BEARER_FILE=/etc/fleaber-dpd/proxy_bearer"
echo "OK install base"
