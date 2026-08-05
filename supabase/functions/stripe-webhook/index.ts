/**
 * SEC-005 — Stripe webhook (BATATA).
 *
 * Aditivo: NÃO remove o settle via GET return URL em create-payment-intent /
 * create-live-tip-checkout. Só chama o mesmo settle quando Stripe confirma pago
 * (útil se o browser fechar antes do redirect).
 *
 * Secrets:
 *   STRIPE_SECRET_KEY
 *   STRIPE_WEBHOOK_SECRET  (whsec_… do endpoint no Dashboard Stripe)
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *
 * Dashboard Stripe (staging) → Webhooks → endpoint:
 *   https://<project>.supabase.co/functions/v1/stripe-webhook
 * Events: checkout.session.completed, checkout.session.async_payment_succeeded
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*" } });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!stripeSecretKey || !webhookSecret) {
    console.error("stripe-webhook missing STRIPE_SECRET_KEY or STRIPE_WEBHOOK_SECRET");
    return json({ ok: false, error: "config" }, 500);
  }
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("stripe-webhook missing Supabase config");
    return json({ ok: false, error: "config" }, 500);
  }

  const signature = req.headers.get("stripe-signature");
  if (!signature) {
    return json({ ok: false, error: "missing_signature" }, 400);
  }

  const rawBody = await req.text();
  const stripe = new Stripe(stripeSecretKey, {
    apiVersion: "2024-06-20",
    httpClient: Stripe.createFetchHttpClient(),
  });
  const cryptoProvider = Stripe.createSubtleCryptoProvider();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      rawBody,
      signature,
      webhookSecret,
      undefined,
      cryptoProvider,
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("stripe-webhook signature failed", msg);
    return json({ ok: false, error: "invalid_signature" }, 400);
  }

  const handledTypes = new Set([
    "checkout.session.completed",
    "checkout.session.async_payment_succeeded",
  ]);
  if (!handledTypes.has(event.type)) {
    return json({ ok: true, ignored: event.type });
  }

  const session = event.data.object as Stripe.Checkout.Session;
  const sessionId = (session.id ?? "").trim();
  if (!sessionId) {
    return json({ ok: true, skipped: "no_session_id" });
  }

  // Só settle com pagamento confirmado (igual ao GET return URL).
  if (session.payment_status !== "paid") {
    return json({
      ok: true,
      skipped: "not_paid",
      payment_status: session.payment_status,
    });
  }

  const isTip = (session.metadata?.purpose ?? "").trim() === "live_tip";
  const edgeName = isTip ? "create-live-tip-checkout" : "create-payment-intent";
  const settleUrl =
    `${supabaseUrl}/functions/v1/${edgeName}` +
    `?checkout_return=success&session_id=${encodeURIComponent(sessionId)}`;

  let settleStatus = 0;
  let settleOk = false;
  try {
    // Reutiliza exactamente a lógica GET existente (BATATA — sem duplicar settle).
    const settleRes = await fetch(settleUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${serviceRoleKey}`,
        apikey: serviceRoleKey,
      },
      redirect: "manual",
    });
    settleStatus = settleRes.status;
    // Sucesso UX: 200 texto/HTML ou 303 redirect para a app.
    // 429 = rate-limit do GET (já settleu antes) → não falhar o webhook.
    settleOk = settleStatus < 500;
  } catch (e) {
    console.error("stripe-webhook settle fetch failed", e);
    settleOk = false;
  }

  try {
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    await admin.from("stripe_checkout_events").insert({
      session_id: sessionId,
      order_id: session.metadata?.order_id ?? null,
      event: "webhook.checkout.session.settled",
      detail: JSON.stringify({
        stripe_event_id: event.id,
        stripe_event_type: event.type,
        settle_http_status: settleStatus,
        settle_ok: settleOk,
        purpose: isTip ? "live_tip" : "checkout",
        tip_id: session.metadata?.tip_id ?? null,
        bag: session.metadata?.bag_checkout === "true",
      }),
    });
  } catch (logErr) {
    console.warn("stripe-webhook event log failed", logErr);
  }

  if (!settleOk) {
    // Stripe re-tenta; GET return URL continua a ser rede de segurança.
    return json({ ok: false, settle_http_status: settleStatus }, 500);
  }

  return json({
    ok: true,
    session_id: sessionId,
    settle_http_status: settleStatus,
    purpose: isTip ? "live_tip" : "checkout",
  });
});
