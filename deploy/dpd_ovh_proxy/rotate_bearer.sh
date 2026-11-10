#!/bin/bash
set -euo pipefail
openssl rand -hex 32 | tee /etc/fleaber-dpd/proxy_bearer >/dev/null
chmod 640 /etc/fleaber-dpd/proxy_bearer
chgrp www-data /etc/fleaber-dpd/proxy_bearer
systemctl restart fleaber-dpd-proxy
sleep 1
B="$(cat /etc/fleaber-dpd/proxy_bearer)"
code="$(curl -fsS -o /tmp/eg.json -w '%{http_code}' -H "Authorization: Bearer ${B}" https://vps-27d76f35.vps.ovh.net/egress || true)"
echo "egress_https_code=${code}"
python3 - <<'PY'
import json
print(json.load(open("/tmp/eg.json")))
PY
curl -fsS https://vps-27d76f35.vps.ovh.net/health
echo
echo BEARER_ROTATED_OK
