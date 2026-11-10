/**
 * FASE 2 E2E — oversell refund Stripe Test (staging).
 * Paga com PaymentIntent + pm_card_visa (Checkout neste account adia PI).
 * Settle/refund via create-payment-intent?fase2_e2e_settle=1 (mesmo refundOversoldStripeOrder).
 * Secret nunca sai da Edge. Só sk_test_ + service_role.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";
import { assertDestructiveHarnessAllowed } from "../_shared/destructive_harness_gate.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const gate = assertDestructiveHarnessAllowed();
  if (!gate.ok) {
    return json({ ok: false, error: gate.error }, gate.status);
  }
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ ok: false, error: "env" }, 500);
  }

  // Autorização: NÃO confiar em JWT alg=none / claims.
  // Aceitar (a) Bearer == SERVICE_ROLE_KEY, ou (b) header secret de staging
  // (FLEABER_STAGING_CRASH_INJECT_SECRET) — só com sk_test_.
  const token = (req.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  const expected = serviceRoleKey.trim();
  const e2eSecret = (Deno.env.get("FLEABER_STAGING_CRASH_INJECT_SECRET") ?? "")
    .trim();
  const hdrSecret = (req.headers.get("x-fleaber-e2e-secret") ?? "").trim();
  const okService = expected.length > 0 && timingSafeEqualStr(token, expected);
  const okE2e = e2eSecret.length >= 16 && timingSafeEqualStr(hdrSecret, e2eSecret);
  if (!okService && !okE2e) {
    return json({ ok: false, error: "Só service_role" }, 401);
  }

  const body = await req.json().catch(() => ({})) as {
    buyer_id?: string;
    seller_id?: string;
    probe?: string;
    payment_intent_id?: string;
    product_id?: string;
    product_a_id?: string;
    product_b_id?: string;
    initial_qty?: number;
    buyer_access_token?: string;
  };
  const buyerId = (body.buyer_id ?? "").trim();
  const sellerId = (body.seller_id ?? "").trim();
  const probe = (body.probe ?? "").trim();
  const buyerAccessToken = (body.buyer_access_token ?? "").trim();

  const stripe = new Stripe(stripeSecretKey, {
    apiVersion: "2024-06-20",
    httpClient: Stripe.createFetchHttpClient(),
  });
  const sb = createClient(supabaseUrl, serviceRoleKey);
  const settleUrl =
    `${supabaseUrl}/functions/v1/create-payment-intent?fase2_e2e_settle=1`;
  const serverAmount = 590;

  // ----- P2-04: bag multi-line amount_paid_cents proporcional -----
  if (probe === "setup_paid_bag") {
    if (!buyerId || !sellerId) {
      return json({ ok: false, error: "buyer_id/seller_id" }, 400);
    }
    const stamp = Date.now();
    const priceAEur = 3.0;
    const priceBEur = 7.0;
    const itemsCents = Math.round(priceAEur * 100) + Math.round(priceBEur * 100);
    const shippingCents = 0; // mão
    const baseEur = (itemsCents + shippingCents) / 100;
    const protEur =
      Math.round((0.65 + baseEur * 0.05) * 100) / 100;
    const protectionCents = Math.round(protEur * 100);
    const totalCents = itemsCents + shippingCents + protectionCents;
    // Alinhamento price_total como create-payment-intent (proporcional aos itens)
    const shareA = Math.round((totalCents * Math.round(priceAEur * 100)) / itemsCents);
    const shareB = totalCents - shareA;

    const { data: productA, error: paErr } = await sb.from("products").insert({
      seller_id: sellerId,
      title: `Bag E2E A ${stamp}`,
      price: priceAEur,
      quantity: 3,
      ref_code: `BAG-A-${stamp}`,
      list_on_marketplace: true,
      available_for_live: false,
      is_sold: false,
      image_urls: [],
    }).select("id, quantity, price").single();
    if (paErr || !productA) throw paErr ?? new Error("productA");

    const { data: productB, error: pbErr } = await sb.from("products").insert({
      seller_id: sellerId,
      title: `Bag E2E B ${stamp}`,
      price: priceBEur,
      quantity: 3,
      ref_code: `BAG-B-${stamp}`,
      list_on_marketplace: true,
      available_for_live: false,
      is_sold: false,
      image_urls: [],
    }).select("id, quantity, price").single();
    if (pbErr || !productB) throw pbErr ?? new Error("productB");

    const { data: orderA, error: oaErr } = await sb.from("orders").insert({
      buyer_id: buyerId,
      seller_id: sellerId,
      product_id: productA.id,
      price_total: shareA / 100,
      quantity: 1,
      status: "reserva_pendente",
      payment_method: "Pagamento na app",
      shipping_method: "entrega em mão",
    }).select("id").single();
    if (oaErr || !orderA) throw oaErr ?? new Error("orderA");

    const { data: orderB, error: obErr } = await sb.from("orders").insert({
      buyer_id: buyerId,
      seller_id: sellerId,
      product_id: productB.id,
      price_total: shareB / 100,
      quantity: 1,
      status: "reserva_pendente",
      payment_method: "Pagamento na app",
      shipping_method: "entrega em mão",
    }).select("id").single();
    if (obErr || !orderB) throw obErr ?? new Error("orderB");

    const pi = await stripe.paymentIntents.create({
      amount: totalCents,
      currency: "eur",
      confirm: true,
      return_url: "https://fleaber.pt/",
      payment_method: "pm_card_visa",
      automatic_payment_methods: {
        enabled: true,
        allow_redirects: "never",
      },
      metadata: {
        fleaber_e2e: "bag_p204",
        bag_checkout: "true",
        buyer_id: buyerId,
        seller_id: sellerId,
        order_id: orderA.id as string,
        server_amount_cents: String(totalCents),
      },
    });
    if (pi.status !== "succeeded") {
      throw new Error(`PI status=${pi.status}`);
    }

    const settleRes = await fetch(settleUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${serviceRoleKey}`,
        apikey: serviceRoleKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        bag_checkout: true,
        payment_intent_id: pi.id,
        buyer_id: buyerId,
        seller_id: sellerId,
        bag_lines: [
          { order_id: orderA.id, product_id: productA.id },
          { order_id: orderB.id, product_id: productB.id },
        ],
      }),
    });
    const settleBody = await settleRes.json().catch(() => ({}));

    const { data: ordersAfter } = await sb.from("orders").select(
      "id, status, price_total, amount_paid_cents, stock_units_applied, product_id",
    ).in("id", [orderA.id, orderB.id]);

    const byId = new Map(
      (ordersAfter ?? []).map((o) => [String(o.id), o]),
    );
    const paidA = Number(byId.get(String(orderA.id))?.amount_paid_cents ?? 0);
    const paidB = Number(byId.get(String(orderB.id))?.amount_paid_cents ?? 0);
    const piAmt = Number(pi.amount_received || pi.amount || 0);
    const expectedA = Math.round((piAmt * shareA) / totalCents);
    const expectedB = piAmt - expectedA;

    const noLineHasFull =
      paidA < piAmt && paidB < piAmt && paidA > 0 && paidB > 0;
    const sumOk = paidA + paidB === piAmt;
    const proportionalOk =
      Math.abs(paidA - expectedA) <= 1 && Math.abs(paidB - expectedB) <= 1;
    const bothPaid = (ordersAfter ?? []).every(
      (o) => String(o.status).toLowerCase() === "pago",
    );

    return json({
      ok: bothPaid && noLineHasFull && sumOk && proportionalOk &&
        settleRes.status === 200,
      probe: "setup_paid_bag",
      payment_intent_id: pi.id,
      pi_amount_cents: piAmt,
      total_cents_quote: totalCents,
      items_cents: itemsCents,
      protection_cents: protectionCents,
      share_a_cents: shareA,
      share_b_cents: shareB,
      expected_paid_a: expectedA,
      expected_paid_b: expectedB,
      paid_a: paidA,
      paid_b: paidB,
      order_a_id: orderA.id,
      order_b_id: orderB.id,
      product_a_id: productA.id,
      product_b_id: productB.id,
      settle_http: settleRes.status,
      settle_body: settleBody,
      orders: ordersAfter,
      checks: {
        both_pago: bothPaid,
        no_line_has_full_pi: noLineHasFull,
        sum_eq_pi: sumOk,
        proportional: proportionalOk,
      },
    });
  }

  if (probe === "cleanup_bag_fixture") {
    const ids = [
      (body as { product_a_id?: string }).product_a_id,
      (body as { product_b_id?: string }).product_b_id,
      body.product_id,
    ].map((x) => (x ?? "").trim()).filter(Boolean);
    for (const pid of ids) {
      await sb.from("orders").delete().eq("product_id", pid);
      await sb.from("products").delete().eq("id", pid);
    }
    return json({ ok: true, cleaned: ids });
  }

  // ----- TEST probes (staging harness only) -----
  if (probe === "list_stripe_refunds") {
    const piId = (body.payment_intent_id ?? "").trim();
    if (!piId) return json({ ok: false, error: "payment_intent_id" }, 400);
    const listed = await stripe.refunds.list({ payment_intent: piId, limit: 20 });
    const pi = await stripe.paymentIntents.retrieve(piId);
    return json({
      ok: true,
      payment_intent: {
        id: pi.id,
        status: pi.status,
        amount: pi.amount,
        amount_received: pi.amount_received,
      },
      refunds: listed.data.map((r) => ({
        id: r.id,
        status: r.status,
        amount: r.amount,
        metadata: r.metadata,
      })),
      refund_count: listed.data.length,
    });
  }

  if (probe === "cleanup_fixture") {
    const productId = (body.product_id ?? "").trim();
    if (!productId) return json({ ok: false, error: "product_id" }, 400);
    await sb.from("orders").delete().eq("product_id", productId);
    await sb.from("products").delete().eq("id", productId);
    return json({ ok: true, cleaned: productId });
  }

  if (probe === "orphan_second_pi_refund") {
    // RTBB-1115-P1: order pago (PI A) + 2.ª Session/PI B paga → settle B reembolsa B.
    try {
      if (!buyerId || !sellerId) {
        return json({ ok: false, error: "buyer_id/seller_id" }, 400);
      }
      const stamp = Date.now();
      const { data: product, error: pErr } = await sb.from("products").insert({
        seller_id: sellerId,
        title: `Orphan PI E2E ${stamp}`,
        price: 5.0,
        quantity: 2,
        ref_code: `ORPH-E2E-${stamp}`,
        list_on_marketplace: true,
        available_for_live: false,
        is_sold: false,
        image_urls: [],
      }).select("id").single();
      if (pErr || !product) {
        return json({ ok: false, error: "product", detail: pErr?.message }, 500);
      }
      const productId = product.id as string;
      const { data: order, error: oErr } = await sb.from("orders").insert({
        buyer_id: buyerId,
        seller_id: sellerId,
        product_id: productId,
        price_total: serverAmount / 100,
        quantity: 1,
        status: "reserva_pendente",
        payment_method: "Pagamento na app",
        shipping_method: "hand",
        contract_unit_cents: 500,
        contract_qty: 1,
      }).select("id").single();
      if (oErr || !order) {
        return json({ ok: false, error: "order", detail: oErr?.message }, 500);
      }
      const orderId = order.id as string;

      const piA = await stripe.paymentIntents.create({
        amount: serverAmount,
        currency: "eur",
        confirm: true,
        return_url: "https://fleaber.pt/",
        payment_method: "pm_card_visa",
        automatic_payment_methods: {
          enabled: true,
          allow_redirects: "never",
        },
        metadata: { fleaber_order_id: orderId, fleaber_e2e: "orphan_a" },
      });
      if (piA.status !== "succeeded") {
        return json({ ok: false, error: `piA=${piA.status}` }, 500);
      }
      await sb.from("orders").update({
        stripe_payment_intent_id: piA.id,
        amount_paid_cents: Number(piA.amount_received || piA.amount || 0),
        price_total: serverAmount / 100,
      }).eq("id", orderId);

      const settleA = await fetch(settleUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          order_id: orderId,
          payment_intent_id: piA.id,
          product_id: productId,
        }),
      });
      const settleABody = await settleA.json().catch(() => ({}));
      const { data: oPaid } = await sb.from("orders").select(
        "status, stripe_payment_intent_id, stripe_checkout_session_id, stripe_refund_id",
      ).eq("id", orderId).maybeSingle();
      if (String(oPaid?.status ?? "").toLowerCase() !== "pago") {
        return json({
          ok: false,
          error: "setup not pago",
          settleA: settleABody,
          order: oPaid,
        }, 500);
      }

      // Session B paga (metadata mesma order) — captura órfã.
      const sessionB = await stripe.checkout.sessions.create({
        mode: "payment",
        payment_method_types: ["card"],
        success_url:
          `${supabaseUrl}/functions/v1/create-payment-intent?checkout_return=success&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url:
          `${supabaseUrl}/functions/v1/create-payment-intent?checkout_return=cancel&session_id={CHECKOUT_SESSION_ID}`,
        line_items: [{
          quantity: 1,
          price_data: {
            currency: "eur",
            unit_amount: serverAmount,
            product_data: { name: `Orphan B ${stamp}` },
          },
        }],
        payment_intent_data: {
          metadata: {
            fleaber_order_id: orderId,
            fleaber_e2e: "orphan_b",
          },
        },
        metadata: {
          order_id: orderId,
          buyer_id: buyerId,
          seller_id: sellerId,
          product_id: productId,
          server_amount_cents: String(serverAmount),
          total: String(serverAmount),
          shipping_method: "hand",
        },
      });

      let piB = typeof sessionB.payment_intent === "string"
        ? sessionB.payment_intent
        : (sessionB.payment_intent as { id?: string } | null)?.id;
      if (!piB) {
        const full = await stripe.checkout.sessions.retrieve(sessionB.id, {
          expand: ["payment_intent"],
        });
        const raw = full.payment_intent;
        piB = typeof raw === "string"
          ? raw
          : (raw as { id?: string } | null)?.id;
      }
      if (!piB) {
        // Fallback: PI avulso + settle GET não serve; refund órfão via
        // refundOversold path simulando settleOrder (PI B ≠ PI A na order).
        const piBDirect = await stripe.paymentIntents.create({
          amount: serverAmount,
          currency: "eur",
          confirm: true,
          return_url: "https://fleaber.pt/",
          payment_method: "pm_card_visa",
          automatic_payment_methods: {
            enabled: true,
            allow_redirects: "never",
          },
          metadata: {
            fleaber_order_id: orderId,
            fleaber_e2e: "orphan_b_direct",
          },
        });
        if (piBDirect.status !== "succeeded") {
          return json({
            ok: false,
            error: `piB_direct=${piBDirect.status}`,
            session_b: sessionB.id,
          }, 500);
        }
        piB = piBDirect.id;
        // Invoca settle GET com Session B unpaid NÃO reembolsa.
        // Em vez disso: chama refund-order path? Não.
        // Usa create-payment-intent settleOrder via POST fase2 com PI B
        // enquanto order já pago → Edge settleOrderPaidOrRefundOversell.
        const settleB = await fetch(settleUrl, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${serviceRoleKey}`,
            apikey: serviceRoleKey,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            order_id: orderId,
            payment_intent_id: piB,
            product_id: productId,
            session_id: sessionB.id,
          }),
        });
        const settleBBody = await settleB.json().catch(() => ({}));
        const listed = await stripe.refunds.list({
          payment_intent: piB,
          limit: 5,
        });
        const refundB = listed.data.find((r) =>
          ["succeeded", "pending"].includes(String(r.status ?? "").toLowerCase())
        );
        const { data: oAfter } = await sb.from("orders").select(
          "status, stripe_payment_intent_id, stripe_refund_id",
        ).eq("id", orderId).maybeSingle();
        const ok = String(oAfter?.status ?? "").toLowerCase() === "pago" &&
          String(oAfter?.stripe_payment_intent_id ?? "") === piA.id &&
          Boolean(refundB) &&
          !oAfter?.stripe_refund_id;
        return json({
          ok,
          probe: "orphan_second_pi_refund",
          mode: "fase2_settle_dup_pi",
          order_id: orderId,
          pi_a: piA.id,
          pi_b: piB,
          session_b: sessionB.id,
          settle_b: settleBBody,
          refund_b_id: refundB?.id ?? null,
          order_status: oAfter?.status ?? null,
          order_pi: oAfter?.stripe_payment_intent_id ?? null,
        }, ok ? 200 : 500);
      }

      const confB = await stripe.paymentIntents.confirm(piB, {
        payment_method: "pm_card_visa",
        return_url: "https://fleaber.pt/",
      });
      if (confB.status !== "succeeded") {
        return json({ ok: false, error: `piB=${confB.status}` }, 500);
      }

      const settleGet =
        `${supabaseUrl}/functions/v1/create-payment-intent?checkout_return=success&session_id=${sessionB.id}`;
      const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? serviceRoleKey;
      const r2 = await fetch(settleGet, {
        method: "GET",
        headers: { Authorization: `Bearer ${anonKey}`, apikey: anonKey },
      });
      const t2 = await r2.text();
      const listed = await stripe.refunds.list({
        payment_intent: piB,
        limit: 5,
      });
      const refundB = listed.data.find((r) =>
        ["succeeded", "pending"].includes(String(r.status ?? "").toLowerCase())
      );
      const { data: oAfter } = await sb.from("orders").select(
        "status, stripe_payment_intent_id, stripe_refund_id",
      ).eq("id", orderId).maybeSingle();
      const ok = String(oAfter?.status ?? "").toLowerCase() === "pago" &&
        String(oAfter?.stripe_payment_intent_id ?? "") === piA.id &&
        Boolean(refundB);
      return json({
        ok,
        probe: "orphan_second_pi_refund",
        mode: "checkout_get_settle",
        order_id: orderId,
        pi_a: piA.id,
        pi_b: piB,
        session_b: sessionB.id,
        settle2_http: r2.status,
        settle2_clip: t2.slice(0, 200),
        refund_b_id: refundB?.id ?? null,
        order_status: oAfter?.status ?? null,
      }, ok ? 200 : 500);
    } catch (e) {
      return json({
        ok: false,
        probe: "orphan_second_pi_refund",
        error: e instanceof Error ? e.message : String(e),
      }, 500);
    }
  }

  if (probe === "settle_get_replay") {
    // S2-P0-01: order já pago + Session paga + GET settle 2× — sem refund.
    // (Checkout POST bloqueia status pago; Session criada na Stripe API como o return URL.)
    try {
      if (!buyerId || !sellerId) {
        return json({ ok: false, error: "buyer_id/seller_id" }, 400);
      }
      const stamp = Date.now();
      const { data: product, error: pErr } = await sb.from("products").insert({
        seller_id: sellerId,
        title: `Settle replay E2E ${stamp}`,
        price: 5.0,
        quantity: 2,
        ref_code: `SR-E2E-${stamp}`,
        list_on_marketplace: true,
        available_for_live: false,
        is_sold: false,
        image_urls: [],
      }).select("id").single();
      if (pErr || !product) {
        return json({
          ok: false,
          error: "product",
          detail: pErr?.message ?? String(pErr),
        }, 500);
      }
      const productId = product.id as string;

      const { data: order, error: oErr } = await sb.from("orders").insert({
        buyer_id: buyerId,
        seller_id: sellerId,
        product_id: productId,
        price_total: serverAmount / 100,
        quantity: 1,
        status: "reserva_pendente",
        payment_method: "Pagamento na app",
        shipping_method: "hand",
        contract_unit_cents: 500,
        contract_qty: 1,
      }).select("id").single();
      if (oErr || !order) {
        return json({
          ok: false,
          error: "order",
          detail: oErr?.message ?? String(oErr),
          product_id: productId,
        }, 500);
      }
      const orderId = order.id as string;

      // 1) Liquidar como o resto do E2E (PI + fase2_e2e_settle) → status pago.
      const piPay = await stripe.paymentIntents.create({
        amount: serverAmount,
        currency: "eur",
        confirm: true,
        return_url: "https://fleaber.pt/",
        payment_method: "pm_card_visa",
        automatic_payment_methods: {
          enabled: true,
          allow_redirects: "never",
        },
        metadata: {
          fleaber_order_id: orderId,
          fleaber_e2e: "settle_get_replay",
          product_id: productId,
        },
      });
      if (piPay.status !== "succeeded") {
        return json({
          ok: false,
          error: `setup PI status=${piPay.status}`,
          order_id: orderId,
        }, 500);
      }
      await sb.from("orders").update({
        stripe_payment_intent_id: piPay.id,
        amount_paid_cents: Number(piPay.amount_received || piPay.amount || 0),
        price_total: serverAmount / 100,
      }).eq("id", orderId);

      const settleSetup = await fetch(settleUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          order_id: orderId,
          payment_intent_id: piPay.id,
          product_id: productId,
        }),
      });
      const settleSetupBody = await settleSetup.json().catch(() => ({}));
      const { data: oPaid } = await sb.from("orders").select(
        "id, status, stripe_refund_id, stock_units_applied, amount_paid_cents",
      ).eq("id", orderId).maybeSingle();
      if (String(oPaid?.status ?? "").toLowerCase() !== "pago") {
        return json({
          ok: false,
          error: "setup settle did not reach pago",
          settle_http: settleSetup.status,
          settle_body: settleSetupBody,
          order: oPaid,
        }, 500);
      }

      // 2) Session Checkout — payment_intent_data força PI imediato (hosted pode adiar).
      const session = await stripe.checkout.sessions.create({
        mode: "payment",
        payment_method_types: ["card"],
        success_url:
          `${supabaseUrl}/functions/v1/create-payment-intent?checkout_return=success&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url:
          `${supabaseUrl}/functions/v1/create-payment-intent?checkout_return=cancel&session_id={CHECKOUT_SESSION_ID}`,
        line_items: [{
          quantity: 1,
          price_data: {
            currency: "eur",
            unit_amount: serverAmount,
            product_data: { name: `Settle replay ${stamp}` },
          },
        }],
        payment_intent_data: {
          metadata: {
            fleaber_order_id: orderId,
            fleaber_e2e: "settle_get_replay_session",
            product_id: productId,
          },
        },
        metadata: {
          order_id: orderId,
          buyer_id: buyerId,
          seller_id: sellerId,
          product_id: productId,
          server_amount_cents: String(serverAmount),
          total: String(serverAmount),
          shipping_method: "hand",
        },
      });

      let piId = typeof session.payment_intent === "string"
        ? session.payment_intent
        : (session.payment_intent as { id?: string } | null)?.id;
      if (!piId) {
        const retrieved = await stripe.checkout.sessions.retrieve(session.id, {
          expand: ["payment_intent"],
        });
        const raw = retrieved.payment_intent;
        piId = typeof raw === "string"
          ? raw
          : (raw as { id?: string } | null)?.id;
      }
      if (!piId) {
        // Fallback: PI avulso não serve para GET settle; falhar com diagnóstico.
        return json({
          ok: false,
          error: "session missing payment_intent",
          session_id: session.id,
          session_status: session.status,
          session_payment_status: session.payment_status,
        }, 500);
      }

      const piSess = await stripe.paymentIntents.confirm(piId, {
        payment_method: "pm_card_visa",
        return_url: "https://fleaber.pt/",
      });
      if (piSess.status !== "succeeded") {
        return json({
          ok: false,
          error: `session PI status=${piSess.status}`,
          session_id: session.id,
          payment_intent_id: piId,
        }, 500);
      }

      const settleGet =
        `${supabaseUrl}/functions/v1/create-payment-intent?checkout_return=success&session_id=${session.id}`;
      const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? serviceRoleKey;
      const h = {
        Authorization: `Bearer ${anonKey}`,
        apikey: anonKey,
      };
      const r1 = await fetch(settleGet, { method: "GET", headers: h });
      const t1 = await r1.text();
      const r2 = await fetch(settleGet, { method: "GET", headers: h });
      const t2 = await r2.text();

      const { data: oAfter } = await sb.from("orders").select(
        "id, status, stripe_refund_id, stock_units_applied, amount_paid_cents, stripe_checkout_session_id",
      ).eq("id", orderId).maybeSingle();
      const { data: pAfter } = await sb.from("products").select(
        "quantity, is_sold",
      ).eq("id", productId).maybeSingle();

      const st = String(oAfter?.status ?? "").toLowerCase();
      const ref = String(oAfter?.stripe_refund_id ?? "").trim();
      const ok = st === "pago" && ref.length === 0 &&
        !t2.includes("reembolsado automaticamente") &&
        !t2.includes("Artigo esgotado");

      return json({
        ok,
        probe: "settle_get_replay",
        order_id: orderId,
        product_id: productId,
        session_id: session.id,
        payment_intent_id: piId,
        setup_pi: piPay.id,
        settle1_http: r1.status,
        settle2_http: r2.status,
        settle1_clip: t1.slice(0, 240),
        settle2_clip: t2.slice(0, 240),
        order_before_replay: oPaid,
        order: oAfter,
        product: pAfter,
      }, ok ? 200 : 500);
    } catch (e) {
      return json({
        ok: false,
        probe: "settle_get_replay",
        error: e instanceof Error ? e.message : String(e),
      }, 500);
    }
  }

  if (probe === "setup_paid_order") {
    if (!buyerId || !sellerId) {
      return json({ ok: false, error: "buyer_id/seller_id" }, 400);
    }
    const initialQty = Math.max(Number(body.initial_qty ?? 2), 1);
    const stamp = Date.now();
    const { data: walletBuyer } = await sb.from("wallets").select("balance")
      .eq("id", buyerId).maybeSingle();
    const { data: walletSeller } = await sb.from("wallets").select("balance")
      .eq("id", sellerId).maybeSingle();

    const { data: product, error: pErr } = await sb.from("products").insert({
      seller_id: sellerId,
      title: `Refund crash E2E ${stamp}`,
      price: serverAmount / 100,
      quantity: initialQty,
      ref_code: `RC-E2E-${stamp}`,
      list_on_marketplace: true,
      available_for_live: false,
      is_sold: false,
      image_urls: [],
    }).select("id, quantity").single();
    if (pErr || !product) throw pErr ?? new Error("product");

    const productId = product.id as string;
    const { data: order, error: oErr } = await sb.from("orders").insert({
      buyer_id: buyerId,
      seller_id: sellerId,
      product_id: productId,
      price_total: serverAmount / 100,
      quantity: 1,
      status: "reserva_pendente",
      payment_method: "Pagamento na app",
    }).select("id").single();
    if (oErr || !order) throw oErr ?? new Error("order");
    const orderId = order.id as string;

    const pi = await stripe.paymentIntents.create({
      amount: serverAmount,
      currency: "eur",
      confirm: true,
      return_url: "https://fleaber.pt/",
      payment_method: "pm_card_visa",
      automatic_payment_methods: {
        enabled: true,
        allow_redirects: "never",
      },
      metadata: {
        fleaber_order_id: orderId,
        fleaber_e2e: "refund_crash_setup",
        product_id: productId,
      },
    });
    if (pi.status !== "succeeded") {
      throw new Error(`PI status=${pi.status}`);
    }

    await sb.from("orders").update({
      stripe_payment_intent_id: pi.id,
      price_total: serverAmount / 100,
      amount_paid_cents: Number(pi.amount_received || pi.amount || 0),
    }).eq("id", orderId);

    const settleRes = await fetch(settleUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${serviceRoleKey}`,
        apikey: serviceRoleKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        order_id: orderId,
        payment_intent_id: pi.id,
        product_id: productId,
      }),
    });
    const settleBody = await settleRes.json().catch(() => ({}));

    const { data: oAfter } = await sb.from("orders").select(
      "id, status, stock_units_applied, stripe_refund_id, stripe_payment_intent_id, price_total, amount_paid_cents",
    ).eq("id", orderId).maybeSingle();
    const { data: pAfter } = await sb.from("products").select(
      "quantity, is_sold",
    ).eq("id", productId).maybeSingle();

    return json({
      ok: String(oAfter?.status).toLowerCase() === "pago",
      order_id: orderId,
      product_id: productId,
      payment_intent_id: pi.id,
      pi_status: pi.status,
      pi_amount_received: pi.amount_received,
      initial_qty: initialQty,
      settle_http: settleRes.status,
      settle_body: settleBody,
      order: oAfter,
      product: pAfter,
      buyer_wallet_before: walletBuyer?.balance ?? null,
      seller_wallet_before: walletSeller?.balance ?? null,
    }, String(oAfter?.status).toLowerCase() === "pago" ? 200 : 500);
  }

  if (!buyerId || !sellerId) {
    return json({ ok: false, error: "buyer_id/seller_id" }, 400);
  }

  const evidence: Record<string, unknown> = {
    at: new Date().toISOString(),
    mode: "stripe_test",
    note:
      "Pagamentos via PaymentIntent Test (pm_card_visa). Refund via create-payment-intent refundOversoldStripeOrder.",
  };

  try {
    const { data: walletBefore } = await sb.from("wallets").select("balance")
      .eq("id", sellerId).maybeSingle();
    evidence.seller_wallet_before = walletBefore?.balance ?? null;

    const stamp = Date.now();
    const { data: product, error: pErr } = await sb.from("products").insert({
      seller_id: sellerId,
      title: `F2 E2E oversell ${stamp}`,
      price: 5,
      quantity: 1,
      ref_code: `F2E2E-${stamp}`,
      list_on_marketplace: true,
      available_for_live: false,
      is_sold: false,
      image_urls: [],
    }).select("id, quantity").single();
    if (pErr || !product) throw pErr ?? new Error("product");
    const productId = product.id as string;
    evidence.product_id = productId;

    const mkOrder = async () => {
      const { data: order, error } = await sb.from("orders").insert({
        buyer_id: buyerId,
        seller_id: sellerId,
        product_id: productId,
        price_total: serverAmount / 100,
        quantity: 1,
        status: "reserva_pendente",
        payment_method: "Pagamento na app",
      }).select("id").single();
      if (error || !order) throw error ?? new Error("order");
      return order.id as string;
    };
    const orderA = await mkOrder();
    const orderB = await mkOrder();
    evidence.order_a_id = orderA;
    evidence.order_b_id = orderB;

    async function payPi(orderId: string, tag: string) {
      const pi = await stripe.paymentIntents.create({
        amount: serverAmount,
        currency: "eur",
        confirm: true,
        return_url: "https://fleaber.pt/",
        payment_method: "pm_card_visa",
        automatic_payment_methods: {
          enabled: true,
          allow_redirects: "never",
        },
        metadata: {
          fleaber_order_id: orderId,
          fleaber_e2e: "fase2_oversell",
          fleaber_tag: tag,
          product_id: productId,
        },
      });
      if (pi.status !== "succeeded") {
        throw new Error(`PI ${tag} status=${pi.status}`);
      }
      await sb.from("orders").update({
        stripe_payment_intent_id: pi.id,
        price_total: serverAmount / 100,
      }).eq("id", orderId);
      return {
        id: pi.id,
        status: pi.status,
        amount: pi.amount,
        amount_received: pi.amount_received,
        currency: pi.currency,
      };
    }

    async function settle(orderId: string, paymentIntentId: string) {
      const res = await fetch(settleUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          order_id: orderId,
          payment_intent_id: paymentIntentId,
          product_id: productId,
        }),
      });
      const text = await res.text();
      let parsed: unknown = text;
      try {
        parsed = JSON.parse(text);
      } catch (_) {
        /* keep text */
      }
      return { http: res.status, body: parsed };
    }

    // Ambos os PIs criados/pagos ENQUANTO stock ainda é 1 (antes do settle).
    const piA = await payPi(orderA, "winner");
    const piB = await payPi(orderB, "loser");
    evidence.winner_pi = piA;
    evidence.loser_pi = piB;
    evidence.stock_before_settle = (
      await sb.from("products").select("quantity").eq("id", productId)
        .maybeSingle()
    ).data?.quantity;

    const settleA = await settle(orderA, piA.id);
    evidence.settle_a = settleA;

    const { data: oa } = await sb.from("orders").select(
      "id, status, stock_units_applied, stripe_refund_id, stripe_payment_intent_id, price_total",
    ).eq("id", orderA).maybeSingle();
    const { data: stockAfterA } = await sb.from("products").select(
      "quantity, is_sold",
    ).eq("id", productId).maybeSingle();
    evidence.order_a_after = oa;
    evidence.stock_after_winner = stockAfterA;

    if (String(oa?.status).toLowerCase() !== "pago") {
      throw new Error(`vencedor não pago: ${JSON.stringify(settleA).slice(0, 300)}`);
    }

    const settleB = await settle(orderB, piB.id);
    evidence.settle_b = settleB;

    const { data: ob } = await sb.from("orders").select(
      "id, status, stock_units_applied, stripe_refund_id, stripe_refunded_at, stripe_payment_intent_id, price_total",
    ).eq("id", orderB).maybeSingle();
    evidence.order_b_after = ob;

    const refundId = String(ob?.stripe_refund_id ?? "");
    if (!refundId.startsWith("re_")) {
      throw new Error(
        `sem refund na order B: ${JSON.stringify({ ob, settleB }).slice(0, 500)}`,
      );
    }

    const refund = await stripe.refunds.retrieve(refundId);
    evidence.refund = {
      id: refund.id,
      status: refund.status,
      amount: refund.amount,
      currency: refund.currency,
      payment_intent: refund.payment_intent,
      metadata: refund.metadata,
    };

    // Retry settle (idempotência)
    const settleB2 = await settle(orderB, piB.id);
    evidence.settle_b_retry = settleB2;
    const { data: ob2 } = await sb.from("orders").select(
      "status, stripe_refund_id, stock_units_applied",
    ).eq("id", orderB).maybeSingle();
    evidence.order_b_after_retry = ob2;

    const refundList = await stripe.refunds.list({
      payment_intent: piB.id,
      limit: 5,
    });
    evidence.refunds_on_pi = refundList.data.map((r) => ({
      id: r.id,
      amount: r.amount,
      status: r.status,
    }));

    const { data: stockFinal } = await sb.from("products").select(
      "quantity, is_sold",
    ).eq("id", productId).maybeSingle();
    const { data: walletAfter } = await sb.from("wallets").select("balance")
      .eq("id", sellerId).maybeSingle();
    evidence.stock_final = stockFinal;
    evidence.seller_wallet_after = walletAfter?.balance ?? null;

    const { data: events } = await sb.from("stripe_checkout_events")
      .select("event, created_at")
      .eq("order_id", orderB)
      .order("created_at", { ascending: false })
      .limit(8);
    evidence.order_b_events = events;

    const checks = {
      both_pi_paid_before_settle: piA.status === "succeeded" &&
        piB.status === "succeeded",
      stock_was_1_before_settle: Number(evidence.stock_before_settle) === 1,
      winner_order_pago: String(oa?.status).toLowerCase() === "pago",
      winner_stock_consumed: Number(stockAfterA?.quantity) === 0,
      loser_not_pago: String(ob?.status).toLowerCase() !== "pago",
      loser_cancelado: String(ob?.status).toLowerCase() === "cancelado",
      refund_created: refund.id.startsWith("re_"),
      refund_status_ok: refund.status === "succeeded" ||
        refund.status === "pending",
      refund_amount_ok: refund.amount === serverAmount,
      refund_pi_matches: String(refund.payment_intent) === piB.id,
      refund_id_on_order: ob?.stripe_refund_id === refund.id,
      stock_final_zero: Number(stockFinal?.quantity) === 0,
      loser_no_claim: ob?.stock_units_applied == null,
      seller_wallet_unchanged: String(walletBefore?.balance ?? "") ===
        String(walletAfter?.balance ?? ""),
      retry_same_refund: ob2?.stripe_refund_id === refund.id,
      single_refund_on_pi: refundList.data.length === 1 &&
        refundList.data[0]?.id === refund.id,
      settle_b_oversell: (settleB.body as { settleResult?: string })
        ?.settleResult === "oversell_refunded" ||
        String(ob?.status).toLowerCase() === "cancelado",
      idempotency_key: `fleaber_oversell_refund_${orderB}`,
    };

    const failed = Object.entries(checks)
      .filter(([k, v]) => k !== "idempotency_key" && v !== true)
      .map(([k]) => k);

    evidence.checks = checks;
    evidence.failed_checks = failed;
    evidence.ok = failed.length === 0;
    evidence.server_amount_cents = serverAmount;

    if (failed.length === 0) {
      await sb.from("orders").delete().eq("product_id", productId);
      await sb.from("products").delete().eq("id", productId);
      evidence.cleaned = true;
    } else {
      evidence.cleaned = false;
    }

    return json(evidence, failed.length === 0 ? 200 : 500);
  } catch (e) {
    evidence.ok = false;
    evidence.error = e instanceof Error ? e.message : String(e);
    return json(evidence, 500);
  }
});
