#!/usr/bin/env python3
import json
import urllib.request
from pathlib import Path

env = {}
for line in Path("tool/live_ops_production.env").read_text(encoding="utf-8").splitlines():
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()

url = env["SUPABASE_URL"]
key = env["SUPABASE_SERVICE_ROLE_KEY"]
print("url", url)

req = urllib.request.Request(
    url + "/storage/v1/bucket",
    headers={"apikey": key, "Authorization": "Bearer " + key},
)
print("buckets", urllib.request.urlopen(req).read().decode()[:1000])

# existing chat_image samples
q = "/rest/v1/chat_messages?text=like.*chat_image*&select=id,text&limit=3"
req2 = urllib.request.Request(
    url + q,
    headers={"apikey": key, "Authorization": "Bearer " + key},
)
print("samples", urllib.request.urlopen(req2).read().decode()[:1200])

# create bucket if missing
body = json.dumps(
    {"id": "fleaber_private", "name": "fleaber_private", "public": False}
).encode()
req3 = urllib.request.Request(
    url + "/storage/v1/bucket",
    data=body,
    headers={
        "apikey": key,
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
    },
    method="POST",
)
try:
    print("create", urllib.request.urlopen(req3).read().decode()[:400])
except Exception as e:
    print("create err", getattr(e, "read", lambda: b"")().decode()[:400], e)
