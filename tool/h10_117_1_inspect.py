#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json, urllib.request
from pathlib import Path

env = {}
for line in Path("tool/live_ops_production.env").read_text(encoding="utf-8").splitlines():
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
url, key = env["SUPABASE_URL"], env["SUPABASE_SERVICE_ROLE_KEY"]
CHAT = "84cd817c-9068-4d0b-960a-8d41110da40b"
h = {"apikey": key, "Authorization": f"Bearer {key}"}

def get(path):
    req = urllib.request.Request(url + path, headers=h)
    return json.loads(urllib.request.urlopen(req).read().decode())

msgs = get(f"/rest/v1/chat_messages?chat_id=eq.{CHAT}&select=id,text,created_at,sender_id&order=created_at.asc")
print("count", len(msgs))
for m in msgs:
    t = m["text"] or ""
    flag = ""
    if "fleaber_res" in t or "H10" in t or "H116" in t or "seed" in t.lower() or "[[[" in t or "Cancelar" in t or "cancel_request" in t or "chat_image" in t or "bundle" in t or "demonstr" in t.lower() or "layout" in t.lower() or "TESTE" in t:
        flag = " ***"
    preview = t.replace("\n", " | ")[:160]
    print(f"{m['id']:4} {m['created_at'][11:19]}{flag} {preview}")
