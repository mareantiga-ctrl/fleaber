import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import {
  normalizeStripeMode,
  resolveStripeSecretForMode,
} from "../_shared/ops_env.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type RefundBody = {
  order_id?: string;
  reason?: string;
  source?: string;
  /** Staging/TEST only — ignored unless sk_test_ + secret match */
  crash_inject?: string;
};

const SYSTEM_REFUND_REASONS = new Set([
  "shipping_deadline_or_delta_expired",
]);

function parseJwtRole(authHeader: string): string | null {
  try {
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    const part = token.split(".")[1] ?? "";
    if (!part) return null;
    const normalized = part.replace(/-/g, "+").replace(/_/g, "/");
    const pad = normalized.length % 4 === 0
      ? ""
      : "=".repeat(4 - (normalized.length % 4));
    const claims = JSON.parse(atob(normalized + pad)) as { role?: string };
    return String(claims.role ?? "") || null;
  } catch {
    return null;
  }
}

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

function timingSafeEqualStr(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const aa = enc.encode(a);
  const bb = enc.encode(b);
  if (aa.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < aa.length; i++) diff |= aa[i]! ^ bb[i]!;
  return diff === 0;
}

/** Crash inject só em Stripe TEST + secret partilhado (nunca bypass prod). */
function allowCrashInject(
  stripeSecretKey: string,
  req: Request,
  body: RefundBody,
): string | null {
  if (!stripeSecretKey.startsWith("sk_test_")) return null;
  const secret = Deno.env.get("FLEABER_STAGING_CRASH_INJECT_SECRET") ?? "";
  if (!secret || secret.length < 16) return null;
  const hdr = (req.headers.get("x-fleaber-crash-inject-secret") ?? "").trim();
  if (!timingSafeEqualStr(hdr, secret)) return null;
  const point = (body.crash_inject ??
    req.headers.get("x-fleaber-crash-inject") ?? "").trim();
  if (
    point === "after_stripe_before_db" ||
    point === "after_db_before_response"
  ) {
    return point;
  }
  return null;
}

async function findExistingOrderRefund(
  stripe: Stripe,
  paymentIntentId: string,
  orderId: string,
): Promise<Stripe.Refund | null> {
  const listed = await stripe.refunds.list({
    payment_intent: paymentIntentId,
    limit: 20,
  });
  // P1-A / INDEP-20260827: NUNCA reutilizar o único refund do PI sem metadata.
  // Saco partilha PI — refund da linha A não serve para B.
  for (const r of listed.data) {
    const metaOrder = String(r.metadata?.fleaber_order_id ?? "").trim();
    if (metaOrder === orderId) return r;
  }
  return null;
}

