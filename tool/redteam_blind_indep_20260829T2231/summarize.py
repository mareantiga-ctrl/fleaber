import json
from pathlib import Path

d = json.loads(
    Path("tool/redteam_blind_indep_20260829T2231/out/results_20260829T213957Z.json").read_text(
        encoding="utf-8"
    )
)
keys = (
    "CHECKOUT",
    "ORDERS",
    "QTY",
    "PRICE",
    "OFFERS",
    "PAYOUT",
    "TIPS",
    "BAG",
    "WALLET",
    "ORDER_FSM",
    "AUTHORITY",
    "REVIEWS",
    "LIVE",
    "STORAGE",
    "STRIPE",
    "WEBHOOK",
    "PRIVACY",
    "STOCK",
    "AUTH",
    "RPC/batata_credit",
    "RPC/batata_release",
    "RPC/batata_wallet",
    "RPC/batata_payout",
    "RPC/batata_find",
    "RPC/batata_seller",
    "RPC/batata_ensure",
    "RPC/batata_mark",
    "EDGE/create-payment",
    "EDGE/refund",
    "EDGE/stripe",
    "EDGE/sec-fase",
    "EDGE/delete",
)
for m in d["matrix"]:
    s = m["surface"]
    interesting = m["severity"] in ("P0", "P1", "P2") or any(k in s for k in keys)
    if not interesting:
        continue
    if m["severity"] == "INFO" and s.startswith("EDGE/") and "fase2" not in m["attack"] and "webhook" not in m["attack"] and "settle" not in m["attack"]:
        continue
    print(f"[{m['severity']}] {s} | {m['attack'][:90]}")
    print("   ", str(m["result"])[:240].replace("\n", " "))
    print()

print("==== STRIPE_TEST ====")
for s in d.get("stripe_test") or []:
    print(s.get("kind"), s.get("label"), s.get("http"), str(s.get("body"))[:400])
    print()
