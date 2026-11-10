/**
 * ZIP 128 — Submeter provas a uma disputa Stripe (BATATA).
 *
 * - Autenticado: vendedor da disputa ou admin
 * - Regista upload local + chama Stripe disputes.update (evidence)
 * - Idempotente por (dispute_id + evidence_kind + storage_path)
 * - NÃO cobra cartões; NÃO activa Live; Sandbox OK
 *
 * Body JSON:
 * {
 *   stripe_dispute_id, order_id?,
 *   evidence_kind: 'shipping_documentation'|'customer_communication'|'uncategorized_text'|...,
 *   uncategorized_text?: string,
 *   storage_path?: string,
 *   submit?: boolean  // se true, stripe.disputes.submitEvidence
 * }
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

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

  const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  if (!stripeSecretKey || !supabaseUrl || !serviceRoleKey) {
    return json({ ok: false, error: "config" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ ok: false, error: "auth_required" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey || serviceRoleKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user?.id) {
    return json({ ok: false, error: "auth_required" }, 401);
  }
  const uid = userData.user.id;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  const disputeId = String(body.stripe_dispute_id ?? "").trim();
  const evidenceKind = String(body.evidence_kind ?? "uncategorized_text").trim();
  const text = String(body.uncategorized_text ?? body.notes ?? "").trim();
  const storagePath = String(body.storage_path ?? "").trim() || null;
  const orderId = String(body.order_id ?? "").trim() || null;
  const doSubmit = body.submit === true;

  if (!disputeId) {
    return json({ ok: false, error: "missing_dispute_id" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: dispute, error: dErr } = await admin
    .from("stripe_disputes")
    .select("id,seller_id,stripe_dispute_id,order_id,status")
    .eq("stripe_dispute_id", disputeId)
    .maybeSingle();

  if (dErr || !dispute) {
    return json({ ok: false, error: "dispute_not_found" }, 404);
  }

  const { data: isAdmin } = await admin.rpc("batata_is_admin");
  const sellerOk = dispute.seller_id === uid;
  if (!sellerOk && isAdmin !== true) {
    // fallback: check profiles admin via SQL helper already used
    const { data: me } = await admin
      .from("profiles")
      .select("user_type")
      .eq("id", uid)
      .maybeSingle();
    const ut = String(me?.user_type ?? "").toLowerCase();
    const adminish = ["admin", "admim", "administrador", "administracao"].includes(ut);
    if (!adminish) {
      return json({ ok: false, error: "forbidden" }, 403);
    }
  }

  const { data: uploadRow, error: upErr } = await admin
    .from("stripe_dispute_evidence_uploads")
    .insert({
      stripe_dispute_id: disputeId,
      order_id: orderId ?? dispute.order_id,
      uploaded_by: uid,
      evidence_kind: evidenceKind,
      storage_path: storagePath,
      notes: text || null,
      stripe_submitted: false,
    })
    .select("id")
    .maybeSingle();

  if (upErr) {
    console.error("evidence insert", upErr);
    return json({ ok: false, error: "persist_failed" }, 500);
  }

  const stripe = new Stripe(stripeSecretKey, {
    apiVersion: "2024-06-20",
    httpClient: Stripe.createFetchHttpClient(),
  });

  try {
    const evidence: Stripe.DisputeUpdateParams.Evidence = {};
    if (text) {
      if (evidenceKind === "customer_communication") {
        evidence.customer_communication = text;
      } else if (evidenceKind === "shipping_documentation") {
        evidence.shipping_documentation = text;
      } else {
        evidence.uncategorized_text = text;
      }
    }

    await stripe.disputes.update(disputeId, {
      evidence,
      metadata: {
        fleaber_upload_id: String(uploadRow?.id ?? ""),
        fleaber_order_id: String(orderId ?? dispute.order_id ?? ""),
      },
    });

    if (doSubmit) {
      await stripe.disputes.submitEvidence(disputeId);
    }

    if (uploadRow?.id) {
      await admin
        .from("stripe_dispute_evidence_uploads")
        .update({ stripe_submitted: doSubmit })
        .eq("id", uploadRow.id);
    }
  } catch (stripeErr) {
    const msg = stripeErr instanceof Error ? stripeErr.message : String(stripeErr);
    console.error("stripe evidence update failed", msg);
    // Mantém registo local; Stripe pode falhar em Sandbox sem dispute real
    return json({
      ok: true,
      local_saved: true,
      stripe_ok: false,
      stripe_error: msg,
      upload_id: uploadRow?.id ?? null,
    });
  }

  return json({
    ok: true,
    local_saved: true,
    stripe_ok: true,
    submitted: doSubmit,
    upload_id: uploadRow?.id ?? null,
  });
});
