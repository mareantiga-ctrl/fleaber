/**
 * ZIP 170/173 — proxy Moloni (Maré Antiga).
 *
 * Modes:
 *   simulation — no Moloni HTTP (ZIP 169)
 *   readonly   — OAuth + GET + prepare/simulate create (ZIP 170/173); writes blocked
 *   live       — product insert only with explicit GO + MOLONI_MODE=live
 *
 * Secrets (Supabase Edge Secrets only — never in client/ZIP/logs):
 *   MOLONI_CLIENT_ID, MOLONI_CLIENT_SECRET, MOLONI_COMPANY_ID,
 *   MOLONI_REDIRECT_URI, MOLONI_MODE=simulation|readonly|live
 *   MOLONI_ACCESS_TOKEN, MOLONI_REFRESH_TOKEN (set by callback / refresh)
 *   MOLONI_ADMIN_TOKEN (optional exact-match admin bearer)
 *   MOLONI_DEFAULT_CATEGORY_ID, MOLONI_DEFAULT_UNIT_ID, MOLONI_DEFAULT_TAX_ID
 *
 * Callback:
 *   https://bpmpkzwnrbmuqnhgdscf.supabase.co/functions/v1/moloni-api/callback
 *
 * Reference sequence (ZIP 173.1, format approved): FLB###### starting FLB000001
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MOLONI_API = "https://api.moloni.pt/v1";
const MOLONI_OAUTH =
  "https://www.moloni.pt/ac/root/oauth/";

type Mode = "simulation" | "readonly" | "live";

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function mode(): Mode {
  const m = (Deno.env.get("MOLONI_MODE") || "simulation").toLowerCase();
  if (m === "live") return "live";
  if (m === "readonly" || m === "read_only" || m === "read") return "readonly";
  return "simulation";
}

function requireAdmin(req: Request) {
  const auth = req.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) throw new Error("unauthorized");
  return auth.slice(7);
}

function secretsPresent() {
  return {
    client_id: Boolean(Deno.env.get("MOLONI_CLIENT_ID")),
    client_secret: Boolean(Deno.env.get("MOLONI_CLIENT_SECRET")),
    company_id: Boolean(Deno.env.get("MOLONI_COMPANY_ID")),
    redirect_uri: Boolean(Deno.env.get("MOLONI_REDIRECT_URI")),
    access_token: Boolean(Deno.env.get("MOLONI_ACCESS_TOKEN")),
    refresh_token: Boolean(Deno.env.get("MOLONI_REFRESH_TOKEN")),
  };
}

function oauthAuthorizeUrl(): string | null {
  const clientId = Deno.env.get("MOLONI_CLIENT_ID");
  const redirect = Deno.env.get("MOLONI_REDIRECT_URI");
  if (!clientId || !redirect) return null;
  return (
    `${MOLONI_OAUTH}?response_type=code`
    + `&client_id=${encodeURIComponent(clientId)}`
    + `&redirect_uri=${encodeURIComponent(redirect)}`
  );
}

async function moloniGrant(params: Record<string, string>) {
  const q = new URLSearchParams(params).toString();
  const res = await fetch(`${MOLONI_API}/grant/?${q}`, { method: "GET" });
  const text = await res.text();
  let data: Record<string, unknown> = {};
  try {
    data = JSON.parse(text);
  } catch {
    data = { raw: text.slice(0, 200) };
  }
  return { ok: res.ok, status: res.status, data };
}

async function adminClient() {
  const sr = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const su = Deno.env.get("SUPABASE_URL");
  if (!sr || !su) return null;
  return createClient(su, sr);
}

async function loadStoredTokens(): Promise<{
  access_token?: string;
  refresh_token?: string;
  company_id?: string;
}> {
  const envAccess = Deno.env.get("MOLONI_ACCESS_TOKEN");
  const envRefresh = Deno.env.get("MOLONI_REFRESH_TOKEN");
  if (envAccess) {
    return {
      access_token: envAccess,
      refresh_token: envRefresh || undefined,
      company_id: Deno.env.get("MOLONI_COMPANY_ID") || undefined,
    };
  }
  const admin = await adminClient();
  if (!admin) return {};
  const { data } = await admin
    .from("moloni_oauth_tokens")
    .select("access_token, refresh_token, company_id")
    .eq("id", 1)
    .maybeSingle();
  return {
    access_token: data?.access_token ? String(data.access_token) : undefined,
    refresh_token: data?.refresh_token ? String(data.refresh_token) : undefined,
    company_id: data?.company_id ? String(data.company_id) : undefined,
  };
}

async function persistTokens(access: string, refresh?: string | null) {
  const admin = await adminClient();
  if (!admin) return;
  await admin.from("moloni_oauth_tokens").upsert({
    id: 1,
    company_id: Deno.env.get("MOLONI_COMPANY_ID"),
    access_token: access,
    refresh_token: refresh ?? null,
    expires_in: 3600,
    updated_at: new Date().toISOString(),
    zip: "170-C2",
  }, { onConflict: "id" });
}

async function ensureAccessToken(): Promise<string> {
  const stored = await loadStoredTokens();
  if (stored.company_id && !Deno.env.get("MOLONI_COMPANY_ID")) {
    Deno.env.set("MOLONI_COMPANY_ID", stored.company_id);
  }
  if (stored.access_token) return stored.access_token;

  const refresh = stored.refresh_token || Deno.env.get("MOLONI_REFRESH_TOKEN");
  const clientId = Deno.env.get("MOLONI_CLIENT_ID");
  const clientSecret = Deno.env.get("MOLONI_CLIENT_SECRET");
  if (!refresh || !clientId || !clientSecret) {
    throw new Error("oauth_token_missing");
  }
  const grant = await moloniGrant({
    grant_type: "refresh_token",
    client_id: clientId,
    client_secret: clientSecret,
    refresh_token: refresh,
  });
  const tok = String(grant.data?.access_token || "");
  if (!grant.ok || !tok) {
    throw new Error("oauth_refresh_failed");
  }
  await persistTokens(
    tok,
    grant.data?.refresh_token
      ? String(grant.data.refresh_token)
      : refresh,
  );
  return tok;
}

async function moloniGet(
  path: string,
  body: Record<string, unknown> = {},
): Promise<{ ok: boolean; status: number; data: unknown }> {
  const token = await ensureAccessToken();
  const companyId = Deno.env.get("MOLONI_COMPANY_ID");
  const payload = {
    company_id: companyId ? Number(companyId) : undefined,
    ...body,
  };
  const url =
    `${MOLONI_API}/${path}/?access_token=${encodeURIComponent(token)}&json=true`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  let data: unknown = null;
  try {
    data = JSON.parse(text);
  } catch {
    data = { raw: text.slice(0, 300) };
  }
  return { ok: res.ok, status: res.status, data };
}

/** ZIP 173.1 — codes FLB000001 … (format approved; writes still need GO). */
const REF_PREFIX = (Deno.env.get("MOLONI_REF_PREFIX") || "FLB").toUpperCase();
const REF_WIDTH = Number(Deno.env.get("MOLONI_REF_WIDTH") || 6);
const REF_START = Number(Deno.env.get("MOLONI_REF_START") || 1);

