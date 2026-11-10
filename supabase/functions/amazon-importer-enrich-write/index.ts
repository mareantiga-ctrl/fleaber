/**
 * ZIP 157 — escrita segura de enrich local (admin JWT).
 * Body JSON tipado; sem SQL concatenado com texto do manifesto.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

type PhotoIn = {
  url: string;
  source?: string;
  sort_order?: number;
  is_primary?: boolean;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !serviceKey || !anonKey) {
    return json({ ok: false, error: "missing_env" }, 200);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  const uid = userData.user?.id ?? null;
  if (!uid) return json({ ok: false, error: "auth_required" }, 200);

  const { data: isAdmin } = await userClient.rpc(
    "batata_is_amazon_importer_admin",
  );
  if (isAdmin !== true) {
    return json({ ok: false, error: "forbidden" }, 200);
  }

  const body = await req.json().catch(() => ({}));
  const asin = String(body.asin ?? "").trim().toUpperCase();
  if (!/^[A-Z0-9]{10}$/.test(asin)) {
    return json({ ok: false, error: "invalid_asin" }, 200);
  }

  const title = body.title != null ? String(body.title).slice(0, 200) : null;
  const description = body.description != null
    ? String(body.description).slice(0, 4000)
    : null;
  const titleOriginal = body.title_original != null
    ? String(body.title_original).slice(0, 500)
    : null;
  const llmModel = body.llm_model != null
    ? String(body.llm_model).slice(0, 80)
    : null;
  const copyStatus = body.copy_status != null
    ? String(body.copy_status).slice(0, 40)
    : null;
  const suggested = typeof body.suggested_sale_eur === "number"
    ? body.suggested_sale_eur
    : null;
  const photos = Array.isArray(body.photos) ? body.photos as PhotoIn[] : [];

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const primary = photos.find((p) => p.url)?.url ?? null;
  const patch: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
    catalog_status: copyStatus === "pass" ? "prepared" : "needs_review",
  };
  if (title != null) patch.title = title;
  if (description != null) patch.description = description;
  if (titleOriginal != null) patch.title_original = titleOriginal;
  if (llmModel != null) {
    patch.llm_model = llmModel;
    patch.llm_generated_at = new Date().toISOString();
  }
  if (suggested != null) patch.suggested_sale_eur = suggested;
  if (primary) {
    patch.primary_image_url = primary;
    patch.photo_rights_status = "internal_ref";
  }
  if (copyStatus) {
    patch.prep_notes = `ZIP157 copy_status=${copyStatus}`;
  }

  const { data: upserted, error: upErr } = await admin
    .from("amazon_catalog_products")
    .upsert(
      {
        asin,
        ...patch,
        discount_pct: 50,
      },
      { onConflict: "asin" },
    )
    .select("id")
    .maybeSingle();

  if (upErr || !upserted?.id) {
    return json({
      ok: false,
      error: "upsert_failed",
      detail: upErr?.message ?? "no_id",
    }, 200);
  }

  const productId = upserted.id as string;

  // Substituir só refs automáticas (nunca apaga uploads próprios).
  await admin
    .from("amazon_product_photos")
    .delete()
    .eq("product_id", productId)
    .in("source", [
      "amazon_cdn_pending_rights",
      "amazon_ref_pending_rights",
      "amazon_dp_html",
      "amazon_browser_pending_rights",
    ]);

  let sort = 0;
  for (const ph of photos.slice(0, 8)) {
    const url = String(ph.url ?? "").trim();
    if (!/^https:\/\//i.test(url)) continue;
    const source = [
        "upload",
        "camera",
        "amazon_ref_pending_rights",
        "amazon_cdn_pending_rights",
        "amazon_dp_html",
        "amazon_browser_pending_rights",
      ].includes(String(ph.source))
      ? String(ph.source)
      : "amazon_dp_html";
    await admin.from("amazon_product_photos").insert({
      product_id: productId,
      storage_path: url,
      public_url: url,
      sort_order: typeof ph.sort_order === "number" ? ph.sort_order : sort,
      is_primary: ph.is_primary === true || sort === 0,
      source,
    });
    sort++;
  }

  return json({
    ok: true,
    product_id: productId,
    asin,
    photo_count: sort,
    updated_by: uid,
  });
});
