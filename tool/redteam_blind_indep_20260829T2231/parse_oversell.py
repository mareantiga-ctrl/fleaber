#!/usr/bin/env python3
import json
from pathlib import Path
p = Path("tool/redteam_blind_indep_20260829T2231/out/pass3_20260829T214723Z.json")
log = json.loads(p.read_text(encoding="utf-8"))
for row in log:
    if row.get("k") == "e2e_oversell_two":
        b = row["body"]
        print("keys", list(b) if isinstance(b, dict) else type(b))
        print(json.dumps(b, indent=2, default=str)[:4000])
    if row.get("k") == "patch_contract":
        print("PATCH CONTRACT", json.dumps(row, default=str)[:1500])
    if row.get("k") == "escalate_aguarda":
        sts = []
        for c, r in row["results"]:
            if isinstance(r, dict):
                sts.append(r.get("status"))
        print("buyer escalate statuses", sts)
    if row.get("k") == "seller_escalate_reservado":
        sts = []
        for c, r in row["results"]:
            if isinstance(r, dict):
                sts.append((c, r.get("status"), r.get("id")))
        print("seller escalate", sts)
