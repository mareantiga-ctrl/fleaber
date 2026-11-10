/**
 * ZIP 130 — Tracking DPD (wservices.dpd.pt/trace/track).
 * Auth: comprador, vendedor da encomenda ou admin.
 * Chave: secret DPD_TRACKING_API_KEY (header apikey) — nunca no cliente.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { fetchDpdTrace } from "../_shared/dpd_client.ts";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ ok: false, error: "auth_required" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  const uid = userData?.user?.id;
  if (!uid) return json({ ok: false, error: "auth_required" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  const orderId = String(body.order_id ?? "").trim();
  if (!orderId) return json({ ok: false, error: "order_id_required" }, 400);

  const countrycode = String(body.countrycode ?? body.lang ?? "PT").trim();

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });
  const { data: order, error } = await admin
    .from("orders")
    .select(
      "id,buyer_id,seller_id,status,dpd_tracking_code,dpd_expedition_id,shipping_method",
    )
    .eq("id", orderId)
    .maybeSingle();

  if (error || !order) {
    return json({ ok: false, error: "order_not_found" }, 404);
  }

  const isParty = order.buyer_id === uid || order.seller_id === uid;
  if (!isParty) {
    // auth.uid() via JWT do utilizador — não service role
    const { data: isAdmin } = await userClient.rpc("batata_is_admin");
    if (isAdmin !== true) {
      return json({ ok: false, error: "forbidden" }, 403);
    }
  }

  // Guia: BD da encomenda; override só vendedor/admin (pré-visualizar / QA)
  let guide = String(order.dpd_tracking_code ?? "").trim();
  const override = String(body.guide ?? body.search ?? "").trim();
  if (override) {
    const { data: isAdmin } = await userClient.rpc("batata_is_admin");
    if (isAdmin === true || order.seller_id === uid) {
      guide = override;
    }
  }

  if (!guide) {
    return json({
      ok: false,
      status: "missing_guide",
      order_id: orderId,
      events: [],
      message:
        "Esta encomenda ainda não tem número de guia DPD. O seguimento aparece assim que a etiqueta for emitida.",
    });
  }

  const result = await fetchDpdTrace({ guide, countrycode });
  return json({
    ok: result.ok,
    status: result.status,
    order_id: orderId,
    guide: result.guide,
    countrycode: result.countrycode,
    events: result.events,
    message: result.message ?? null,
    http_status: result.http_status ?? null,
  });
});