function formatMoloniRef(
  n: number,
  prefix = REF_PREFIX,
  width = REF_WIDTH,
): string {
  return `${prefix}${String(n).padStart(width, "0")}`;
}

function fieldMap(
  product: Record<string, unknown>,
  reference: string,
  defaults: { category_id?: number; unit_id?: number; tax_id?: number },
) {
  const price = Number(product.price ?? product.approved_sale_eur ?? 0);
  const taxId = defaults.tax_id
    ?? Number(Deno.env.get("MOLONI_DEFAULT_TAX_ID") || 3621477);
  return {
    company_id: Number(Deno.env.get("MOLONI_COMPANY_ID") || 354250),
    category_id: defaults.category_id
      ?? Number(Deno.env.get("MOLONI_DEFAULT_CATEGORY_ID") || 10587619), // Amzeu
    type: 1,
    name: String(product.title ?? "").slice(0, 250),
    reference,
    ean: product.ean ? String(product.ean) : "",
    price,
    unit_id: defaults.unit_id
      ?? Number(Deno.env.get("MOLONI_DEFAULT_UNIT_ID") || 3308782), // Unidade
    has_stock: 1,
    // Stock enters via purchase document later (ZIP futuro) — ficha nasce a 0.
    stock: 0,
    at_product_category: "M",
    taxes: taxId
      ? [{ tax_id: taxId, order: 0, cumulative: 0 }]
      : [],
    weight: product.shipping_weight_kg != null
      ? Number(product.shipping_weight_kg)
      : undefined,
    fleaber_product_id: product.id ? String(product.id) : undefined,
  };
}

function normalizeRef(v: unknown): string {
  return String(v ?? "")
    .trim()
    .toUpperCase()
    .replace(/^AMZ-/, "");
}

async function loadMoloniRefSet(): Promise<Set<string>> {
  const companyId = Number(Deno.env.get("MOLONI_COMPANY_ID") || 354250);
  const refs = new Set<string>();
  let offset = 0;
  for (let i = 0; i < 40; i++) {
    const r = await moloniGet("products/getAll", { qty: 50, offset });
    const list = Array.isArray(r.data) ? r.data as Record<string, unknown>[] : [];
    if (!list.length) break;
    for (const p of list) {
      const ref = String(p.reference ?? "").trim().toUpperCase();
      if (ref) refs.add(ref);
    }
    if (list.length < 50) break;
    offset += 50;
  }
  return refs;
}

async function seqConfig(): Promise<{
  prefix: string;
  width: number;
  next_n: number;
  approved: boolean;
}> {
  const supabase = await adminClient();
  if (supabase) {
    const { data } = await supabase
      .from("moloni_reference_seq")
      .select("next_n, prefix, width, approved_at")
      .eq("id", 1)
      .maybeSingle();
    if (data) {
      return {
        prefix: String(data.prefix || REF_PREFIX).toUpperCase(),
        width: Number(data.width || REF_WIDTH),
        next_n: Number(data.next_n || REF_START),
        approved: Boolean(data.approved_at),
      };
    }
  }
  return {
    prefix: REF_PREFIX,
    width: REF_WIDTH,
    next_n: REF_START,
    approved: true,
  };
}

