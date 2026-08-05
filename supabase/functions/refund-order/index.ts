import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type RefundBody = {
  order_id?: string;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function euroToCents(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.round(n * 100);
}

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
    }

    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!stripeSecretKey || !supabaseUrl || !serviceRoleKey) {
      throw new Error("Stripe refund is not configured.");
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ ok: false, error: "Missing authorization." }, 401);
    }

    const body = (await req.json()) as RefundBody;
    const orderId = body.order_id?.trim() ?? "";
    if (!orderId) {
      return jsonResponse({ ok: false, error: "order_id required" }, 400);
    }

    const supabaseAuthed = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await supabaseAuthed.auth.getUser();
    if (userError || !user) {
      return jsonResponse({ ok: false, error: "Invalid user." }, 401);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Rate-limit fail-open (RPC em falta → continua). Anular venda normal = 1–2 hits.
    const refundRate = await checkAnonRate(
      supabase,
      `refund_order:${user.id}`,
      "refund-order",
      30,
    );
    if (refundRate.rateLimited) {
      return jsonResponse({
        ok: false,
        error: "Demasiados pedidos de reembolso. Tenta mais tarde.",
      }, 429);
    }

    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select(
        "id, status, payment_method, price_total, seller_id, buyer_id, stripe_checkout_session_id, stripe_payment_intent_id, stripe_refund_id",
      )
      .eq("id", orderId)
      .maybeSingle();

    if (orderError || !order) {
      return jsonResponse({ ok: false, error: "Encomenda não encontrada." }, 404);
    }

    const sellerId = (order.seller_id as string | null)?.trim() ?? "";
    // SEC-011 (BATATA): só o vendedor anula+reembolsa Seguro Fleaber na app.
    // Buyer nunca chama esta edge no produto; manter seller-only evita abuso.
    if (!sellerId || user.id !== sellerId) {
      return jsonResponse({ ok: false, error: "Sem permissão." }, 403);
    }

    const paymentMethod = String(order.payment_method ?? "").toLowerCase();
    const isSeguro =
      paymentMethod.includes("pagamento na app") ||
      paymentMethod.includes("seguro fleaber") ||
      paymentMethod.includes("stripe");
    const isDirect =
      paymentMethod.includes("direto") ||
      paymentMethod.includes("mb way") ||
      paymentMethod.includes("mbway") ||
      paymentMethod.includes("transfer");
    if (!isSeguro || isDirect) {
      return jsonResponse({
        ok: true,
        skipped: true,
        reason: "not_seguro_fleaber",
      });
    }

    const existingRefund = (order.stripe_refund_id as string | null)?.trim() ??
      "";
    if (existingRefund.length > 0) {
      return jsonResponse({
        ok: true,
        already_refunded: true,
        refund_id: existingRefund,
      });
    }

    let paymentIntentId =
      (order.stripe_payment_intent_id as string | null)?.trim() ?? "";
    let sessionId =
      (order.stripe_checkout_session_id as string | null)?.trim() ?? "";

    if (!paymentIntentId && !sessionId) {
      const { data: evt } = await supabase
        .from("stripe_checkout_events")
        .select("session_id")
        .eq("order_id", orderId)
        .not("session_id", "is", null)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      sessionId = (evt?.session_id as string | null)?.trim() ?? "";
    }

    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2024-06-20",
      httpClient: Stripe.createFetchHttpClient(),
    });

    if (!paymentIntentId && sessionId) {
      const session = await stripe.checkout.sessions.retrieve(sessionId);
      const pi = session.payment_intent;
      paymentIntentId = typeof pi === "string"
        ? pi
        : (pi as { id?: string } | null)?.id?.trim() ?? "";
    }

    if (!paymentIntentId) {
      return jsonResponse({
        ok: false,
        error:
          "Sem PaymentIntent Stripe nesta encomenda. Contacte suporte com o ID da encomenda.",
      }, 422);
    }

    const amountCents = euroToCents(order.price_total);
    if (amountCents <= 0) {
      return jsonResponse({
        ok: false,
        error: "Valor da encomenda inválido para reembolso.",
      }, 422);
    }

    const refund = await stripe.refunds.create(
      {
        payment_intent: paymentIntentId,
        amount: amountCents,
        reason: "requested_by_customer",
        metadata: {
          fleaber_order_id: orderId,
          fleaber_actor_id: user.id,
        },
      },
      { idempotencyKey: `fleaber_order_refund_${orderId}` },
    );

    const { error: patchError } = await supabase
      .from("orders")
      .update({
        stripe_payment_intent_id: paymentIntentId,
        stripe_checkout_session_id: sessionId || null,
        stripe_refund_id: refund.id,
        stripe_refunded_at: new Date().toISOString(),
      })
      .eq("id", orderId);

    if (patchError) {
      console.error("orders refund patch failed", patchError);
    }

    try {
      await supabase.from("stripe_checkout_events").insert({
        session_id: sessionId || null,
        order_id: orderId,
        event: "refund_created",
        detail: JSON.stringify({
          refund_id: refund.id,
          payment_intent: paymentIntentId,
          amount_cents: amountCents,
          status: refund.status,
        }),
      });
    } catch (_) {
      /* audit best-effort */
    }

    return jsonResponse({
      ok: true,
      refund_id: refund.id,
      status: refund.status,
      amount_cents: amountCents,
      payment_intent: paymentIntentId,
    });
  } catch (e) {
    console.error("refund-order failed", e);
    const message = e instanceof Error ? e.message : String(e);
    return jsonResponse({ ok: false, error: message }, 500);
  }
});
