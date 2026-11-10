#!/usr/bin/env python3
"""Create two live Checkout Sessions for stock=1 race orders; save full URLs."""
from __future__ import annotations

import json
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = ROOT / "tool" / "live_ops_staging.env"
OUT = Path(__file__).resolve().parent / "out"


def load_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def norm_url(raw: str) -> str:
    u = raw.strip().rstrip("/")
    for suf in ("/rest/v1", "/auth/v1", "/functions/v1"):
        if u.endswith(suf):
            u = u[: -len(suf)].rstrip("/")
    return u


def http(method, url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=60) as resp:
            text = resp.read().decode("utf-8", "replace")
            return resp.status, json.loads(text) if text else None, text
    except HTTPError as e:
        text = e.read().decode("utf-8", "replace")
        try:
            parsed = json.loads(text) if text else None
        except json.JSONDecodeError:
            parsed = None
        return e.code, parsed, text


def main():
    env = load_env(ENV_PATH)
    url = norm_url(env["SUPABASE_URL"])
    anon = env["SUPABASE_ANON_KEY"]
    buyer_id = env["LIVE_OPS_TEST_BUYER_ID"]
    st, body, _ = http(
        "POST",
        f"{url}/auth/v1/token?grant_type=password",
        {"apikey": anon, "Content-Type": "application/json"},
        {"email": env["LIVE_OPS_TEST_BUYER_EMAIL"], "password": env["LIVE_OPS_TEST_BUYER_PASSWORD"]},
    )
    tok = body["access_token"]
    H = {
        "apikey": anon,
        "Authorization": f"Bearer {tok}",
        "Content-Type": "application/json",
    }
    orders = [
        "9d73a949-b175-4436-a34c-4dbc89b5ffa2",
        "9b0f9153-e77e-4c08-9ec1-823a39b1e55b",
    ]
    out = []
    for oid in orders:
        st, parsed, text = http(
            "POST",
            f"{url}/functions/v1/create-payment-intent",
            H,
            {
                "buyer_id": buyer_id,
                "order_id": oid,
                "shipping_method": "hand",
                "amount": 1,
            },
        )
        rec = {
            "order_id": oid,
            "http": st,
            "checkoutUrl": (parsed or {}).get("checkoutUrl") if isinstance(parsed, dict) else None,
            "checkoutSessionId": (parsed or {}).get("checkoutSessionId") if isinstance(parsed, dict) else None,
            "server_amount_cents": (parsed or {}).get("server_amount_cents") if isinstance(parsed, dict) else None,
            "text_len": len(text),
        }
        if rec["checkoutUrl"]:
            rec["url_len"] = len(rec["checkoutUrl"])
        out.append(rec)
        print(json.dumps({k: rec[k] for k in rec if k != "checkoutUrl"}))
        if rec["checkoutUrl"]:
            print("URL", rec["checkoutUrl"])
            print("---")
    dest = OUT / "fresh_sessions_stock1.json"
    dest.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print("wrote", dest)


if __name__ == "__main__":
    main()
