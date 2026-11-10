#!/usr/bin/env python3
"""RI-E / RI-B reteste independente — staging LIVE. Sem SQL, sem deploy, sem C1."""
from __future__ import annotations

import atexit
import json
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
TAG = f"RI_INDEP_{int(time.time())}_{uuid.uuid4().hex[:6]}"
STAGING = "fxdknzrqjenzqcvnwqqq"
EV_PATH = ROOT / "tool" / "reports" / "RI_RETESTE_INDEP_20260827_EVIDENCE.json"


def load_env() -> dict[str, str]:
    out: dict[str, str] = {}
    for line in (ROOT / "tool" / "live_ops_staging.env").read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        k, v = t.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def req(method: str, url: str, token: str, body=None, timeout=60):
    headers = {
        "apikey": ANON if token != SVC else SVC,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    data = None if body is None else json.dumps(body).encode()
    r = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
            parsed = json.loads(raw) if raw else None
            return {"http": resp.status, "body": parsed, "raw": raw[:2500]}
    except HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = raw
        return {"http": e.code, "body": parsed, "raw": raw[:2500]}
    except URLError as e:
        return {"http": 0, "body": {"error": str(e.reason)}, "raw": str(e)}


def rest(method, path, tok, body=None, qs=""):
    return req(method, f"{URL}/rest/v1/{path}" + (f"?{qs}" if qs else ""), tok, body)


def rpc(name, tok, body):
    return req("POST", f"{URL}/rest/v1/rpc/{name}", tok, body)


def login(email, pw):
    r = req(
        "POST",
        f"{URL}/auth/v1/token?grant_type=password",
        ANON,
        {"email": email, "password": pw},
    )
    tok = (r.get("body") or {}).get("access_token") if isinstance(r.get("body"), dict) else None
    if not tok:
        raise SystemExit(f"login fail {email}: {r}")
    return tok


def row(res):
    b = res.get("body")
    if isinstance(b, list) and b and isinstance(b[0], dict):
        return b[0]
    if isinstance(b, dict) and b.get("id"):
        return b
    return None


def get_req(rid, tok=None):
    return row(rest("GET", "live_reservation_requests", tok or SVC, qs=f"id=eq.{rid}&select=*"))


def get_reviews(oid):
    r = rest("GET", "reviews", SVC, qs=f"order_id=eq.{oid}&select=id,buyer_id,author_role,stars,order_id,target_id,is_automatic")
    b = r.get("body")
    return b if isinstance(b, list) else []


def avail(liid, exclude=None):
    body = {"p_live_item_id": liid}
    if exclude:
        body["p_exclude_request_id"] = exclude
    return rpc("batata_live_reservation_accept_available", SELLER, body)


def rec(out, key, payload):
    out[key] = payload
    print(f"  {key}: http={payload.get('http')} {str(payload.get('verdict') or payload.get('raw') or '')[:120]}")


def main():
    global URL, ANON, SVC, BUYER, SELLER, BUYER_ID, SELLER_ID
    env = load_env()
    URL = env["SUPABASE_URL"].strip().rstrip("/")
    for s in ("/rest/v1", "/auth/v1", "/functions/v1"):
        if URL.endswith(s):
            URL = URL[: -len(s)].rstrip("/")
    if STAGING not in URL:
        raise SystemExit("ABORT not staging")
    ANON = env["SUPABASE_ANON_KEY"]
    SVC = env["SUPABASE_SERVICE_ROLE_KEY"]
    BUYER_ID = env["LIVE_OPS_TEST_BUYER_ID"]
    SELLER_ID = env["LIVE_OPS_TEST_SELLER_ID"]
    BUYER = login(env["LIVE_OPS_TEST_BUYER_EMAIL"], env["LIVE_OPS_TEST_BUYER_PASSWORD"])
    SELLER = login(env["LIVE_OPS_TEST_SELLER_EMAIL"], env["LIVE_OPS_TEST_SELLER_PASSWORD"])

    evidence = {
        "auditor": "independente",
        "tag": TAG,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "staging": STAGING,
        "production_touched": False,
        "fase4": False,
        "corrections": False,
        "ri_e": {},
        "ri_b": {},
        "cleanup": {},
    }
    live_ids = []
    product_ids = []
    order_ids = []
    wrote = {"ok": False}

    def persist():
        if wrote["ok"]:
            return
        wrote["ok"] = True
        try:
            for lid in live_ids:
                rest("PATCH", "lives", SVC, {"status": "ended", "is_active": False}, qs=f"id=eq.{lid}")
            for pid in product_ids:
                rest(
                    "PATCH",
                    "products",
                    SVC,
                    {"list_on_marketplace": False, "available_for_live": False},
                    qs=f"id=eq.{pid}",
                )
            evidence["cleanup"] = {"lives": live_ids, "products": product_ids, "orders": order_ids}
            evidence["finished_at"] = datetime.now(timezone.utc).isoformat()
            evidence["summary"] = {
                "ri_e_verdicts": {
                    k: v.get("verdict")
                    for k, v in evidence["ri_e"].items()
                    if isinstance(v, dict) and "verdict" in v
                },
                "ri_b_verdicts": {
                    k: v.get("verdict")
                    for k, v in evidence["ri_b"].items()
                    if isinstance(v, dict) and "verdict" in v
                },
            }
            dest = EV_PATH
            if dest.exists():
                dest = ROOT / "tool" / "reports" / f"RI_RETESTE_INDEP_20260827_EVIDENCE_{int(time.time())}.json"
            dest.write_text(json.dumps(evidence, indent=2, default=str), encoding="utf-8")
            print("WROTE", dest)
            print("SUMMARY_E", json.dumps(evidence["summary"]["ri_e_verdicts"]))
            print("SUMMARY_B", json.dumps(evidence["summary"]["ri_b_verdicts"]))
        except Exception as e:
            print("PERSIST_ERR", repr(e))

    atexit.register(persist)

    # ----- fixtures RI-E -----
    prod = row(
        rest(
            "POST",
            "products",
            SVC,
            {
                "seller_id": SELLER_ID,
                "title": f"{TAG} cap1",
                "price": 7,
                "quantity": 1,
                "ref_code": f"RIE-{uuid.uuid4().hex[:8]}",
                "list_on_marketplace": True,
                "available_for_live": True,
                "is_sold": False,
                "image_urls": [],
            },
        )
    )
    product_ids.append(prod["id"])
    live = row(
        rest(
            "POST",
            "lives",
            SVC,
            {
                "seller_id": SELLER_ID,
                "title": f"{TAG} live",
                "status": "ended",
                "is_active": False,
            },
        )
    )
    live_ids.append(live["id"])
    li = row(
        rest(
            "POST",
            "live_items",
            SVC,
            {
                "live_id": live["id"],
                "product_id": prod["id"],
                "title": f"{TAG} li",
                "price": 7,
                "ref_code": f"RIE-LI-{uuid.uuid4().hex[:6]}",
                "item_kind": "marketplace_product",
                "status": "available",
                "is_active": False,
            },
        )
    )
    liid = li["id"]
    evidence["ri_e"]["fixture"] = {
        "product_id": prod["id"],
        "product_qty": prod.get("quantity"),
        "live_id": live["id"],
        "live_item_id": liid,
        "available_rpc": avail(liid),
        "total_qty_rpc": rpc("batata_live_item_total_qty", SELLER, {"p_live_item_id": liid}),
        "li_row": li,
    }

    def mk_cap_item(qty=1, suffix=""):
        p = row(
            rest(
                "POST",
                "products",
                SVC,
                {
                    "seller_id": SELLER_ID,
                    "title": f"{TAG} cap{qty}{suffix}",
                    "price": 7,
                    "quantity": qty,
                    "ref_code": f"RIE-{uuid.uuid4().hex[:8]}",
                    "list_on_marketplace": True,
                    "available_for_live": True,
                    "is_sold": False,
                    "image_urls": [],
                },
            )
        )
        product_ids.append(p["id"])
        item = row(
            rest(
                "POST",
                "live_items",
                SVC,
                {
                    "live_id": live["id"],
                    "product_id": p["id"],
                    "title": f"{TAG} li{suffix}",
                    "price": 7,
                    "ref_code": f"RIE-LI-{uuid.uuid4().hex[:6]}",
                    "item_kind": "marketplace_product",
                    "status": "available",
                    "is_active": False,
                },
            )
        )
        return p, item

    def ins_pending_on(item_id, qty, status="pending"):
        r = rest(
            "POST",
            "live_reservation_requests",
            BUYER,
            {
                "live_id": live["id"],
                "live_item_id": item_id,
                "buyer_id": BUYER_ID,
                "seller_id": SELLER_ID,
                "requested_qty": qty,
                "status": status,
                "source": "fleaber_live",
            },
        )
        rr = row(r)
        if not rr:
            print("INS_PENDING_FAIL", r.get("http"), str(r.get("raw", ""))[:220])
        return r, rr

    def ins_pending(qty, status="pending"):
        r, _ = ins_pending_on(liid, qty, status)
        return r

    # E6 INSERT buyer accepted qty 9
    e6 = ins_pending(9, "accepted")
    e6row = row(e6)
    rec(
        evidence["ri_e"],
        "E6_buyer_insert_accepted_qty9",
        {
            "http": e6["http"],
            "request": {"status": "accepted", "requested_qty": 9, "actor": "buyer_jwt"},
            "after": e6row,
            "verdict": "BLOCKED"
            if e6row and str(e6row.get("status")).lower() == "pending"
            else "OPEN",
        },
    )

    # E1 PATCH status=accepted keep qty=9
    p9 = row(ins_pending(9))
    before_e1 = get_req(p9["id"])
    e1 = rest("PATCH", "live_reservation_requests", SELLER, {"status": "accepted"}, qs=f"id=eq.{p9['id']}")
    after_e1 = get_req(p9["id"])
    rec(
        evidence["ri_e"],
        "E1_seller_patch_accepted_keep_qty9",
        {
            "http": e1["http"],
            "raw": e1["raw"][:400],
            "before": before_e1,
            "after": after_e1,
            "available_before": avail(liid, p9["id"]),
            "verdict": "BLOCKED"
            if after_e1 and str(after_e1.get("status")).lower() != "accepted"
            else "OPEN",
        },
    )

    # E2 PATCH accepted + qty=9
    p9b = row(ins_pending(9)) if after_e1 and str(after_e1.get("status")).lower() != "accepted" else p9
    if p9b["id"] == p9["id"] and str((after_e1 or {}).get("status")).lower() == "accepted":
        p9b = row(ins_pending(9))
    e2 = rest(
        "PATCH",
        "live_reservation_requests",
        SELLER,
        {"status": "accepted", "requested_qty": 9},
        qs=f"id=eq.{p9b['id']}",
    )
    after_e2 = get_req(p9b["id"])
    rec(
        evidence["ri_e"],
        "E2_seller_patch_accepted_and_qty9",
        {
            "http": e2["http"],
            "raw": e2["raw"][:400],
            "after": after_e2,
            "verdict": "BLOCKED"
            if after_e2 and str(after_e2.get("status")).lower() != "accepted"
            else "OPEN",
        },
    )

    # E3 qty=2 available=1
    p2 = row(ins_pending(2))
    e3 = rest(
        "PATCH",
        "live_reservation_requests",
        SELLER,
        {"status": "accepted", "requested_qty": 2},
        qs=f"id=eq.{p2['id']}",
    )
    after_e3 = get_req(p2["id"])
    rec(
        evidence["ri_e"],
        "E3_seller_patch_qty2_avail1",
        {
            "http": e3["http"],
            "raw": e3["raw"][:400],
            "after": after_e3,
            "verdict": "BLOCKED"
            if after_e3 and str(after_e3.get("status")).lower() != "accepted"
            else "OPEN",
        },
    )

    # aliases of accepted
    palias = row(ins_pending(9))
    alias_results = []
    for st in ("ACCEPTED", "Accepted", " accepted ", "aceite", "converted"):
        r = rest("PATCH", "live_reservation_requests", SELLER, {"status": st}, qs=f"id=eq.{palias['id']}")
        after = get_req(palias["id"])
        alias_results.append(
            {
                "try": st,
                "http": r["http"],
                "status_after": (after or {}).get("status"),
                "qty_after": (after or {}).get("requested_qty"),
            }
        )
    rec(
        evidence["ri_e"],
        "E1b_status_aliases",
        {
            "tries": alias_results,
            "verdict": "BLOCKED"
            if all(str(x["status_after"]).lower() != "accepted" for x in alias_results)
            else "OPEN",
        },
    )

    # E5 buyer PATCH pending→accepted
    pb = row(ins_pending(1))
    e5 = rest("PATCH", "live_reservation_requests", BUYER, {"status": "accepted"}, qs=f"id=eq.{pb['id']}")
    after_e5 = get_req(pb["id"])
    rec(
        evidence["ri_e"],
        "E5_buyer_patch_accepted",
        {
            "http": e5["http"],
            "raw": e5["raw"][:300],
            "after": after_e5,
            "verdict": "BLOCKED"
            if after_e5 and str(after_e5.get("status")).lower() != "accepted"
            else "OPEN",
        },
    )

    # E4 PATCH qty=1 available=1 on a CLEAN item (no leftover waitlist)
    prod_e4, li_e4 = mk_cap_item(1, suffix="-e4")
    _, p1 = ins_pending_on(li_e4["id"], 1)
    e4_avail = avail(li_e4["id"], p1["id"] if p1 else None)
    e4 = rest("PATCH", "live_reservation_requests", SELLER, {"status": "accepted"}, qs=f"id=eq.{p1['id']}")
    after_e4 = get_req(p1["id"])
    rec(
        evidence["ri_e"],
        "E4_seller_patch_qty1_avail1",
        {
            "http": e4["http"],
            "raw": e4["raw"][:500],
            "available_rpc": e4_avail,
            "total_qty_rpc": rpc("batata_live_item_total_qty", SELLER, {"p_live_item_id": li_e4["id"]}),
            "product_now": row(rest("GET", "products", SVC, qs=f"id=eq.{prod_e4['id']}&select=id,quantity")),
            "open_rows": rest(
                "GET",
                "live_reservation_requests",
                SVC,
                qs=f"live_item_id=eq.{li_e4['id']}&select=id,status,requested_qty",
            ).get("body"),
            "after": after_e4,
            "verdict": "OK"
            if after_e4 and str(after_e4.get("status")).lower() == "accepted" and int(after_e4.get("requested_qty") or 0) == 1
            else "FAIL_HAPPY",
        },
    )

    # RPC accept legit on a second clean item
    _, li_rpc = mk_cap_item(1, suffix="-rpc")
    _, p_rpc = ins_pending_on(li_rpc["id"], 1)
    rpc_acc = rpc(
        "batata_process_live_reservation_request",
        SELLER,
        {"p_request_id": p_rpc["id"], "p_action": "accept"},
    )
    after_rpc = get_req(p_rpc["id"])
    rec(
        evidence["ri_e"],
        "E4b_rpc_accept_qty1",
        {
            "http": rpc_acc["http"],
            "body": rpc_acc.get("body"),
            "raw": rpc_acc["raw"][:500],
            "after": after_rpc,
            "verdict": "OK"
            if after_rpc and str(after_rpc.get("status")).lower() == "accepted"
            else "FAIL_HAPPY",
        },
    )

    # RPC accept of qty=9 pending
    p_rpc9 = p9b if str((after_e2 or {}).get("status")).lower() != "accepted" else row(ins_pending(9))
    rpc9 = rpc(
        "batata_process_live_reservation_request",
        SELLER,
        {"p_request_id": p_rpc9["id"], "p_action": "accept"},
    )
    after_rpc9 = get_req(p_rpc9["id"])
    rec(
        evidence["ri_e"],
        "E1c_rpc_accept_qty9",
        {
            "http": rpc9["http"],
            "body": rpc9.get("body"),
            "raw": rpc9["raw"][:400],
            "after": after_rpc9,
            "verdict": "BLOCKED"
            if after_rpc9 and str(after_rpc9.get("status")).lower() != "accepted"
            else "OPEN",
        },
    )

    # E8 pending alto presente + accept qty=1 que cabe (PATCH: pending não conta na capacidade C1)
    _, li_e8 = mk_cap_item(1, suffix="-e8")
    _, wait = ins_pending_on(li_e8["id"], 9)
    _, legit = ins_pending_on(li_e8["id"], 1)
    e8 = rest("PATCH", "live_reservation_requests", SELLER, {"status": "accepted"}, qs=f"id=eq.{legit['id']}")
    after_wait = get_req(wait["id"])
    after_legit = get_req(legit["id"])
    rec(
        evidence["ri_e"],
        "E8_waitlist_plus_legit_accept",
        {
            "http": e8["http"],
            "raw": e8["raw"][:400],
            "waitlist_after": after_wait,
            "legit_after": after_legit,
            "waitlist_still_pending": after_wait and str(after_wait.get("status")).lower() == "pending",
            "legit_accepted": after_legit and str(after_legit.get("status")).lower() == "accepted",
            "verdict": "OK"
            if (
                after_wait
                and str(after_wait.get("status")).lower() == "pending"
                and after_legit
                and str(after_legit.get("status")).lower() == "accepted"
            )
            else "FAIL_HAPPY_OR_OPEN",
        },
    )

    # E7 two concurrent PATCH accepted qty=1 stock=1 on CLEAN item
    _, li_e7 = mk_cap_item(1, suffix="-e7")
    _, c1 = ins_pending_on(li_e7["id"], 1)
    _, c2 = ins_pending_on(li_e7["id"], 1)

    def patch_acc(rid):
        return rest("PATCH", "live_reservation_requests", SELLER, {"status": "accepted"}, qs=f"id=eq.{rid}")

    with ThreadPoolExecutor(max_workers=2) as ex:
        f1, f2 = ex.submit(patch_acc, c1["id"]), ex.submit(patch_acc, c2["id"])
        r1, r2 = f1.result(), f2.result()
    a1, a2 = get_req(c1["id"]), get_req(c2["id"])
    accepted_rows = [x for x in (a1, a2) if x and str(x.get("status")).lower() in ("accepted", "converted")]
    sum_acc = sum(int(x.get("requested_qty") or 0) for x in accepted_rows)
    rec(
        evidence["ri_e"],
        "E7_concurrent_two_accept_qty1",
        {
            "http": [r1["http"], r2["http"]],
            "raw": [r1["raw"][:250], r2["raw"][:250]],
            "after": [a1, a2],
            "sum_accepted_qty": sum_acc,
            "n_accepted": len(accepted_rows),
            "capacity": 1,
            "verdict": "OPEN" if sum_acc > 1 else "BLOCKED",
        },
    )

    # seller INSERT accepted qty 9
    s_ins = rest(
        "POST",
        "live_reservation_requests",
        SELLER,
        {
            "live_id": live["id"],
            "live_item_id": liid,
            "buyer_id": BUYER_ID,
            "seller_id": SELLER_ID,
            "requested_qty": 9,
            "status": "accepted",
            "source": "fleaber_live",
        },
    )
    rec(
        evidence["ri_e"],
        "E_seller_insert_accepted_qty9",
        {
            "http": s_ins["http"],
            "raw": s_ins["raw"][:400],
            "after": row(s_ins),
            "verdict": "BLOCKED"
            if s_ins["http"] >= 400
            or not (row(s_ins) and str(row(s_ins).get("status")).lower() == "accepted")
            else "OPEN",
        },
    )

    # bump qty while already accepted — only score if the row was actually accepted
    _, li_bump = mk_cap_item(1, suffix="-bump")
    _, bump_src = ins_pending_on(li_bump["id"], 1)
    acc_bump = rest("PATCH", "live_reservation_requests", SELLER, {"status": "accepted"}, qs=f"id=eq.{bump_src['id']}")
    mid_bump = get_req(bump_src["id"])
    bump = rest(
        "PATCH",
        "live_reservation_requests",
        SELLER,
        {"requested_qty": 9},
        qs=f"id=eq.{bump_src['id']}",
    )
    after_bump = get_req(bump_src["id"])
    was_accepted = mid_bump and str(mid_bump.get("status")).lower() == "accepted"
    rec(
        evidence["ri_e"],
        "E_bump_qty_while_accepted",
        {
            "accept_http": acc_bump["http"],
            "accept_raw": acc_bump["raw"][:250],
            "mid": mid_bump,
            "http": bump["http"],
            "raw": bump["raw"][:300],
            "after": after_bump,
            "verdict": (
                "FAIL_HAPPY"
                if not was_accepted
                else (
                    "BLOCKED"
                    if after_bump and int(after_bump.get("requested_qty") or 0) <= 1
                    else "OPEN"
                )
            ),
        },
    )

    # ----- RI-B reviews -----
    prod2 = row(
        rest(
            "POST",
            "products",
            SVC,
            {
                "seller_id": SELLER_ID,
                "title": f"{TAG} rev",
                "price": 5,
                "quantity": 20,
                "ref_code": f"RIB-{uuid.uuid4().hex[:8]}",
                "list_on_marketplace": True,
                "is_sold": False,
                "image_urls": [],
            },
        )
    )
    product_ids.append(prod2["id"])

    def mk_eligible_order():
        created = rest(
            "POST",
            "orders",
            BUYER,
            {
                "buyer_id": BUYER_ID,
                "seller_id": SELLER_ID,
                "product_id": prod2["id"],
                "quantity": 1,
                "price_total": 5,
                "payment_method": "MB WAY",
                "status": "reserva_pendente",
            },
        )
        o = row(created)
        if not o:
            print("MK_ORDER_FAIL", created.get("http"), str(created.get("raw", ""))[:300])
            return None
        order_ids.append(o["id"])
        rest("PATCH", "orders", SELLER, {"status": "pago"}, qs=f"id=eq.{o['id']}")
        rest("PATCH", "orders", SELLER, {"status": "enviado"}, qs=f"id=eq.{o['id']}")
        rest("PATCH", "orders", BUYER, {"status": "concluido"}, qs=f"id=eq.{o['id']}")
        live_o = row(rest("GET", "orders", SVC, qs=f"id=eq.{o['id']}&select=id,status,stock_units_applied,payment_method"))
        return live_o

    o1 = mk_eligible_order()
    if not o1:
        raise RuntimeError("mk_eligible_order o1 failed")

    def ins_rev(tok, oid, role, stars=5, comment="x"):
        return rest(
            "POST",
            "reviews",
            tok,
            {
                "order_id": oid,
                "buyer_id": BUYER_ID,
                "stars": stars,
                "comment": f"{TAG} {comment}",
                "author_role": role,
            },
        )

    # B9/B4 first legit on o1
    b4 = ins_rev(BUYER, o1["id"], "comprador", 5, "legit")
    rec(
        evidence["ri_b"],
        "B9_B4_legit_comprador",
        {
            "http": b4["http"],
            "row": row(b4),
            "all": get_reviews(o1["id"]),
            "order": o1,
            "verdict": "OK"
            if b4["http"] in (200, 201)
            and row(b4)
            and str(row(b4).get("author_role")).lower() == "comprador"
            else "FAIL_HAPPY",
        },
    )

    # B1 vendedor on SAME order (should duplicate)
    b1 = ins_rev(BUYER, o1["id"], "vendedor", 1, "forge-v")
    rec(
        evidence["ri_b"],
        "B1_author_vendedor_after_comprador",
        {
            "http": b1["http"],
            "raw": b1["raw"][:400],
            "row": row(b1),
            "all": get_reviews(o1["id"]),
            "verdict": "BLOCKED"
            if b1["http"] >= 400
            and not any(str(x.get("author_role")).lower() in ("vendedor", "seller") for x in get_reviews(o1["id"]))
            else "OPEN",
        },
    )

    o2 = mk_eligible_order()
    if not o2:
        raise RuntimeError("o2")
    # B1 on fresh order first insert as vendedor
    b1f = ins_rev(BUYER, o2["id"], "vendedor", 2, "first-v")
    rec(
        evidence["ri_b"],
        "B1_fresh_insert_vendedor",
        {
            "http": b1f["http"],
            "row": row(b1f),
            "all": get_reviews(o2["id"]),
            "verdict": "BLOCKED"
            if row(b1f) and str(row(b1f).get("author_role")).lower() == "comprador"
            else ("OPEN" if row(b1f) and str(row(b1f).get("author_role")).lower() in ("vendedor", "seller") else "BLOCKED"),
        },
    )

    o3 = mk_eligible_order()
    if not o3:
        raise RuntimeError("o3")
    b2 = ins_rev(BUYER, o3["id"], "seller", 3, "seller")
    rec(
        evidence["ri_b"],
        "B2_fresh_insert_seller",
        {
            "http": b2["http"],
            "row": row(b2),
            "all": get_reviews(o3["id"]),
            "verdict": "BLOCKED"
            if not row(b2) or str(row(b2).get("author_role")).lower() == "comprador"
            else "OPEN",
        },
    )

    o4 = mk_eligible_order()
    if not o4:
        raise RuntimeError("o4")
    b3 = ins_rev(BUYER, o4["id"], "buyer", 4, "buyer")
    rec(
        evidence["ri_b"],
        "B3_fresh_insert_buyer",
        {
            "http": b3["http"],
            "row": row(b3),
            "all": get_reviews(o4["id"]),
            "verdict": "OK"
            if row(b3) and str(row(b3).get("author_role")).lower() == "comprador"
            else "FAIL_HAPPY",
        },
    )

    # B5 aliases — first review already on o2; use o3 which has seller→comprador
    o5 = mk_eligible_order()
    if not o5:
        raise RuntimeError("o5")
    alias_out = []
    first = True
    for role in ("BUYER", "Buyer", " buyer ", "VENDEDOR", "Seller", " vendedor ", "SELLER", "Comprador"):
        r = ins_rev(BUYER, o5["id"], role, 5, f"alias-{role.strip()}")
        rows = get_reviews(o5["id"])
        alias_out.append(
            {
                "try": role,
                "http": r["http"],
                "persisted_role": (row(r) or {}).get("author_role"),
                "n_reviews": len(rows),
                "roles": [x.get("author_role") for x in rows],
            }
        )
        first = False
    n5 = len(get_reviews(o5["id"]))
    rec(
        evidence["ri_b"],
        "B5_aliases",
        {
            "tries": alias_out,
            "final_n": n5,
            "final_roles": [x.get("author_role") for x in get_reviews(o5["id"])],
            "verdict": "BLOCKED" if n5 <= 1 and not any(str(x).lower() in ("vendedor", "seller") for x in [y.get("author_role") for y in get_reviews(o5["id"])]) else "OPEN",
        },
    )

    # B6 race two INSERT
    o6 = mk_eligible_order()
    if not o6:
        raise RuntimeError("o6")

    def ins_role(role):
        return ins_rev(BUYER, o6["id"], role, 5, f"race-{role}")

    with ThreadPoolExecutor(max_workers=2) as ex:
        g1, g2 = ex.submit(ins_role, "buyer"), ex.submit(ins_role, "comprador")
        race_res = [g1.result(), g2.result()]
    final6 = get_reviews(o6["id"])
    rec(
        evidence["ri_b"],
        "B6_race_buyer_vs_comprador",
        {
            "http": [x["http"] for x in race_res],
            "raw": [x["raw"][:200] for x in race_res],
            "rows_echo": [row(x) for x in race_res],
            "final": final6,
            "n": len(final6),
            "verdict": "BLOCKED" if len(final6) <= 1 else "OPEN",
        },
    )

    # B7 UPDATE author_role then insert
    o7 = mk_eligible_order()
    if not o7:
        raise RuntimeError("o7")
    first7 = ins_rev(BUYER, o7["id"], "comprador", 5, "u1")
    rid = (row(first7) or {}).get("id")
    upd = rest("PATCH", "reviews", BUYER, {"author_role": "vendedor"}, qs=f"id=eq.{rid}") if rid else {"http": 0, "raw": "no id"}
    after_upd = get_reviews(o7["id"])
    second7 = ins_rev(BUYER, o7["id"], "comprador", 1, "u2")
    rec(
        evidence["ri_b"],
        "B7_update_role_then_second_insert",
        {
            "first_http": first7["http"],
            "update_http": upd.get("http"),
            "update_raw": str(upd.get("raw", ""))[:250],
            "roles_after_update": [x.get("author_role") for x in after_upd],
            "second_http": second7["http"],
            "second_raw": second7["raw"][:250],
            "final": get_reviews(o7["id"]),
            "verdict": "BLOCKED"
            if len(get_reviews(o7["id"])) == 1
            and str((get_reviews(o7["id"])[0] or {}).get("author_role")).lower() == "comprador"
            else "OPEN",
        },
    )

    # B8 seller JWT forge
    o8 = mk_eligible_order()
    if not o8:
        raise RuntimeError("o8")
    srev = rest(
        "POST",
        "reviews",
        SELLER,
        {
            "order_id": o8["id"],
            "buyer_id": BUYER_ID,
            "stars": 5,
            "comment": f"{TAG} seller-forge",
            "author_role": "comprador",
        },
    )
    rec(
        evidence["ri_b"],
        "B8_seller_jwt_forge_buyer",
        {
            "http": srev["http"],
            "raw": srev["raw"][:400],
            "row": row(srev),
            "all": get_reviews(o8["id"]),
            "verdict": "BLOCKED" if srev["http"] >= 400 and len(get_reviews(o8["id"])) == 0 else "OPEN",
        },
    )

    persist()


if __name__ == "__main__":
    main()
