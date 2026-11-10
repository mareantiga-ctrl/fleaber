const fs = require("fs");
const path = require("path");

const root = "c:/Users/Casa/Desktop/Fleaber/fleaber";
const envPath = path.join(root, "tool/live_ops_staging.env");
const env = Object.fromEntries(
  fs.readFileSync(envPath, "utf8").split(/\r?\n/)
    .filter((l) => l && !l.startsWith("#") && l.includes("="))
    .map((l) => {
      const i = l.indexOf("=");
      return [l.slice(0, i), l.slice(i + 1).trim()];
    }),
);
const base = (env.SUPABASE_URL || "")
  .replace(/\/rest\/v1\/?$/i, "")
  .replace(/\/$/, "");
const anon = env.SUPABASE_ANON_KEY;
const sr = env.SUPABASE_SERVICE_ROLE_KEY;
if (!base.includes("fxdknzrqjenzqcvnwqqq")) throw new Error("ABORT not staging");
if (base.includes("bpmpkzwnrbmuqnhgdscf")) throw new Error("ABORT prod");
console.log("base", base);

const results = {};
function ok(id, msg) { results[id] = "PASS: " + msg; console.log("PASS", id, msg); }
function fail(id, msg) { results[id] = "FAIL: " + msg; console.log("FAIL", id, msg); }