/** Cêntimos já reembolsados neste PI (succeeded + pending). */
function refundedCentsOnPi(refunds: Stripe.Refund[]): number {
  let n = 0;
  for (const r of refunds) {
    const st = String(r.status ?? "").toLowerCase();
    if (st === "failed" || st === "canceled") continue;
    n += Number(r.amount ?? 0);
  }
  return n;
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

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
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

    // Crash inject só com chave TEST resolvida (nunca LIVE).
    const testPeek = resolveStripeSecretForMode("test");
    const crashPoint = allowCrashInject(testPeek.key || "", req, body);
    const reason = String(body.reason ?? "").trim();
    const isService = parseJwtRole(authHeader) === "service_role" ||
      authHeader.replace(/^Bearer\s+/i, "").trim() === serviceRoleKey;

    // ZIP 144.2: tick de expiração 48h chama com service_role (não é seller JWT).
    // Mantém seller-only para reembolsos manuais; service só em reasons de sistema.
    let actorId: string | null = null;
    if (isService) {
      if (!SYSTEM_REFUND_REASONS.has(reason)) {
        return jsonResponse({
          ok: false,
          error: "Sem permissão (service_role só em cancelamento por prazo/delta).",
        }, 403);
      }
      actorId = "service_role";
    } else {
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
      actorId = user.id;
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const refundRate = await checkAnonRate(
      supabase,
      `refund_order:${actorId}`,
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
        "id, status, payment_method, price_total, amount_paid_cents, seller_id, buyer_id, stripe_checkout_session_id, stripe_payment_intent_id, stripe_refund_id, stock_units_applied, product_id, quantity, wallet_refund_processed_at, ops_stripe_mode",
      )
      .eq("id", orderId)
      .maybeSingle();

    if (orderError || !order) {
      return jsonResponse({ ok: false, error: "Encomenda não encontrada." }, 404);
    }

    const sellerId = (order.seller_id as string | null)?.trim() ?? "";
    if (!isService) {
      if (!sellerId || actorId !== sellerId) {
        return jsonResponse({ ok: false, error: "Sem permissão." }, 403);
      }
    }

    // ZIP 172: reembolso com a chave do sticky ops_stripe_mode (sem LIVE→global).
    const orderStripeMode = normalizeStripeMode(
      (order as { ops_stripe_mode?: string }).ops_stripe_mode,
    );
    const stripeResolved = resolveStripeSecretForMode(orderStripeMode);
    if (!stripeResolved.ok || !stripeResolved.key) {
      return jsonResponse({
        ok: false,
        error: stripeResolved.error ?? "stripe_mode_blocked",
        message: orderStripeMode === "live"
          ? "Reembolso LIVE bloqueado até GO + STRIPE_SECRET_KEY_LIVE."
          : "Reembolso TEST indisponível (credencial TEST em falta).",
        ops_stripe_mode: orderStripeMode,
      }, 403);
    }
    const stripeSecretKey = stripeResolved.key;

    // D0733-P1: após enviado/concluido ou com disputa aberta — sem anular Stripe.
    // Idempotência (já tem stripe_refund_id) continua abaixo.
    const existingRefundEarly =
      (order.stripe_refund_id as string | null)?.trim() ?? "";
    if (existingRefundEarly.length === 0) {
      const { data: allowGate, error: allowErr } = await supabase.rpc(
        "batata_order_allows_seller_stripe_refund",
        { p_order_id: orderId },
      );
      if (allowErr) {
        console.error("refund_status_gate", allowErr);
        return jsonResponse({
          ok: false,
          error: "Não foi possível validar o estado da encomenda.",
        }, 500);
      }
      const gate = (allowGate ?? {}) as {
        ok?: boolean;
        error?: string;
        status?: string;
      };
      if (gate.ok !== true) {
        const code = String(gate.error ?? "order_refund_blocked");
        return jsonResponse({
          ok: false,
          error: code === "order_refund_blocked_open_dispute"
            ? "Há uma disputa aberta. O reembolso só pode ser feito pela equipa Fleaber."
            : "Não é possível anular esta venda neste estado (já enviada ou concluída).",
          code,
          status: gate.status ?? order.status,
        }, 403);
      }
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

    // RTC-C-P0-001: wallet disputa já restituiu → Stripe só pode o residual.
    const { data: walletRefundCentsRaw, error: walletRefundErr } = await supabase
      .rpc("batata_order_wallet_reembolso_cents", { p_order_id: orderId });
    if (walletRefundErr) {
      console.error("wallet_reembolso_cents", walletRefundErr);
      return jsonResponse({
        ok: false,
        error: "Não foi possível validar reembolso em carteira.",
      }, 500);
    }
    const walletRefundCents = Math.max(
      0,
      Number(walletRefundCentsRaw ?? 0) || 0,
    );
    const walletFlag = Boolean(order.wallet_refund_processed_at);

    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2024-06-20",
      httpClient: Stripe.createFetchHttpClient(),
    });

    async function finalize(
      refundId: string,
      paymentIntentId: string,
      sessionId: string,
      amountCents: number,
      already: boolean,
    ) {
      const { data: fin, error: finErr } = await supabase.rpc(
        "batata_finalize_stripe_order_refund",
        {
          p_order_id: orderId,
          p_refund_id: refundId,
          p_payment_intent_id: paymentIntentId || null,
          p_session_id: sessionId || null,
          p_amount_cents: amountCents > 0 ? amountCents : null,
        },
      );
      if (finErr) {
        return {
          ok: false as const,
          error: finErr.message,
          refund_id: refundId,
          needs_reconcile: true as const,
        };
      }
      const row = (fin ?? {}) as Record<string, unknown>;
      if (row.ok !== true) {
        return {
          ok: false as const,
          error: String(row.error ?? "finalize_failed"),
          refund_id: refundId,
          needs_reconcile: true as const,
        };
      }
      // ZIP 128: se havia livre resolução B2C aberta, marcar refunded (best-effort)
      try {
        await supabase.rpc("batata_mark_consumer_withdrawal_refunded", {
          p_order_id: orderId,
        });
      } catch (_) { /* soft */ }
      return {
        ok: true as const,
        already_refunded: already || row.already_refunded === true,
        idempotent: row.idempotent === true,
        refund_id: refundId,
        status: String(row.status ?? "cancelado"),
        stock_units_applied: row.stock_units_applied ?? null,
        amount_cents: amountCents,
        payment_intent: paymentIntentId,
      };
    }

    const existingRefund = (order.stripe_refund_id as string | null)?.trim() ??
      "";
    if (existingRefund.length > 0) {
      const fin = await finalize(
        existingRefund,
        (order.stripe_payment_intent_id as string | null)?.trim() ?? "",
        (order.stripe_checkout_session_id as string | null)?.trim() ?? "",
        euroToCents(order.price_total),
        true,
      );
      if (!fin.ok) {
        return jsonResponse({
          ok: false,
          error: fin.error,
          refund_id: fin.refund_id,
          code: "refund_pending_reconcile",
          needs_reconcile: true,
        }, 500);
      }
      return jsonResponse(fin);
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

    // RTB-B-1245-P0/P1: reconciliar refund Stripe órfão ANTES do check
    // remaining=0 (senão retry cai em wallet_refund_covers_capture falso e
    // leave stripe_refund_id null → release seller minta wallet).
    let refund = await findExistingOrderRefund(stripe, paymentIntentId, orderId);
    if (refund) {
      const orphanCents = Number(refund.amount ?? 0);
      const finOrphan = await finalize(
        refund.id,
        paymentIntentId,
        sessionId,
        orphanCents > 0 ? orphanCents : euroToCents(order.price_total),
        true,
      );
      if (!finOrphan.ok) {
        return jsonResponse({
          ok: false,
          error: finOrphan.error,
          refund_id: finOrphan.refund_id,
          code: "refund_pending_reconcile",
          needs_reconcile: true,
        }, 500);
      }
      return jsonResponse(finOrphan);
    }

    // Autoridade: amount_paid_cents da linha (bag) ≤ residual do PI.
    // Nunca default para captura completa do PI quando a linha tem parcela.
    const pi = await stripe.paymentIntents.retrieve(paymentIntentId);
    const captured = Number(pi.amount_received || pi.amount || 0);
    const listedForCap = await stripe.refunds.list({
      payment_intent: paymentIntentId,
      limit: 20,
    });
    const alreadyOut = refundedCentsOnPi(listedForCap.data);
    const remaining = Math.max(0, captured - alreadyOut);
    const rowPaid = Number(order.amount_paid_cents ?? 0);
    const fromPrice = euroToCents(order.price_total);
    let amountCents = rowPaid > 0 ? rowPaid : fromPrice;
    if (amountCents <= 0 && remaining > 0 && alreadyOut === 0) {
      // Order única sem amount_paid: fallback captura residual.
      amountCents = remaining;
    }

    // RTC-C-P0-001: não reembolsar no cartão o que já foi creditado na wallet.
    const paidAuthority = rowPaid > 0 ? rowPaid : captured;
    const stripeResidualAfterWallet = Math.max(
      0,
      paidAuthority - walletRefundCents,
    );
    amountCents = Math.min(amountCents, remaining, stripeResidualAfterWallet);
    if (amountCents <= 0) {
      if (walletRefundCents > 0 || walletFlag) {
        return jsonResponse({
          ok: false,
          skipped: true,
          reason: "wallet_refund_covers_capture",
          code: "wallet_refund_already_processed",
          wallet_refund_cents: walletRefundCents,
          wallet_refund_flag: walletFlag,
          error:
            "Esta encomenda já foi reembolsada em carteira. Não há valor residual no cartão.",
        }, 422);
      }
      return jsonResponse({
        ok: false,
        error:
          "Sem valor residual neste pagamento para reembolsar esta encomenda.",
        code: "no_stripe_residual",
      }, 422);
    }

    amountCents = Math.min(amountCents, remaining);
    if (amountCents <= 0) {
      return jsonResponse({
        ok: false,
        error:
          "Sem valor residual neste pagamento para reembolsar esta encomenda.",
      }, 422);
    }
    refund = await stripe.refunds.create(
      {
        payment_intent: paymentIntentId,
        amount: amountCents,
        reason: "requested_by_customer",
        metadata: {
          fleaber_order_id: orderId,
          fleaber_actor_id: actorId ?? "",
        },
      },
      { idempotencyKey: `fleaber_order_refund_${orderId}` },
    );

    // Persistência cedo do id: se crash antes do finalize, release seller
    // vê stripe_refund_id e não minta; retry finaliza via existingRefund.
    try {
      await supabase
        .from("orders")
        .update({ stripe_refund_id: refund.id })
        .eq("id", orderId)
        .is("stripe_refund_id", null);
    } catch (_) {
      /* best-effort seal */
    }

    if (crashPoint === "after_stripe_before_db") {
      return jsonResponse({
        ok: false,
        error: "crash_inject:after_stripe_before_db",
        refund_id: refund.id,
        payment_intent: paymentIntentId,
        code: "refund_pending_reconcile",
        needs_reconcile: true,
        crash_inject: true,
      }, 500);
    }

    const fin = await finalize(
      refund.id,
      paymentIntentId,
      sessionId,
      amountCents,
      false,
    );

    if (!fin.ok) {
      // Segunda tentativa imediata (rede/PostgREST flaky).
      const fin2 = await finalize(
        refund.id,
        paymentIntentId,
        sessionId,
        amountCents,
        false,
      );
      if (!fin2.ok) {
        return jsonResponse({
          ok: false,
          error: fin2.error,
          refund_id: refund.id,
          payment_intent: paymentIntentId,
          code: "refund_pending_reconcile",
          needs_reconcile: true,
        }, 500);
      }
      Object.assign(fin, fin2);
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

    if (crashPoint === "after_db_before_response") {
      return jsonResponse({
        ok: false,
        error: "crash_inject:after_db_before_response",
        refund_id: refund.id,
        code: "refund_pending_reconcile",
        needs_reconcile: true,
        crash_inject: true,
        note: "DB já cancelada — retry deve ser idempotente already_refunded",
      }, 500);
    }

    return jsonResponse({
      ...fin,
      // CEGA-P3-04: 2.º concurrent vê idempotent/already do finalize
      already_refunded: Boolean(
        fin.already_refunded || fin.idempotent === true,
      ),
      status_stripe: refund.status,
    });
  } catch (e) {
    console.error("refund-order failed", e);
    const message = e instanceof Error ? e.message : String(e);
    return jsonResponse({ ok: false, error: message }, 500);
  }
});
