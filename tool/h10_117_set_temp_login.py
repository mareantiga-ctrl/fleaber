#!/usr/bin/env python3
"""Define password temporaria so para captura Playwright H10 117. NAO incluir no ZIP."""
import json
import secrets
import string
import urllib.request
from pathlib import Path

env = {}
for line in Path("tool/live_ops_production.env").read_text(encoding="utf-8").splitlines():
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()

url = env["SUPABASE_URL"]
key = env["SUPABASE_SERVICE_ROLE_KEY"]
uid = "08c9dca8-3707-4ee5-9f43-b33293085d6a"
alphabet = string.ascii_letters + string.digits
password = "H10-" + "".join(secrets.choice(alphabet) for _ in range(14))

body = json.dumps({"password": password}).encode()
req = urllib.request.Request(
    f"{url}/auth/v1/admin/users/{uid}",
    data=body,
    headers={
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    },
    method="PUT",
)
with urllib.request.urlopen(req, timeout=30) as resp:
    print("status", resp.status)

out = Path("tool/reports/fleahub_h10_mensagens_117_2026-10-26/_temp_login_DO_NOT_ZIP.json")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(
    json.dumps(
        {"email": "mareantiga@gmail.com", "password": password, "note": "temporaria UI 117"},
        indent=2,
    ),
    encoding="utf-8",
)
print("wrote", out)