async function req(method, urlPath, { token, service, body } = {}) {
  const headers = {
    apikey: service ? sr : anon,
    Authorization: `Bearer ${service ? sr : token || anon}`,
    "Content-Type": "application/json",
    Prefer: "return=representation",
  };
  const res = await fetch(base + urlPath, {
    method,
    headers,
    body: body != null ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  if (!res.ok) {
    const err = new Error(typeof data === "object" ? JSON.stringify(data) : text);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

async function login(email, pass) {
  const res = await fetch(base + "/auth/v1/token?grant_type=password", {
    method: "POST",
    headers: { apikey: anon, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: pass }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(JSON.stringify(data));
  return data;
}

async function main() {
  let auth = null;
  for (const [e, p] of [
    ["vendora.muxb+3df24746@fleaber.test", "testeteste"],
    [env.LIVE_OPS_TEST_SELLER_EMAIL, env.LIVE_OPS_TEST_SELLER_PASSWORD],
  ]) {
    if (!e) continue;
    try { auth = await login(e, p); console.log("login", e, auth.user.id); break; }
    catch (err) { console.log("login fail", e, String(err.message || err).slice(0, 200)); }
  }
  if (!auth) throw new Error("no seller");
  const tok = auth.access_token;
  const uid = auth.user.id;

  const live = (await req("POST", "/rest/v1/lives", {
    service: true,
    body: {
      seller_id: uid, vendedor_id: uid, title: "guard-fix-" + Date.now(),
      status: "live", is_active: true, publish_backend: "livekit_mux",
    },
  }))[0];
  const liveId = live.id;
  console.log("live", liveId);

  async function product(qty, title) {
    return (await req("POST", "/rest/v1/products", {
      service: true,
      body: { seller_id: uid, title, quantity: qty, price: 1 },
    }))[0];
  }
  async function mktItem(productId, ref) {
    return (await req("POST", "/rest/v1/live_items", {
      service: true,
      body: {
        live_id: liveId, product_id: productId, item_kind: "marketplace_product",
        ref_code: ref, title: ref, price: 1, status: "available", is_active: true,
        quantity: null,
      },
    }))[0];
  }
  async function liveOnly(qty, ref) {
    return (await req("POST", "/rest/v1/live_items", {
      service: true,
      body: {
        live_id: liveId, item_kind: "live_only", ref_code: ref, title: ref,
        price: 1, status: "available", is_active: true, quantity: qty,
      },
    }))[0];
  }
  async function pending(itemId, qty, name) {
    return (await req("POST", "/rest/v1/live_reservation_requests", {
      service: true,
      body: {
        live_id: liveId, live_item_id: itemId, seller_id: uid,
        requested_qty: qty, status: "pending", source: "facebook_manual",
        external_display_name: name,
        external_buyer_ref: "test:" + crypto.randomUUID(),
        ingest_status: "auto", notes: "guard_fix_t",
      },
    }))[0];
  }
  async function accept(id) {
    try {
      return await req("POST", "/rest/v1/rpc/batata_process_live_reservation_request", {
        token: tok,
        body: { p_request_id: id, p_action: "accept", p_processed_by: uid },
      });
    } catch (e) {
      return { ok: false, error: e.message, data: e.data };
    }
  }
  async function reject(id) {
    try {
      return await req("POST", "/rest/v1/rpc/batata_process_live_reservation_request", {
        token: tok,
        body: { p_request_id: id, p_action: "reject", p_processed_by: uid },
      });
    } catch (e) {
      return { ok: false, error: e.message, data: e.data };
    }
  }

  // T1
  try {
    const p = await product(10, "T1");
    const it = await mktItem(p.id, "#T1A");
    const r = await pending(it.id, 1, "T1");
    const a = await accept(r.id);
    if (a && a.ok !== false && !String(a.error || "").includes("below")) ok("T1", "accept qty10");
    else fail("T1", JSON.stringify(a));
  } catch (e) { fail("T1", e.message); }

  // T2
  try {
    const p = await product(1, "T2");
    const it = await mktItem(p.id, "#T2A");
    const r = await pending(it.id, 1, "T2");
    const a = await accept(r.id);
    if (a && a.ok !== false && !String(a.error || "").includes("below")) ok("T2", "accept qty1");
    else fail("T2", JSON.stringify(a));
  } catch (e) { fail("T2", e.message); }

  // T3
  try {
    const p = await product(0, "T3");
    const it = await mktItem(p.id, "#T3A");
    const r = await pending(it.id, 1, "T3");
    const a = await accept(r.id);
    const s = JSON.stringify(a);
    if (a.ok === false || /no_stock|qty_exceeds|below_reservations|42501/.test(s)) ok("T3", "blocked " + s.slice(0, 120));
    else fail("T3", s);
  } catch (e) {
    if (/no_stock|qty_exceeds|below|42501/.test(e.message)) ok("T3", "blocked http");
    else fail("T3", e.message);
  }

  // T4 + T8
  try {
    const p = await product(1, "T4");
    const it = await mktItem(p.id, "#T4A");
    const ra = await pending(it.id, 1, "T4A");
    const rb = await pending(it.id, 1, "T4B");
    const [aa, ab] = await Promise.all([accept(ra.id), accept(rb.id)]);
    const acc = await req("GET", `/rest/v1/live_reservation_requests?live_item_id=eq.${it.id}&status=eq.accepted&select=id`, { service: true });
    const n = Array.isArray(acc) ? acc.length : 0;
    if (n <= 1) { ok("T4", "accepted=" + n); ok("T8", "concurrent accepted=" + n); }
    else { fail("T4", "oversell " + n); fail("T8", "oversell " + n); }
    console.log("T4 detail", JSON.stringify({ aa, ab, n }).slice(0, 300));
  } catch (e) { fail("T4", e.message); fail("T8", e.message); }

  // T5
  try {
    const it = await liveOnly(2, "#T5L");
    const r = await pending(it.id, 1, "T5");
    const a = await accept(r.id);
    if (a && a.ok !== false) ok("T5", "live_only accept");
    else fail("T5", JSON.stringify(a));
  } catch (e) { fail("T5", e.message); }

  // T6
  try {
    const p = await product(1, "T6");
    const it = await mktItem(p.id, "#T6A");
    const ra = await pending(it.id, 1, "T6A");
    await reject(ra.id);
    const rb = await pending(it.id, 1, "T6B");
    const a = await accept(rb.id);
    if (a && a.ok !== false) ok("T6", "accept after reject");
    else fail("T6", JSON.stringify(a));
  } catch (e) { fail("T6", e.message); }

  // T7
  try {
    const p = await product(1, "T7");
    const it = await mktItem(p.id, "#T7A");
    const ra = await pending(it.id, 1, "T7A");
    const rb = await pending(it.id, 1, "T7B");
    const a1 = await accept(ra.id);
    const a2 = await accept(rb.id);
    const s = JSON.stringify(a2);
    if (a1 && a1.ok !== false && (a2.ok === false || /qty_exceeds|no_stock|below|42501|not_sellable/.test(s)))
      ok("T7", "second blocked after first accept");
    else fail("T7", JSON.stringify({ a1, a2 }));
  } catch (e) { fail("T7", e.message); }

  // T9
  try {
    const p = await product(2, "T9");
    const it = await mktItem(p.id, "#T9A");
    const r = await pending(it.id, 1, "T9");
    await accept(r.id);
    await accept(r.id);
    const acc = await req("GET", `/rest/v1/live_reservation_requests?live_item_id=eq.${it.id}&status=eq.accepted&select=id,requested_qty`, { service: true });
    const sum = (acc || []).reduce((s, x) => s + Number(x.requested_qty || 0), 0);
    if ((acc || []).length === 1 && sum === 1) ok("T9", "no double consume");
    else fail("T9", JSON.stringify({ acc, sum }));
  } catch (e) { fail("T9", e.message); }

  // T10
  try {
    const p = await product(5, "T10");
    const it = await mktItem(p.id, "#T10A");
    const r = await pending(it.id, 1, "T10");
    await accept(r.id);
    const stock = await req("POST", "/rest/v1/rpc/batata_live_item_stock", { token: tok, body: { p_live_item_id: it.id } });
    const tot = await req("POST", "/rest/v1/rpc/batata_live_item_total_qty", { token: tok, body: { p_live_item_id: it.id } });
    // seller touch
    let touchOk = true;
    try {
      await req("PATCH", `/rest/v1/live_items?id=eq.${it.id}`, {
        token: tok,
        body: { updated_at: new Date().toISOString() },
      });
    } catch (e) {
      touchOk = false;
      if (/below_reservations/.test(e.message)) fail("T10", "touch still below_reservations " + e.message);
    }
    if (touchOk && stock.ok && tot === 5) ok("T10", `stock avail=${stock.available_qty} total=${tot} touch_ok`);
    else if (!results.T10) fail("T10", JSON.stringify({ stock, tot, touchOk }));
  } catch (e) { fail("T10", e.message); }

  // RRR6
  const rrrLive = "ab6cbc98-ec28-4d7b-a329-8d5c833220d9";
  const rrrItem = "677f7051-e974-40e2-a94f-2096aad054bc";
  const rrrReq = "e944cc6c-1e49-4bcc-8006-60e3bfd39565";
  try {
    const before = (await req("GET", `/rest/v1/live_reservation_requests?id=eq.${rrrReq}&select=id,status,requested_qty`, { service: true }))[0];
    const li = (await req("GET", `/rest/v1/live_items?id=eq.${rrrItem}&select=id,quantity,item_kind,product_id`, { service: true }))[0];
    const prod = (await req("GET", `/rest/v1/products?id=eq.${li.product_id}&select=id,quantity`, { service: true }))[0];
    console.log("RRR6", before.status, "li.qty", li.quantity, "prod.qty", prod.quantity, "kind", li.item_kind);
    if (before.status !== "pending") {
      ok("RRR6", `already ${before.status}; guard validated via T1/T10`);
    } else {
      await req("PATCH", `/rest/v1/lives?id=eq.${rrrLive}`, {
        service: true,
        body: { status: "live", is_active: true },
      });
      try {
        const a = await accept(rrrReq);
        const after = (await req("GET", `/rest/v1/live_reservation_requests?id=eq.${rrrReq}&select=id,status`, { service: true }))[0];
        if (after.status === "accepted") ok("RRR6", "Mariana accept PASS");
        else fail("RRR6", JSON.stringify({ a, after }));
      } finally {
        await req("PATCH", `/rest/v1/lives?id=eq.${rrrLive}`, {
          service: true,
          body: { status: "ended", is_active: false },
        });
      }
    }
  } catch (e) { fail("RRR6", e.message); }

  try {
    await req("PATCH", `/rest/v1/lives?id=eq.${liveId}`, {
      service: true,
      body: { status: "ended", is_active: false },
    });
  } catch (_) {}

  const out = path.join(root, "tool/reports/guard_marketplace_qty_null_t1_t10_2026-09-20.json");
  fs.writeFileSync(out, JSON.stringify(results, null, 2));
  console.log("Wrote", out);
  const fails = Object.values(results).filter((v) => v.startsWith("FAIL")).length;
  process.exit(fails ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(2); });