/** Peek next free codes without advancing the counter (simulate/prepare). */
async function nextFreeRefs(
  count: number,
  existing: Set<string>,
): Promise<string[]> {
  const cfg = await seqConfig();
  const out: string[] = [];
  let n = cfg.next_n;
  while (out.length < count && n < cfg.next_n + 100000) {
    const code = formatMoloniRef(n, cfg.prefix, cfg.width);
    if (!existing.has(code.toUpperCase())) out.push(code);
    n += 1;
  }
  return out;
}

/**
 * Atomically reserve N sequence numbers (FOR UPDATE). Used on live create only.
 * Returns the formatted codes; advances next_n so concurrent callers never clash.
 */
async function allocateRefsAtomic(count: number): Promise<string[]> {
  const supabase = await adminClient();
  if (!supabase || count <= 0) return [];
  const { data, error } = await supabase.rpc("allocate_moloni_reference_batch", {
    p_count: count,
  });
  if (error || !data) {
    throw new Error(`seq_allocate_failed:${error?.message || "empty"}`);
  }
  const rows = Array.isArray(data) ? data : [data];
  return rows.map((r: { reference?: string } | string) =>
    typeof r === "string" ? r : String(r.reference || "")
  ).filter(Boolean);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const url = new URL(req.url);
  const path = url.pathname.replace(/\/+$/, "");
  const currentMode = mode();

  try {
    // OAuth callback — exchange code→token (readonly|live)
    if (path.endsWith("/callback") && req.method === "GET") {
      const code = url.searchParams.get("code");
      if (currentMode === "simulation") {
        return json({
          ok: true,
          simulation: true,
          message:
            "Callback em simulation — nenhum token persistido. "
            + "Defina MOLONI_MODE=readonly + secrets.",
          has_code: Boolean(code),
        });
      }
      const clientId = Deno.env.get("MOLONI_CLIENT_ID");
      const clientSecret = Deno.env.get("MOLONI_CLIENT_SECRET");
      const redirect = Deno.env.get("MOLONI_REDIRECT_URI");
      if (!clientId || !clientSecret || !redirect || !code) {
        return json({ ok: false, error: "oauth_config_incomplete" }, 400);
      }
      const grant = await moloniGrant({
        grant_type: "authorization_code",
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: redirect,
        code,
      });
      const access = Boolean(grant.data?.access_token);
      const refresh = Boolean(grant.data?.refresh_token);
      // Do NOT echo tokens. Operator must store via secure setup script
      // (Management API / CredMan) using the one-time code already consumed —
      // for ZIP 170 we return a HTML page instructing to run setup with
      // tokens captured server-side via service role upsert if table exists.
      const html = `<!doctype html><html lang="pt"><meta charset="utf-8"/>
<title>Moloni OAuth</title>
<body style="font-family:system-ui;padding:2rem">
<h1>Moloni OAuth ${grant.ok && access ? "OK" : "FALHOU"}</h1>
<p>token_received=${access} refresh_received=${refresh} expires_in=${
        grant.data?.expires_in ?? "n/a"
      }</p>
<p>Os tokens <b>não</b> são mostrados aqui. Guarde-os via script seguro
<code>tool/moloni_secure_setup.ps1 -FromCallback</code> se ainda não estiverem
nos Supabase Secrets (<code>MOLONI_ACCESS_TOKEN</code> /
<code>MOLONI_REFRESH_TOKEN</code>).</p>
<p>Pode fechar esta janela e voltar ao Cursor.</p>
</body></html>`;

      if (grant.ok && grant.data?.access_token) {
        try {
          await persistTokens(
            String(grant.data.access_token),
            grant.data.refresh_token
              ? String(grant.data.refresh_token)
              : null,
          );
        } catch {
          // ignore persist errors — HTML still reports token_received
        }
      }

      return new Response(html, {
        status: grant.ok && access ? 200 : 400,
        headers: { ...cors, "Content-Type": "text/html; charset=utf-8" },
      });
    }

    if (req.method !== "POST") {
      return json({ ok: false, error: "method_not_allowed" }, 405);
    }

    const jwt = requireAdmin(req);
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    const adminToken = Deno.env.get("MOLONI_ADMIN_TOKEN") || "";
    // Exact match only (verify_jwt=false for OAuth callback — never trust bare role claims).
    const isService = (Boolean(serviceKey) && jwt === serviceKey)
      || (Boolean(adminToken) && jwt === adminToken);
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      isService
        ? (serviceKey || Deno.env.get("SUPABASE_ANON_KEY")!)
        : Deno.env.get("SUPABASE_ANON_KEY")!,
      isService
        ? undefined
        : { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    let actorId = "service_role";
    if (!isService) {
      const { data: userData, error: userErr } = await supabase.auth.getUser(jwt);
      if (userErr || !userData.user) {
        return json({ ok: false, error: "unauthorized" }, 401);
      }
      actorId = userData.user.id;
    }

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "status");

    if (action === "status") {
      const sp = secretsPresent();
      return json({
        ok: true,
        mode: currentMode,
        zip: "170-C2",
        secrets: sp,
        redirect_uri: Deno.env.get("MOLONI_REDIRECT_URI") || null,
        oauth_authorize_url_ready: Boolean(oauthAuthorizeUrl()),
        writes_enabled: currentMode === "live",
        reads_enabled: currentMode === "readonly" || currentMode === "live",
        security_note:
          "Credenciais só em Supabase Secrets / CredMan. Nunca no git/ZIP/chat.",
      });
    }

    if (action === "oauth_start") {
      const u = oauthAuthorizeUrl();
      if (!u) {
        return json({ ok: false, error: "oauth_config_incomplete" }, 400);
      }
      return json({
        ok: true,
        mode: currentMode,
        authorize_url: u,
        message: "Abra o URL, autorize Maré Antiga, callback troca o code.",
      });
    }

    // ---- ZIP 169 simulation (kept) ----
    if (action === "simulate_upsert_product") {
      const fleaberProductId = String(body.product_id || "");
      if (!fleaberProductId) {
        return json({ ok: false, error: "product_id_required" }, 400);
      }
      const { data: product, error } = await supabase
        .from("products")
        .select(
          "id, title, price, quantity, shipping_weight_kg, ref_code, seller_id",
        )
        .eq("id", fleaberProductId)
        .maybeSingle();
      if (error || !product) {
        return json({ ok: false, error: "product_not_found" }, 404);
      }
      const asin = String(product.ref_code || "").replace(/^AMZ-/, "");
      const { data: catalog } = await supabase
        .from("amazon_catalog_products")
        .select("id")
        .eq("asin", asin)
        .maybeSingle();
      if (!catalog?.id) {
        return json({ ok: false, error: "amazon_catalog_missing" }, 404);
      }
      const payload = fieldMap({ ...product, asin });
      const externalId = `SIM-MOLONI-169-${asin || fleaberProductId.slice(0, 8)}`;
      await supabase.from("amazon_export_links").insert({
        product_id: catalog.id,
        target: "moloni",
        external_id: externalId,
        status: "skipped",
        last_error: "simulation — Moloni não chamada",
        meta: {
          simulated: true,
          zip: "170-C2",
          payload_preview: payload,
          fleaber_product_id: fleaberProductId,
          actor: actorId,
          idempotency_key: `sim_upsert:${catalog.id}`,
        },
      });
      return json({
        ok: true,
        simulation: true,
        external_id: externalId,
        stock_changed: false,
        document_emitted: false,
      });
    }

    if (action === "simulate_stock_decrement") {
      return json({
        ok: true,
        simulation: true,
        stock_changed: false,
        message: "Decremento simulado — stock Moloni intacto.",
      });
    }

    // ---- ZIP 170 read-only ----
    if (
      action === "read_companies"
      || action === "read_products"
      || action === "read_match_preview"
    ) {
      if (currentMode === "simulation") {
        return json({
          ok: false,
          error: "readonly_required",
          message: "MOLONI_MODE=simulation — leituras reais desactivadas.",
        }, 403);
      }
      if (!Deno.env.get("MOLONI_CLIENT_ID") || !Deno.env.get("MOLONI_CLIENT_SECRET")) {
        return json({ ok: false, error: "secrets_missing" }, 400);
      }

      if (action === "read_companies") {
        const r = await moloniGet("companies/getAll", {});
        const list = Array.isArray(r.data) ? r.data : [];
        const companies = list.map((c: Record<string, unknown>) => ({
          company_id: c.company_id ?? c.companyID ?? null,
          name: c.name ?? c.company_name ?? null,
          vat: c.vat ?? c.vat_number ?? null,
          email: c.email ?? null,
          city: c.city ?? null,
        }));
        return json({
          ok: r.ok,
          mode: currentMode,
          http_status: r.status,
          count: companies.length,
          companies,
          writes: false,
        });
      }

      if (action === "read_products") {
        const qty = Math.min(Number(body.qty || 50), 200);
        const offset = Number(body.offset || 0);
        const r = await moloniGet("products/getAll", { qty, offset });
        const list = Array.isArray(r.data) ? r.data : [];
        const products = list.map((p: Record<string, unknown>) => ({
          product_id: p.product_id ?? null,
          reference: p.reference ?? null,
          name: p.name ?? null,
          ean: p.ean ?? null,
          price: p.price ?? null,
          stock: p.stock ?? null,
          has_stock: p.has_stock ?? null,
          taxes: p.taxes ?? null,
        }));
        return json({
          ok: r.ok,
          mode: currentMode,
          http_status: r.status,
          count: products.length,
          products,
          writes: false,
        });
      }

      // read_match_preview — 3 Fleaber ↔ Moloni examples
      const sellerId = String(
        body.seller_id || "08c9dca8-3707-4ee5-9f43-b33293085d6a",
      );
      const { data: fleaberProducts } = await supabase
        .from("products")
        .select("id, title, price, quantity, ref_code")
        .eq("seller_id", sellerId)
        .like("ref_code", "AMZ-%")
        .order("created_at", { ascending: false })
        .limit(35);

      const r = await moloniGet("products/getAll", { qty: 200, offset: 0 });
      const moloniList = Array.isArray(r.data)
        ? r.data as Record<string, unknown>[]
        : [];
      const byRef = new Map<string, Record<string, unknown>>();
      const byEan = new Map<string, Record<string, unknown>>();
      for (const m of moloniList) {
        const ref = normalizeRef(m.reference);
        if (ref) byRef.set(ref, m);
        const ean = String(m.ean ?? "").trim();
        if (ean) byEan.set(ean, m);
      }

      // Optional EANs from amazon catalog (products table may not have ean)
      const asins = (fleaberProducts || [])
        .map((fp) => normalizeRef(fp.ref_code))
        .filter(Boolean);
      const { data: catalogRows } = await supabase
        .from("amazon_catalog_products")
        .select("asin, ean")
        .in("asin", asins.length ? asins : ["__none__"]);
      const eanByAsin = new Map<string, string>();
      for (const c of catalogRows || []) {
        if (c?.asin && c?.ean) eanByAsin.set(normalizeRef(c.asin), String(c.ean));
      }

      const matches: Record<string, unknown>[] = [];
      for (const fp of fleaberProducts || []) {
        const asin = normalizeRef(fp.ref_code);
        const ean = eanByAsin.get(asin) || "";
        const hit = (asin && byRef.get(asin))
          || (ean && byEan.get(ean))
          || null;
        if (hit) {
          matches.push({
            fleaber_product_id: fp.id,
            fleaber_ref: fp.ref_code,
            fleaber_title: fp.title,
            fleaber_price: fp.price,
            fleaber_qty: fp.quantity,
            moloni_product_id: hit.product_id ?? null,
            moloni_reference: hit.reference ?? null,
            moloni_name: hit.name ?? null,
            moloni_price: hit.price ?? null,
            moloni_stock: hit.stock ?? null,
            moloni_ean: hit.ean ?? null,
            match_key: asin && byRef.has(asin)
              ? "reference/asin"
              : "ean",
          });
        }
        if (matches.length >= 3) break;
      }

      return json({
        ok: r.ok,
        mode: currentMode,
        http_status: r.status,
        fleaber_candidates: (fleaberProducts || []).length,
        moloni_products_fetched: moloniList.length,
        matches_found: matches.length,
        matches,
        unmatched_strategy:
          "ZIP 173: prepare/simulate_product_create; live insert só com GO.",
        writes: false,
      });
    }

    // ---- ZIP 173 — create prep (no Moloni writes) ----
    if (
      action === "prepare_product_create"
      || action === "simulate_product_create"
    ) {
      if (currentMode === "simulation") {
        return json({
          ok: false,
          error: "readonly_or_live_required",
          message: "Precisa MOLONI_MODE=readonly|live para ler catálogo real.",
        }, 403);
      }

      const sellerId = String(
        body.seller_id || "08c9dca8-3707-4ee5-9f43-b33293085d6a",
      );
      const limit = Math.min(Number(body.limit || 8), 40);
      const includeExistingDemo = body.include_existing_demo !== false;
      const createSlots = includeExistingDemo
        ? Math.max(1, Math.min(limit - 2, limit))
        : limit;

      const { data: fleaberProducts } = await supabase
        .from("products")
        .select("id, title, price, quantity, ref_code")
        .eq("seller_id", sellerId)
        .like("ref_code", "AMZ-%")
        .order("created_at", { ascending: false })
        .limit(createSlots);

      const { data: existingLinks } = await supabase
        .from("moloni_product_links")
        .select(
          "fleaber_product_id, moloni_product_id, moloni_reference, match_key, asin, lpn",
        );

      const linkByFleaber = new Map<string, Record<string, unknown>>();
      for (const l of existingLinks || []) {
        linkByFleaber.set(String(l.fleaber_product_id), l as Record<string, unknown>);
      }

      const moloniRefs = await loadMoloniRefSet();
      const flbCollisions = [...moloniRefs].filter((r) => r.startsWith("FLB"));
      const byRef = new Map<string, Record<string, unknown>>();
      let offset = 0;
      const moloniList: Record<string, unknown>[] = [];
      for (let i = 0; i < 40; i++) {
        const r = await moloniGet("products/getAll", { qty: 50, offset });
        const chunk = Array.isArray(r.data)
          ? r.data as Record<string, unknown>[]
          : [];
        if (!chunk.length) break;
        moloniList.push(...chunk);
        for (const p of chunk) {
          const ref = normalizeRef(p.reference);
          if (ref) byRef.set(ref, p);
        }
        if (chunk.length < 50) break;
        offset += 50;
      }

      const cfg = await seqConfig();
      const needCodes = (fleaberProducts || []).filter((fp) => {
        const asin = normalizeRef(fp.ref_code);
        if (linkByFleaber.has(String(fp.id))) return false;
        if (asin && byRef.has(asin)) return false;
        return true;
      }).length;
      const freeCodes = await nextFreeRefs(needCodes, moloniRefs);
      let codeIdx = 0;

      const defaults = {
        category_id: Number(
          Deno.env.get("MOLONI_DEFAULT_CATEGORY_ID") || 10587619,
        ),
        unit_id: Number(Deno.env.get("MOLONI_DEFAULT_UNIT_ID") || 3308782),
        tax_id: Number(Deno.env.get("MOLONI_DEFAULT_TAX_ID") || 3621477),
      };

      const items: Record<string, unknown>[] = [];
      for (const fp of fleaberProducts || []) {
        const asin = normalizeRef(fp.ref_code);
        const linked = linkByFleaber.get(String(fp.id));
        if (linked) {
          items.push({
            action: "reuse_linked",
            fleaber_product_id: fp.id,
            fleaber_ref: fp.ref_code,
            asin: linked.asin ?? asin,
            lpn: linked.lpn ?? null,
            fleaber_price: fp.price,
            moloni_reference: linked.moloni_reference ?? null,
            moloni_product_id: linked.moloni_product_id ?? null,
            payload: null,
          });
          continue;
        }
        const hit = asin ? byRef.get(asin) : null;
        if (hit) {
          items.push({
            action: "reuse_existing_moloni",
            fleaber_product_id: fp.id,
            fleaber_ref: fp.ref_code,
            asin,
            fleaber_price: fp.price,
            moloni_reference: hit.reference ?? null,
            moloni_product_id: hit.product_id ?? null,
            match_key: "reference/asin",
            payload: null,
          });
          continue;
        }
        const code = freeCodes[codeIdx++]
          || formatMoloniRef(cfg.next_n + codeIdx, cfg.prefix, cfg.width);
        const payload = fieldMap({ ...fp, asin }, code, defaults);
        items.push({
          action: "create_new",
          fleaber_product_id: fp.id,
          fleaber_ref: fp.ref_code,
          asin,
          fleaber_price: fp.price,
          moloni_reference: code,
          moloni_product_id: null,
          match_key: "new_sequence",
          payload,
          collision: moloniRefs.has(code.toUpperCase()),
          code_len: code.length,
        });
      }

      // Incluir 2 artigos Moloni já existentes (prova de reuse, sem criar).
      if (includeExistingDemo) {
        const demos = moloniList
          .filter((p) => {
            const ref = String(p.reference || "").toUpperCase();
            return ref && !ref.startsWith("FLB") && !ref.startsWith("EXE");
          })
          .slice(0, 2);
        for (const p of demos) {
          items.push({
            action: "reuse_existing_moloni",
            fleaber_product_id: null,
            fleaber_ref: null,
            asin: null,
            fleaber_price: p.price ?? null,
            moloni_reference: p.reference ?? null,
            moloni_product_id: p.product_id ?? null,
            match_key: "existing_catalog_demo",
            payload: null,
            note: "Artigo já na Moloni — associação reutiliza ficha; não gera FLB novo.",
          });
        }
      }

      const createCodes = items
        .filter((i) => i.action === "create_new")
        .map((i) => String(i.moloni_reference || ""));
      const uniqueCreate = new Set(createCodes);

      return json({
        ok: true,
        mode: currentMode,
        zip: "173.1-C2",
        writes: false,
        sequence: {
          prefix: cfg.prefix,
          width: cfg.width,
          next_n: cfg.next_n,
          format: `${cfg.prefix}${"#".repeat(cfg.width)}`,
          total_chars: cfg.prefix.length + cfg.width,
          format_approved: cfg.approved,
          examples: [
            formatMoloniRef(1, cfg.prefix, cfg.width),
            formatMoloniRef(2, cfg.prefix, cfg.width),
            formatMoloniRef(3, cfg.prefix, cfg.width),
          ],
        },
        flb_prefix_collisions_in_catalog: flbCollisions.length,
        flb_collision_samples: flbCollisions.slice(0, 5),
        moloni_products_scanned: moloniRefs.size,
        defaults,
        defaults_validated: {
          category: "Amzeu / 10587619",
          unit: "Unidade / 3308782",
          tax: "IVA Normal 23% / 3621477",
        },
        summary: {
          total: items.length,
          create_new: items.filter((i) => i.action === "create_new").length,
          reuse_linked: items.filter((i) => i.action === "reuse_linked").length,
          reuse_existing_moloni: items.filter((i) =>
            i.action === "reuse_existing_moloni"
          ).length,
          collisions: items.filter((i) => i.collision === true).length,
          create_codes_unique: uniqueCreate.size === createCodes.length,
        },
        items,
        note:
          "SIMULAÇÃO — nenhum products/insert. Formato FLB###### aprovado; "
          + "aguarda GO para escrita real na Moloni.",
      });
    }

    // ---- ZIP 176 — auto-create on Fleaber publish (simulate by default) ----
    if (
      action === "process_moloni_sync_jobs"
      || action === "simulate_auto_create"
    ) {
      const autoMode = (
        Deno.env.get("MOLONI_AUTO_CREATE_MODE") || "simulate"
      ).toLowerCase();
      const forceSimulate = action === "simulate_auto_create"
        || body.simulate === true
        || autoMode !== "live";
      const limit = Math.min(Number(body.limit || 20), 50);

      const { data: jobs, error: jobsErr } = await supabase
        .from("moloni_sync_jobs")
        .select("*")
        .eq("status", "pending")
        .order("created_at", { ascending: true })
        .limit(limit);
      if (jobsErr) {
        return json({ ok: false, error: jobsErr.message }, 500);
      }

      const cfg = await seqConfig();
      const results: Record<string, unknown>[] = [];
      let peekOffset = 0;

      for (const job of jobs || []) {
        const fleaberId = String(job.fleaber_product_id);
        await supabase.from("moloni_sync_jobs").update({
          status: "processing",
          attempt_count: Number(job.attempt_count || 0) + 1,
          updated_at: new Date().toISOString(),
        }).eq("id", job.id);

        const { data: link } = await supabase
          .from("moloni_product_links")
          .select("moloni_product_id, moloni_reference, link_status")
          .eq("fleaber_product_id", fleaberId)
          .eq("link_status", "linked")
          .maybeSingle();

        if (link?.moloni_product_id) {
          await supabase.from("moloni_sync_jobs").update({
            status: "linked",
            result_action: "already_linked",
            moloni_product_id: link.moloni_product_id,
            moloni_reference: link.moloni_reference,
            processed_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          }).eq("id", job.id);
          results.push({
            job_id: job.id,
            action: "already_linked",
            moloni_reference: link.moloni_reference,
          });
          continue;
        }

        const { data: product } = await supabase
          .from("products")
          .select("id, title, price, ref_code, quantity")
          .eq("id", fleaberId)
          .maybeSingle();
        if (!product) {
          await supabase.from("moloni_sync_jobs").update({
            status: "failed",
            last_error: "fleaber_product_missing",
            updated_at: new Date().toISOString(),
          }).eq("id", job.id);
          results.push({ job_id: job.id, action: "failed", error: "fleaber_product_missing" });
          continue;
        }

        const asin = normalizeRef(product.ref_code);
        // Unequivocal reuse: ASIN == Moloni reference only (no fuzzy)
        let reused: Record<string, unknown> | null = null;
        if (asin) {
          const moloniRefs = await loadMoloniRefSet();
          if (moloniRefs.has(asin)) {
            // Need product_id — fetch page (expensive but rare for ASIN refs)
            let offset = 0;
            for (let i = 0; i < 40 && !reused; i++) {
              const r = await moloniGet("products/getAll", { qty: 50, offset });
              const chunk = Array.isArray(r.data)
                ? r.data as Record<string, unknown>[]
                : [];
              reused = chunk.find((p) =>
                normalizeRef(p.reference) === asin
              ) || null;
              if (!chunk.length || chunk.length < 50) break;
              offset += 50;
            }
          }
        }

        if (reused) {
          const mref = String(reused.reference || "");
          const mid = String(reused.product_id || "");
          if (!forceSimulate) {
            await supabase.from("moloni_product_links").upsert({
              fleaber_product_id: fleaberId,
              moloni_product_id: mid,
              moloni_reference: mref,
              asin,
              lpn: job.lpn ?? null,
              fleaber_ref_code: product.ref_code,
              seller_id: Deno.env.get("MOLONI_DEFAULT_SELLER_ID")
                || "08c9dca8-3707-4ee5-9f43-b33293085d6a",
              match_key: "reference/asin",
              link_status: "linked",
              fiscal_regime: "pending_accountant",
              zip: "176-C2",
              updated_at: new Date().toISOString(),
            }, { onConflict: "fleaber_product_id" });
          }
          await supabase.from("moloni_sync_jobs").update({
            status: forceSimulate ? "simulated" : "linked",
            result_action: "reuse_existing_moloni",
            planned_moloni_reference: mref,
            moloni_reference: mref,
            moloni_product_id: mid,
            processed_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
            meta: { simulated: forceSimulate, zip: "176-C2" },
          }).eq("id", job.id);
          results.push({
            job_id: job.id,
            action: "reuse_existing_moloni",
            simulated: forceSimulate,
            moloni_reference: mref,
          });
          continue;
        }

        const planned = formatMoloniRef(
          cfg.next_n + peekOffset,
          cfg.prefix,
          cfg.width,
        );
        peekOffset += 1;

        if (forceSimulate) {
          await supabase.from("moloni_sync_jobs").update({
            status: "simulated",
            result_action: "create_new_simulated",
            planned_moloni_reference: planned,
            processed_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
            meta: {
              simulated: true,
              zip: "176-C2",
              would_start_at: planned,
              stock: 0,
              category_id: Number(
                Deno.env.get("MOLONI_DEFAULT_CATEGORY_ID") || 10587619,
              ),
              unit_id: Number(
                Deno.env.get("MOLONI_DEFAULT_UNIT_ID") || 3308782,
              ),
              fiscal_regime: "pending_accountant",
              note: "IVA da ficha não força regime de venda; margem 2ª mão TBD contabilista",
            },
          }).eq("id", job.id);
          results.push({
            job_id: job.id,
            fleaber_product_id: fleaberId,
            fleaber_ref: product.ref_code,
            asin,
            action: "create_new_simulated",
            planned_moloni_reference: planned,
            code_len: planned.length,
            stock: 0,
            writes: false,
          });
          continue;
        }

        // LIVE (ZIP 176 GO): allocate FLB + products/insert stock=0 + link
        try {
          const codes = await allocateRefsAtomic(1);
          const code = codes[0] || planned;
          const defaults = {
            category_id: Number(
              Deno.env.get("MOLONI_DEFAULT_CATEGORY_ID") || 10587619,
            ),
            unit_id: Number(
              Deno.env.get("MOLONI_DEFAULT_UNIT_ID") || 3308782,
            ),
            tax_id: Number(
              Deno.env.get("MOLONI_DEFAULT_TAX_ID") || 3621477,
            ),
          };
          const payload = fieldMap(
            { ...product, asin, ean: job.meta?.ean },
            code,
            defaults,
          );
          // Remove client-only helper fields before Moloni HTTP
          const { fleaber_product_id: _fp, ...insertBody } = payload as Record<
            string,
            unknown
          >;
          const token = await ensureAccessToken();
          const companyId = Number(
            Deno.env.get("MOLONI_COMPANY_ID") || 354250,
          );
          const url =
            `${MOLONI_API}/products/insert/?access_token=${
              encodeURIComponent(token)
            }&json=true`;
          const res = await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ ...insertBody, company_id: companyId }),
          });
          const text = await res.text();
          let resp: Record<string, unknown> = {};
          try {
            resp = JSON.parse(text);
          } catch {
            resp = { raw: text.slice(0, 300) };
          }
          const productId = resp.product_id;
          const valid = resp.valid === 1 || resp.valid === "1" || Boolean(productId);
          if (!res.ok || !valid || !productId) {
            throw new Error(
              `moloni_insert_failed:${res.status}:${JSON.stringify(resp).slice(0, 200)}`,
            );
          }
          const sellerId = Deno.env.get("MOLONI_DEFAULT_SELLER_ID")
            || "08c9dca8-3707-4ee5-9f43-b33293085d6a";
          await supabase.from("moloni_product_links").upsert({
            fleaber_product_id: fleaberId,
            moloni_product_id: String(productId),
            moloni_reference: code,
            asin,
            lpn: job.lpn ?? null,
            fleaber_ref_code: product.ref_code,
            seller_id: sellerId,
            match_key: "new_sequence",
            link_status: "linked",
            fiscal_regime: "pending_accountant",
            zip: "176.1-C2",
            updated_at: new Date().toISOString(),
          }, { onConflict: "fleaber_product_id" });
          await supabase.from("moloni_sync_jobs").update({
            status: "linked",
            result_action: "created",
            planned_moloni_reference: code,
            moloni_reference: code,
            moloni_product_id: String(productId),
            processed_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
            meta: { simulated: false, zip: "176.1-C2", stock: 0 },
          }).eq("id", job.id);
          results.push({
            job_id: job.id,
            fleaber_product_id: fleaberId,
            fleaber_ref: product.ref_code,
            asin,
            action: "created",
            moloni_reference: code,
            moloni_product_id: String(productId),
            stock: 0,
            writes: true,
          });
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          await supabase.from("moloni_sync_jobs").update({
            status: "failed",
            last_error: msg.slice(0, 500),
            planned_moloni_reference: planned,
            updated_at: new Date().toISOString(),
          }).eq("id", job.id);
          results.push({
            job_id: job.id,
            action: "failed",
            error: msg.slice(0, 300),
            planned_moloni_reference: planned,
            fleaber_preserved: true,
          });
        }
      }

      const { count: pendingCount } = await supabase
        .from("moloni_sync_jobs")
        .select("id", { count: "exact", head: true })
        .eq("status", "pending");

      return json({
        ok: true,
        zip: "176.1-C2",
        mode: currentMode,
        auto_create_mode: forceSimulate ? "simulate" : "live",
        writes: !forceSimulate,
        sequence: {
          prefix: cfg.prefix,
          width: cfg.width,
          next_n: (await seqConfig()).next_n,
          next_reference: formatMoloniRef(
            (await seqConfig()).next_n,
            cfg.prefix,
            cfg.width,
          ),
          format_approved: cfg.approved,
        },
        processed: results.length,
        results,
        pending_jobs: pendingCount ?? 0,
        note: forceSimulate
          ? "Simulação — sem products/insert."
          : "LIVE auto-create activo (ZIP 176 GO) — stock 0; sem compras/faturas.",
      });
    }

    if (action === "enqueue_fleaber_product") {
      const pid = String(body.fleaber_product_id || "");
      if (!pid) {
        return json({ ok: false, error: "fleaber_product_id_required" }, 400);
      }
      const { data, error } = await supabase.rpc(
        "batata_moloni_enqueue_fleaber_product",
        { p_product_id: pid },
      );
      if (error) return json({ ok: false, error: error.message }, 500);
      return json({ ok: true, enqueue: data, writes: false, zip: "176-C2" });
    }

    if (
      action === "live_upsert_product"
      || action === "live_stock_decrement"
      || action === "live_create_document"
    ) {
      if (currentMode !== "live") {
        return json({
          ok: false,
          error: "live_disabled",
          message:
            `MOLONI_MODE=${currentMode} — escritas recusadas (ZIP 173: precisa GO + live).`,
        }, 403);
      }
      if (action !== "live_upsert_product") {
        return json({
          ok: false,
          error: "stock_docs_future_phase",
          message:
            "Stock/faturação (compra/venda/NC) documentados para ZIPs futuros — não neste ZIP.",
        }, 501);
      }
      // Live product create is coded but still requires explicit GO secret.
      const go = String(body.go_token || "");
      const expectedGo = Deno.env.get("MOLONI_CREATE_GO_TOKEN") || "";
      if (!expectedGo || go !== expectedGo) {
        return json({
          ok: false,
          error: "go_required",
          message:
            "Criação real bloqueada: defina MOLONI_CREATE_GO_TOKEN e envie go_token.",
        }, 403);
      }
      return json({
        ok: false,
        error: "live_create_awaiting_write_go",
        message:
          "Formato FLB###### aprovado (ZIP 173.1). "
          + "Escrita real ainda bloqueada — falta GO explícito + go_token.",
      }, 501);
    }

    return json({ ok: false, error: "unknown_action", action }, 400);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const status = msg === "unauthorized"
      ? 401
      : msg.startsWith("oauth_")
      ? 401
      : 500;
    return json({ ok: false, error: msg }, status);
  }
});
