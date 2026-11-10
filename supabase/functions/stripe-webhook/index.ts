/**
 * SEC-005 / ZIP 128 — Stripe webhook (BATATA).
 *
 * - checkout.session.* → settle (igual ao GET return URL; não duplica lógica)
 * - charge.dispute.* → freeze parcial / resolução (RPC batata_*)
 * - account.updated → sync KYC/transfers na carteira (ZIP 166)
 * - transfer.reversed / transfer.canceled → repor saldo ledger (ZIP 166)
 *   (transfer.failed deprecated na API Stripe — não aparece no Dashboard)
 *
 * Não remove settle via GET. Não cobra cartões guardados. Não activa Live.
 *
 * Secrets ZIP 172:
 *   TEST: STRIPE_SECRET_KEY_TEST|STRIPE_SECRET_KEY + STRIPE_WEBHOOK_SECRET_TEST|STRIPE_WEBHOOK_SECRET
 *   LIVE: STRIPE_SECRET_KEY_LIVE + STRIPE_WEBHOOK_SECRET_LIVE + OPS_STRIPE_LIVE_GO=1
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 * Sem fallback LIVE → STRIPE_SECRET_KEY global.
 *
 * Events Dashboard: checkout.session.completed,
 *   checkout.session.async_payment_succeeded,
 *   charge.dispute.created, charge.dispute.updated, charge.dispute.closed,
 *   account.updated, transfer.reversed, transfer.canceled
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";
import {
  listStripeWebhookSecretsForVerify,
  normalizeStripeMode,
  resolveStripeSecretForMode,
  webhookLivemodeAllowed,
} from "../_shared/ops_env.ts";

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

type AdminClient = ReturnType<typeof createClient>;

async function resolveOrderForDispute(
  admin: AdminClient,
  dispute: Stripe.Dispute,
): Promise<{ orderId: string | null; sellerId: string | null }> {
  const pi = typeof dispute.payment_intent === "string"
    ? dispute.payment_intent
    : dispute.payment_intent?.id ?? null;
  const charge = typeof dispute.charge === "string"
    ? dispute.charge
    : dispute.charge?.id ?? null;

  if (pi) {
    const { data } = await admin
      .from("orders")
      .select("id,seller_id")
      .eq("stripe_payment_intent_id", pi)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (data?.id) {
      return { orderId: data.id as string, sellerId: (data.seller_id as string) ?? null };
    }
  }
  if (charge) {
    const { data: byCharge } = await admin
      .from("orders")
      .select("id,seller_id")
      .eq("stripe_charge_id", charge)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (byCharge?.id) {
      return {
        orderId: byCharge.id as string,
        sellerId: (byCharge.seller_id as string) ?? null,
      };
    }
  }
  return { orderId: null, sellerId: null };
}

async function handleAccountUpdated(
  admin: AdminClient,
  event: Stripe.Event,
): Promise<Response> {
  const account = event.data.object as Stripe.Account;
  const accountId = (account.id ?? "").trim();
  const fleaberUserId = String(account.metadata?.fleaber_user_id ?? "").trim();
  if (!accountId || !fleaberUserId) {
    return json({ ok: true, skipped: "account_missing_fleaber_user" });
  }
  const transfers = account.capabilities?.transfers;
  const transfersStatus = typeof transfers === "string"
    ? transfers
    : (transfers as { status?: string } | undefined)?.status ?? null;
  const { data, error } = await admin.rpc("batata_sync_stripe_connect_account", {
    p_user_id: fleaberUserId,
    p_stripe_account_id: accountId,
    p_details_submitted: account.details_submitted === true,
    p_transfers_status: transfersStatus,
    p_charges_enabled: account.charges_enabled === true,
    p_payouts_enabled: account.payouts_enabled === true,
    p_stripe_event_id: event.id,
  });
  if (error) {
    console.error("stripe-webhook account.updated sync failed", error);
    return json({ ok: false, error: "connect_sync_failed" }, 500);
  }
  return json({ ok: true, account_updated: true, sync: data });
}

async function handleTransferFailed(
  admin: AdminClient,
  event: Stripe.Event,
): Promise<Response> {
  const transfer = event.data.object as Stripe.Transfer;
  const transferId = (transfer.id ?? "").trim();
  if (!transferId) {
    return json({ ok: true, skipped: "no_transfer_id" });
  }
  const { data, error } = await admin.rpc(
    "batata_wallet_payout_fail_by_transfer_id",
    {
      p_stripe_transfer_id: transferId,
      p_stripe_event_id: event.id,
    },
  );
  if (error) {
    console.error("stripe-webhook transfer fail reconcile", error);
    return json({ ok: false, error: "transfer_fail_reconcile" }, 500);
  }
  return json({
    ok: true,
    transfer_event: event.type,
    reconcile: data,
  });
}

async function handleDisputeEvent(
  admin: AdminClient,
  event: Stripe.Event,
): Promise<Response> {
  const dispute = event.data.object as Stripe.Dispute;
  const disputeId = (dispute.id ?? "").trim();
  if (!disputeId) {
    return json({ ok: true, skipped: "no_dispute_id" });
  }

  const { orderId, sellerId } = await resolveOrderForDispute(admin, dispute);
  const amountCents = typeof dispute.amount === "number" ? dispute.amount : 0;
  const status = String(dispute.status ?? "needs_response");
  const reason = dispute.reason ? String(dispute.reason) : null;
  const chargeId = typeof dispute.charge === "string"
    ? dispute.charge
    : dispute.charge?.id ?? null;
  const piId = typeof dispute.payment_intent === "string"
    ? dispute.payment_intent
    : dispute.payment_intent?.id ?? null;
  const evidenceDue = dispute.evidence_details?.due_by
    ? new Date(dispute.evidence_details.due_by * 1000).toISOString()
    : null;

  const isTerminal = event.type === "charge.dispute.closed" ||
    ["won", "lost", "warning_closed", "charge_refunded"].includes(status);

  if (isTerminal && (status === "won" || status === "warning_closed" ||
    status === "lost" || status === "charge_refunded")) {
    const { data: releaseData, error: releaseErr } = await admin.rpc(
      "batata_release_stripe_dispute_freeze",
      {
        p_stripe_dispute_id: disputeId,
        p_final_status: status,
        p_stripe_event_id: event.id,
      },
    );
    if (releaseErr) {
      console.error("stripe-webhook dispute release failed", releaseErr);
      return json({ ok: false, error: "dispute_release_failed" }, 500);
    }
    // Se closed sem row prévia (missed created), ainda assim regista freeze=0 via apply
    if (!releaseData || (releaseData as { error?: string }).error === "not_found") {
      const { error: freezeErr } = await admin.rpc(
        "batata_apply_stripe_dispute_freeze",
        {
          p_stripe_dispute_id: disputeId,
          p_order_id: orderId,
          p_seller_id: sellerId,
          p_amount_cents: amountCents,
          p_status: status,
          p_reason: reason,
          p_charge_id: chargeId,
          p_payment_intent_id: piId,
          p_stripe_event_id: event.id,
          p_evidence_due_by: evidenceDue,
          p_raw: {
            status,
            reason,
            event_type: event.type,
          },
        },
      );
      if (freezeErr) {
        console.error("stripe-webhook dispute late-register failed", freezeErr);
        return json({ ok: false, error: "dispute_register_failed" }, 500);
      }
      await admin.rpc("batata_release_stripe_dispute_freeze", {
        p_stripe_dispute_id: disputeId,
        p_final_status: status,
        p_stripe_event_id: `${event.id}:close`,
      });
    }
    try {
      await admin.from("stripe_checkout_events").insert({
        session_id: disputeId,
        order_id: orderId,
        event: `webhook.${event.type}`,
        detail: JSON.stringify({
          stripe_event_id: event.id,
          status,
          amount_cents: amountCents,
          seller_id: sellerId,
        }),
      });
    } catch (_) { /* soft */ }
    return json({
      ok: true,
      dispute_id: disputeId,
      handled: "closed",
      status,
      order_id: orderId,
    });
  }

  const { data, error } = await admin.rpc("batata_apply_stripe_dispute_freeze", {
    p_stripe_dispute_id: disputeId,
    p_order_id: orderId,
    p_seller_id: sellerId,
    p_amount_cents: amountCents,
    p_status: status,
    p_reason: reason,
    p_charge_id: chargeId,
    p_payment_intent_id: piId,
    p_stripe_event_id: event.id,
    p_evidence_due_by: evidenceDue,
    p_raw: {
      status,
      reason,
      event_type: event.type,
      network_reason_code: (dispute as { network_reason_code?: string })
        .network_reason_code ?? null,
    },
  });

  if (error) {
    console.error("stripe-webhook dispute freeze failed", error);
    return json({ ok: false, error: "dispute_freeze_failed" }, 500);
  }

  try {
    await admin.from("stripe_checkout_events").insert({
      session_id: disputeId,
      order_id: orderId,
      event: `webhook.${event.type}`,
      detail: JSON.stringify({
        stripe_event_id: event.id,
        status,
        amount_cents: amountCents,
        seller_id: sellerId,
        freeze: data,
      }),
    });
  } catch (_) { /* soft */ }

  // Notificação seller (best-effort; não duplica E1–E3)
  if (sellerId && event.type === "charge.dispute.created") {
    try {
      const { data: nid } = await admin.rpc("batata_emit_user_notification", {
        p_recipient_id: sellerId,
        p_kind: "stripe_dispute_opened",
        p_title: "Contestação bancária na tua venda",
        p_body:
          "Foi aberta uma disputa Stripe sobre uma venda. O valor contestado ficou retido na carteira. Responde com provas na área da encomenda.",
        p_chat_id: null,
        p_product_id: null,
        p_offer_id: null,
        p_actor_id: null,
        p_dedupe_key: `stripe_dispute:${disputeId}:created`,
        p_order_id: orderId,
      });
      if (nid) {
        const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
        const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
        fetch(`${supabaseUrl}/functions/v1/notify-dispatch`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${serviceRoleKey}`,
            apikey: serviceRoleKey,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ notification_id: nid }),
        }).catch(() => {});
      }
    } catch (notifyErr) {
      console.warn("stripe-webhook dispute notify soft-fail", notifyErr);
    }
  }

  return json({
    ok: true,
    dispute_id: disputeId,
    handled: "freeze",
    status,
    order_id: orderId,
    result: data,
  });
}

async function handleCheckoutSettle(
  supabaseUrl: string,
  serviceRoleKey: string,
  event: Stripe.Event,
): Promise<Response> {
  const session = event.data.object as Stripe.Checkout.Session;
  const sessionId = (session.id ?? "").trim();
  if (!sessionId) {
    return json({ ok: true, skipped: "no_session_id" });
  }

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
    const settleRes = await fetch(settleUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${serviceRoleKey}`,
        apikey: serviceRoleKey,
      },
      redirect: "manual",
    });
    settleStatus = settleRes.status;
    settleOk = settleStatus === 200 || settleStatus === 303;
    if (!settleOk && settleStatus === 429) {
      const orderId = session.metadata?.order_id ?? "";
      if (orderId) {
        try {
          const adminCheck = createClient(supabaseUrl, serviceRoleKey, {
            auth: { persistSession: false },
          });
          const { data: ord } = await adminCheck
            .from("orders")
            .select("status")
            .eq("id", orderId)
            .maybeSingle();
          const st = String(ord?.status ?? "").toLowerCase();
          if (
            st === "pago" ||
            st === "enviado" ||
            st === "entregue" ||
            st === "concluido"
          ) {
            settleOk = true;
          }
        } catch (_) { /* retry */ }
      }
    }
  } catch (e) {
    console.error("stripe-webhook settle fetch failed", e);
    settleOk = false;
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // Stamp canal C2C/B2C após settle (idempotente)
  const orderIdStamp = (session.metadata?.order_id ?? "").trim();
  if (settleOk && orderIdStamp && !isTip) {
    try {
      await admin.rpc("batata_stamp_order_commerce_channel", {
        p_order_id: orderIdStamp,
      });
    } catch (stampErr) {
      console.warn("stripe-webhook stamp commerce soft-fail", stampErr);
    }
  }

  try {
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

  // ZIP 149.1: settle 5xx no replay mas encomendas já liquidadas → OK idempotente
  if (!settleOk && !isTip) {
    try {
      const bagCsv = String(session.metadata?.bag_order_ids ?? "").trim();
      const ids: string[] = [];
      if (bagCsv.length > 0) {
        for (const raw of bagCsv.split(",")) {
          const s = raw.trim();
          if (!s) continue;
          // Compact UUID (sem hífens) → hífenado
          if (/^[0-9a-fA-F]{32}$/.test(s)) {
            ids.push(
              `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20)}`,
            );
          } else {
            ids.push(s);
          }
        }
      } else if (orderIdStamp) {
        ids.push(orderIdStamp);
      }
      if (ids.length > 0) {
        const { data: rows } = await admin
          .from("orders")
          .select("id, status")
          .in("id", ids);
        const liquidated = new Set([
          "pago",
          "enviado",
          "entregue",
          "concluido",
          "concluído",
        ]);
        if (
          (rows ?? []).length === ids.length &&
          (rows ?? []).every((r) =>
            liquidated.has(String(r.status ?? "").toLowerCase())
          )
        ) {
          settleOk = true;
          try {
            await admin.from("stripe_checkout_events").insert({
              session_id: sessionId,
              order_id: session.metadata?.order_id ?? null,
              event: "webhook.checkout.session.settled_idempotent",
              detail: JSON.stringify({
                stripe_event_id: event.id,
                prior_settle_http_status: settleStatus,
                order_ids: ids,
              }),
            });
          } catch (_) { /* soft */ }
        }
      }
    } catch (idemErr) {
      console.warn("stripe-webhook idempotent check failed", idemErr);
    }
  }

  if (!settleOk) {
    return json({ ok: false, settle_http_status: settleStatus }, 500);
  }

  if (!isTip) {
    try {
      const orderId = (session.metadata?.order_id ?? "").trim();
      if (orderId) {
        const { data: ord } = await admin
          .from("orders")
          .select("id,buyer_id,seller_id")
          .eq("id", orderId)
          .maybeSingle();
        const buyer = ord?.buyer_id as string | undefined;
        const seller = ord?.seller_id as string | undefined;
        const emit = async (
          recipient: string,
          kind: string,
          title: string,
          body: string,
          dedupe: string,
        ) => {
          const { data: nid } = await admin.rpc(
            "batata_emit_user_notification",
            {
              p_recipient_id: recipient,
              p_kind: kind,
              p_title: title,
              p_body: body,
              p_chat_id: null,
              p_product_id: null,
              p_offer_id: null,
              p_actor_id: null,
              p_dedupe_key: dedupe,
              p_order_id: orderId,
            },
          );
          if (nid) {
            fetch(`${supabaseUrl}/functions/v1/notify-dispatch`, {
              method: "POST",
              headers: {
                Authorization: `Bearer ${serviceRoleKey}`,
                apikey: serviceRoleKey,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({ notification_id: nid }),
            }).catch(() => {});
          }
        };
        if (buyer) {
          await emit(
            buyer,
            "order_paid_buyer",
            "Já está! A tua compra na Fleaber foi confirmada",
            "O pagamento da tua compra foi confirmado.",
            `order_paid:${orderId}:buyer`,
          );
        }
        if (seller) {
          await emit(
            seller,
            "order_paid_seller",
            "🎉 Parabéns! Fizeste uma venda na Fleaber!",
            "Parabéns — o pagamento desta venda já está confirmado.",
            `order_paid:${orderId}:seller`,
          );
        }
      }
    } catch (notifyErr) {
      console.warn("stripe-webhook notify soft-fail", notifyErr);
    }
  }

  return json({
    ok: true,
    session_id: sessionId,
    settle_http_status: settleStatus,
    purpose: isTip ? "live_tip" : "checkout",
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*" } });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!supabaseUrl || !serviceRoleKey) {
    console.error("stripe-webhook missing Supabase config");
    return json({ ok: false, error: "config" }, 500);
  }

  const verifySecrets = listStripeWebhookSecretsForVerify();
  if (verifySecrets.length === 0) {
    console.error("stripe-webhook missing webhook secrets (TEST/LIVE)");
    return json({ ok: false, error: "config" }, 500);
  }

  const signature = req.headers.get("stripe-signature");
  if (!signature) {
    return json({ ok: false, error: "missing_signature" }, 400);
  }

  const rawBody = await req.text();
  const cryptoProvider = Stripe.createSubtleCryptoProvider();
  // Cliente só para constructEvent — a chave API é escolhida após livemode.
  // Só para constructEventAsync (não chama a API Stripe com esta chave).
  const stripeProbe = new Stripe(
    "sk_test_00000000000000000000000000000000",
    {
      apiVersion: "2024-06-20",
      httpClient: Stripe.createFetchHttpClient(),
    },
  );

  let event: Stripe.Event | null = null;
  let matchedSource = "";
  for (const cand of verifySecrets) {
    try {
      event = await stripeProbe.webhooks.constructEventAsync(
        rawBody,
        signature,
        cand.secret,
        undefined,
        cryptoProvider,
      );
      matchedSource = cand.source;
      break;
    } catch {
      // tenta o próximo secret (TEST vs LIVE)
    }
  }
  if (!event) {
    console.error("stripe-webhook signature failed all secrets");
    return json({ ok: false, error: "invalid_signature" }, 400);
  }

  const eventMode = event.livemode === true ? "live" : "test";
  const stripeResolved = resolveStripeSecretForMode(eventMode);
  if (!stripeResolved.ok || !stripeResolved.key) {
    console.error(
      "stripe-webhook blocked mode",
      eventMode,
      stripeResolved.error,
      matchedSource,
    );
    return json({
      ok: false,
      error: stripeResolved.error ?? "stripe_mode_blocked",
      event_mode: eventMode,
    }, 403);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // Isolamento sticky: se o evento aponta para uma order, livemode ↔ ops_stripe_mode.
  try {
    const obj = event.data.object as {
      metadata?: { order_id?: string };
      id?: string;
    };
    const metaOrderId = String(obj?.metadata?.order_id ?? "").trim();
    let orderId = metaOrderId;
    if (!orderId && typeof obj?.id === "string" && obj.id.startsWith("cs_")) {
      const { data: byCs } = await admin
        .from("orders")
        .select("id, ops_stripe_mode")
        .eq("stripe_checkout_session_id", obj.id)
        .maybeSingle();
      if (byCs?.id) {
        orderId = byCs.id as string;
        const orderMode = normalizeStripeMode(
          (byCs as { ops_stripe_mode?: string }).ops_stripe_mode,
        );
        const gate = webhookLivemodeAllowed(event.livemode === true, orderMode);
        if (!gate.ok) {
          console.error("stripe-webhook livemode/order mismatch", gate.error);
          return json({ ok: false, error: gate.error }, 403);
        }
      }
    } else if (orderId) {
      const { data: ord } = await admin
        .from("orders")
        .select("ops_stripe_mode")
        .eq("id", orderId)
        .maybeSingle();
      if (ord) {
        const orderMode = normalizeStripeMode(
          (ord as { ops_stripe_mode?: string }).ops_stripe_mode,
        );
        const gate = webhookLivemodeAllowed(event.livemode === true, orderMode);
        if (!gate.ok) {
          console.error("stripe-webhook livemode/order mismatch", gate.error);
          return json({ ok: false, error: gate.error }, 403);
        }
      }
    }
  } catch (isoErr) {
    console.warn("stripe-webhook isolation check soft-fail", isoErr);
  }

  if (
    event.type === "charge.dispute.created" ||
    event.type === "charge.dispute.updated" ||
    event.type === "charge.dispute.closed"
  ) {
    return await handleDisputeEvent(admin, event);
  }

  if (event.type === "account.updated") {
    return await handleAccountUpdated(admin, event);
  }

  if (
    event.type === "transfer.failed" ||
    event.type === "transfer.reversed" ||
    event.type === "transfer.canceled"
  ) {
    return await handleTransferFailed(admin, event);
  }

  const handledCheckout = new Set([
    "checkout.session.completed",
    "checkout.session.async_payment_succeeded",
  ]);
  if (!handledCheckout.has(event.type)) {
    return json({ ok: true, ignored: event.type });
  }

  // ZIP 140/142 — diferença de portes: NUNCA cair em settle de venda.
  {
    const session = event.data.object as Stripe.Checkout.Session;
    const mode = String(session.metadata?.fleaber_mode ?? "").trim();
    if (mode === "shipping_delta") {
      try {
        const adjId = String(session.metadata?.adjustment_id ?? "").trim();
        const orderId = String(session.metadata?.order_id ?? "").trim();
        const pi = typeof session.payment_intent === "string"
          ? session.payment_intent
          : session.payment_intent?.id ?? "";
        if (!adjId || !pi) {
          return json({
            ok: false,
            error: "shipping_delta_missing_meta",
          }, 400);
        }
        // Idempotente: RPC mark paid é no-op se já paid.
        const { data: marked, error: markErr } = await admin.rpc(
          "batata_mark_shipping_adjustment_paid",
          {
            p_adjustment_id: adjId,
            p_payment_intent_id: pi,
            p_checkout_session_id: session.id,
          },
        );
        if (markErr) {
          console.error("shipping_delta mark failed", markErr);
          return json({ ok: false, error: "shipping_delta_mark_failed" }, 500);
        }
        try {
          const buyer = String(session.metadata?.buyer_id ?? "").trim();
          const seller = String(session.metadata?.seller_id ?? "").trim();
          const emit = async (
            recipient: string,
            kind: string,
            title: string,
            body: string,
            dedupe: string,
          ) => {
            const { data: nid } = await admin.rpc(
              "batata_emit_user_notification",
              {
                p_recipient_id: recipient,
                p_kind: kind,
                p_title: title,
                p_body: body,
                p_chat_id: null,
                p_product_id: null,
                p_offer_id: null,
                p_actor_id: null,
                p_dedupe_key: dedupe,
                p_order_id: orderId || null,
              },
            );
            if (nid) {
              fetch(`${supabaseUrl}/functions/v1/notify-dispatch`, {
                method: "POST",
                headers: {
                  Authorization: `Bearer ${serviceRoleKey}`,
                  apikey: serviceRoleKey,
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({ notification_id: nid }),
              }).catch(() => {});
            }
          };
          if (seller) {
            await emit(
              seller,
              "shipping_delta_paid",
              "Diferença de portes paga",
              "O comprador pagou a diferença de portes. Podes preparar o envio.",
              `ship_delta:${orderId}:paid`,
            );
          }
          if (buyer) {
            await emit(
              buyer,
              "shipping_delta_paid",
              "Diferença de portes confirmada",
              "O pagamento da diferença de portes foi confirmado.",
              `ship_delta:${orderId}:paid:buyer`,
            );
          }
        } catch (nerr) {
          console.warn("shipping_delta notify soft-fail", nerr);
        }
        return json({
          ok: true,
          fleaber_mode: "shipping_delta",
          adjustment_id: adjId,
          marked,
          settled_as_sale: false,
          stock_touched: false,
          wallet_released: false,
          order_paid_emails: false,
        });
      } catch (deltaErr) {
        console.error("shipping_delta webhook branch", deltaErr);
        // Fail-closed: NUNCA handleCheckoutSettle para shipping_delta.
        return json({
          ok: false,
          error: "shipping_delta_handler_failed",
          settled_as_sale: false,
        }, 500);
      }
    }
  }

  return await handleCheckoutSettle(supabaseUrl, serviceRoleKey, event);
});
