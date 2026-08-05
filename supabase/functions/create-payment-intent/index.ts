import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type BagCheckoutLine = {
  order_id?: string;
  product_id?: string;
  seller_id?: string;
  quantity?: number;
  line_total_cents?: number;
  live_item_id?: string;
  reservation_request_id?: string;
  item_label?: string;
};

type PaymentIntentRequest = {
  amount?: number;
  currency?: string;
  product_id?: string;
  buyer_id?: string;
  seller_id?: string;
  order_id?: string;
  item_price?: number;
  shipping?: number;
  protection_fee?: number;
  shipping_method?: string;
  live_id?: string;
  playback_id?: string;
  is_live?: boolean;
  live_seller_id?: string;
  live_item_id?: string;
  reservation_request_id?: string;
  prize_shipping?: boolean;
  bag_checkout?: boolean;
  bag_lines?: BagCheckoutLine[];
};

async function unitPriceEurForCheckout(
  admin: ReturnType<typeof createClient>,
  liveItemId?: string,
  productId?: string,
): Promise<number> {
  let unit = 0;
  const liid = liveItemId?.trim() ?? "";
  const pid = productId?.trim() ?? "";
  if (liid.length > 0) {
    const { data, error } = await admin
      .from("live_items")
      .select("price")
      .eq("id", liid)
      .maybeSingle();
    if (!error && data?.price != null) {
      unit = Number(data.price);
    }
  }
  if (unit <= 0 && pid.length > 0) {
    const { data, error } = await admin
      .from("products")
      .select("price")
      .eq("id", pid)
      .maybeSingle();
    if (!error && data?.price != null) {
      unit = Number(data.price);
    }
  }
  return unit;
}

async function assertCheckoutPricesPositive(
  admin: ReturnType<typeof createClient>,
  body: PaymentIntentRequest,
  isBagCheckout: boolean,
  bagLines: BagCheckoutLine[],
): Promise<void> {
  // Prémio da Rifa: só portes (+ seguro). item_price pode ser 0.
  if (body.prize_shipping === true) {
    const shipping = Number(body.shipping ?? 0);
    const amount = Number(body.amount ?? 0);
    if (!Number.isInteger(shipping) || shipping < 50) {
      throw new Error("Invalid prize shipping amount.");
    }
    if (!Number.isInteger(amount) || amount < 50) {
      throw new Error("Invalid payment amount.");
    }
    return;
  }

  if (isBagCheckout) {
    for (const line of bagLines) {
      const unit = await unitPriceEurForCheckout(
        admin,
        line.live_item_id,
        line.product_id,
      );
      if (!Number.isFinite(unit) || unit <= 0) {
        throw new Error("Checkout blocked: item without price.");
      }
      const cents = Number(line.line_total_cents ?? 0);
      if (!Number.isInteger(cents) || cents < 50) {
        throw new Error("Invalid line amount.");
      }
    }
    return;
  }

  const unit = await unitPriceEurForCheckout(
    admin,
    body.live_item_id,
    body.product_id,
  );
  if (!Number.isFinite(unit) || unit <= 0) {
    throw new Error("Checkout blocked: item without price.");
  }
}

/**
 * SEC-006 parcial (BATATA): compara amount do cliente com price_total na BD.
 * Só regista aviso — NUNCA rejeita o checkout (portes/taxas/descontos podem divergir).
 */
async function observeCheckoutAmountVsDb(
  admin: ReturnType<typeof createClient>,
  opts: {
    orderId?: string;
    bagLines: BagCheckoutLine[];
    isBagCheckout: boolean;
    amountCents: number;
    buyerId?: string;
  },
): Promise<void> {
  try {
    const orderIds: string[] = [];
    if (opts.isBagCheckout) {
      for (const line of opts.bagLines) {
        const id = line.order_id?.trim() ?? "";
        if (id) orderIds.push(id);
      }
    } else {
      const id = opts.orderId?.trim() ?? "";
      if (id) orderIds.push(id);
    }
    if (orderIds.length === 0) return;

    const { data: rows, error } = await admin
      .from("orders")
      .select("id, price_total")
      .in("id", orderIds);
    if (error || !rows?.length) return;

    let dbCents = 0;
    for (const row of rows) {
      const eur = Number(row.price_total ?? 0);
      if (Number.isFinite(eur) && eur > 0) {
        dbCents += Math.round(eur * 100);
      }
    }
    if (dbCents <= 0) return;

    const delta = opts.amountCents - dbCents;
    // Só log se divergência > 2 € (evita ruído de arredondamento)
    if (Math.abs(delta) <= 200) return;

    console.warn("SEC-006 amount observe", {
      order_ids: orderIds,
      amount_cents: opts.amountCents,
      db_cents: dbCents,
      delta_cents: delta,
      buyer_id: opts.buyerId ?? null,
    });

    await admin.from("stripe_checkout_events").insert({
      session_id: null,
      order_id: orderIds[0] ?? null,
      event: "sec006_amount_observe",
      detail: JSON.stringify({
        order_ids: orderIds,
        amount_cents: opts.amountCents,
        db_price_total_cents: dbCents,
        delta_cents: delta,
        bag: opts.isBagCheckout,
      }),
    });
  } catch (e) {
    console.warn("SEC-006 observe failed (ignored)", e);
  }
}

function parseBagCheckoutLines(
  sessionMetadata: Record<string, string> | null | undefined,
): BagCheckoutLine[] {
  const meta = sessionMetadata ?? {};
  const legacyJson = meta.bag_orders_json?.trim() ?? "";
  if (legacyJson.length > 0) {
    try {
      const parsed = JSON.parse(legacyJson) as BagCheckoutLine[];
      if (Array.isArray(parsed) && parsed.length > 0) return parsed;
    } catch (_) {
      /* fallback compact keys */
    }
  }

  const orderIds = (meta.bag_order_ids ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  if (orderIds.length === 0) return [];

  const itemIds = (meta.bag_live_item_ids ?? "")
    .split(",")
    .map((s) => s.trim());
  const requestIds = (meta.bag_request_ids ?? "")
    .split(",")
    .map((s) => s.trim());
  const productIds = (meta.bag_product_ids ?? "")
    .split(",")
    .map((s) => s.trim());

  return orderIds.map((orderId, i) => ({
    order_id: orderId,
    product_id: productIds[i] ?? "",
    live_item_id: itemIds[i] ?? "",
    reservation_request_id: requestIds[i] ?? "",
  }));
}

function compactBagStripeMetadata(
  bagLines: BagCheckoutLine[],
): Record<string, string> {
  const orderIds: string[] = [];
  const productIds: string[] = [];
  const itemIds: string[] = [];
  const requestIds: string[] = [];
  for (const line of bagLines) {
    const oid = line.order_id?.trim() ?? "";
    if (!oid) continue;
    orderIds.push(oid);
    productIds.push(line.product_id?.trim() ?? "");
    itemIds.push(line.live_item_id?.trim() ?? "");
    requestIds.push(line.reservation_request_id?.trim() ?? "");
  }
  return {
    bag_checkout: "true",
    bag_order_ids: orderIds.join(","),
    bag_product_ids: productIds.join(","),
    bag_live_item_ids: itemIds.join(","),
    bag_request_ids: requestIds.join(","),
  };
}

async function resolveBagLineLabels(
  supabase: ReturnType<typeof createClient>,
  lines: BagCheckoutLine[],
): Promise<string[]> {
  const labels: string[] = [];
  for (const line of lines) {
    const fromMeta = (line.item_label ?? "").trim();
    if (
      fromMeta.length > 0 &&
      fromMeta !== "Artigo" &&
      fromMeta !== "Artigo Fleaber"
    ) {
      labels.push(fromMeta);
      continue;
    }
    const pid = line.product_id?.trim() ?? "";
    if (!pid) {
      labels.push("Artigo");
      continue;
    }
    const { data } = await supabase
      .from("products")
      .select("title")
      .eq("id", pid)
      .maybeSingle();
    const title = (data?.title as string | undefined)?.trim() ?? "";
    labels.push(title.length > 0 ? title : "Artigo");
  }
  return labels;
}

async function sendMarketplaceBagPaidChatMessage(
  supabase: ReturnType<typeof createClient>,
  buyerId: string,
  sellerId: string,
  lines: BagCheckoutLine[],
  totalCents: number,
) {
  if (lines.length === 0) return;
  const firstProductId = lines[0]?.product_id?.trim() ?? "";
  if (!firstProductId) return;

  const labels = await resolveBagLineLabels(supabase, lines);
  const count = lines.length;
  const totalText =
    Number.isFinite(totalCents) && totalCents > 0
      ? ` (${(totalCents / 100).toFixed(2).replace(".", ",")} €)`
      : "";

  let text: string;
  if (count > 1) {
    // Card «Comprado!» injectado no cliente — payload oculto na timeline.
    text = `FLEABER_JSON_V1:${JSON.stringify({
      kind: "marketplace_bag_paid",
      v: 1,
      line_count: count,
      total_cents: totalCents,
      lines: lines.map((l, i) => ({
        product_id: l.product_id,
        item_label: labels[i] ?? "Artigo",
      })),
    })}`;
  } else {
    const label = labels[0] ?? "Artigo";
    text = `Compra paga através do Seguro Fleaber: ${label}${totalText}.`;
  }

  try {
    const { data: existingChat } = await supabase
      .from("chats")
      .select("id")
      .eq("product_id", firstProductId)
      .or(
        `and(user_a.eq.${buyerId},user_b.eq.${sellerId}),and(user_a.eq.${sellerId},user_b.eq.${buyerId})`,
      )
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    let chatId = existingChat?.id as string | undefined;
    if (!chatId) {
      const { data: newChat } = await supabase
        .from("chats")
        .insert({ user_a: buyerId, user_b: sellerId, product_id: firstProductId })
        .select("id")
        .single();
      chatId = newChat?.id;
    }

    if (!chatId) return;

    const { data: existingPlain } = await supabase
      .from("chat_messages")
      .select("id")
      .eq("chat_id", chatId)
      .like("text", "Compra%conjunto paga através do Seguro Fleaber%")
      .limit(1)
      .maybeSingle();
    const { data: existingJson } = await supabase
      .from("chat_messages")
      .select("id")
      .eq("chat_id", chatId)
      .like("text", "FLEABER_JSON_V1:%marketplace_bag_paid%")
      .limit(1)
      .maybeSingle();
    const existingMessage = existingPlain ?? existingJson;

    if (!existingMessage) {
      await supabase.from("chat_messages").insert({
        sender_id: buyerId,
        receiver_id: sellerId,
        chat_id: chatId,
        text,
        is_read: false,
        is_reservation: false,
      });
    }

    await supabase
      .from("chats")
      .update({
        last_message: "Compra paga pelo Seguro Fleaber",
        last_message_time: new Date().toISOString(),
      })
      .eq("id", chatId);
  } catch (chatError) {
    console.error("Fleaber bag chat update failed", chatError);
  }
}

function stripeIdsFromSession(session: {
  id?: string;
  payment_intent?: string | { id?: string } | null;
}): { sessionId: string; paymentIntentId: string } {
  const sessionId = (session.id ?? "").trim();
  const pi = session.payment_intent;
  const paymentIntentId = typeof pi === "string"
    ? pi.trim()
    : (pi?.id ?? "").trim();
  return { sessionId, paymentIntentId };
}

async function settlePaidBagOrders(
  supabase: ReturnType<typeof createClient>,
  lines: BagCheckoutLine[],
  buyerId: string,
  sellerId: string,
  liveIdMeta: string,
  stripeIds?: { sessionId: string; paymentIntentId: string },
) {
  for (const line of lines) {
    const orderId = line.order_id?.trim() ?? "";
    if (!orderId) continue;

    let productId = line.product_id?.trim() ?? "";
    if (!productId) {
      const { data: orderRow } = await supabase
        .from("orders")
        .select("product_id")
        .eq("id", orderId)
        .maybeSingle();
      productId = (orderRow?.product_id as string | undefined)?.trim() ?? "";
    }
    if (!productId) continue;

    const orderPatch: Record<string, unknown> = {
      status: "pago",
      is_reservation: false,
    };
    if (liveIdMeta.length > 0) orderPatch.live_id = liveIdMeta;
    const liveItemId = line.live_item_id?.trim() ?? "";
    if (liveItemId.length > 0) orderPatch.live_item_id = liveItemId;
    if (stripeIds?.sessionId) {
      orderPatch.stripe_checkout_session_id = stripeIds.sessionId;
    }
    if (stripeIds?.paymentIntentId) {
      orderPatch.stripe_payment_intent_id = stripeIds.paymentIntentId;
    }

    // BUG-QA-021: rasto do stock (o decremento é feito pelo trigger ao ficar «pago»).
    const { data: beforeRow } = await supabase
      .from("products")
      .select("quantity, is_sold, list_on_marketplace")
      .eq("id", productId)
      .maybeSingle();

    const { error: orderUpdateError } = await supabase
      .from("orders")
      .update(orderPatch)
      .eq("id", orderId);
    if (orderUpdateError) throw orderUpdateError;

    // BUG-QA-016: o stock (quantity/is_sold) é tratado pelo trigger
    // batata_mark_product_sold_on_paid_order ao ficar «pago». Não atualizamos
    // products aqui para não decrementar duas vezes.
    const { data: afterRow } = await supabase
      .from("products")
      .select("quantity, is_sold, list_on_marketplace")
      .eq("id", productId)
      .maybeSingle();
    console.log(
      `BATATA_STOCK bag order=${orderId} product=${productId} ` +
        `qty_before=${beforeRow?.quantity ?? "?"} qty_after=${afterRow?.quantity ?? "?"} ` +
        `is_sold=${afterRow?.is_sold ?? "?"} list=${afterRow?.list_on_marketplace ?? "?"}`,
    );

    const requestId = line.reservation_request_id?.trim() ?? "";
    if (requestId.length > 0) {
      const { data: convertRes, error: convertErr } = await supabase.rpc(
        "batata_live_reservation_stripe_convert",
        { p_request_id: requestId, p_order_id: orderId },
      );
      if (convertErr) console.error("bag convert", convertErr);
      const ok =
        !convertErr &&
        convertRes &&
        typeof convertRes === "object" &&
        (convertRes as { ok?: boolean }).ok === true;
      if (!ok) {
        await supabase.rpc("batata_live_reconcile_stripe_order", {
          p_order_id: orderId,
          p_reservation_request_id: requestId,
        });
      }
    } else {
      await supabase.rpc("batata_live_reconcile_stripe_order", {
        p_order_id: orderId,
        p_reservation_request_id: null,
      });
    }
  }

  if (liveIdMeta.length > 0 && buyerId) {
    const firstItem = lines.find((l) => (l.live_item_id ?? "").trim().length > 0);
    const broadcastItemId = firstItem?.live_item_id?.trim() ?? "";
    if (broadcastItemId.length > 0) {
      try {
        await supabase.rpc("batata_live_purchase_broadcast", {
          p_live_id: liveIdMeta,
          p_buyer_id: buyerId,
          p_live_item_id: broadcastItemId,
        });
      } catch (broadcastError) {
        console.error("Fleaber live purchase broadcast failed", broadcastError);
      }
    }
  }
}

async function resolveStripeBagRequestId(
  supabase: ReturnType<typeof createClient>,
  options: {
    liveId: string;
    buyerId: string;
    itemIds: string[];
    orderId: string;
    reservationRequestId?: string;
  },
): Promise<string | null> {
  const reservationRequestId = options.reservationRequestId?.trim() ?? "";
  if (reservationRequestId.length > 0) {
    return reservationRequestId;
  }

  const orderTag = `stripe_checkout:${options.orderId}`;
  const { data: byOrder } = await supabase
    .from("live_reservation_requests")
    .select("id")
    .eq("live_id", options.liveId)
    .eq("buyer_id", options.buyerId)
    .eq("source", "fleaber_live")
    .in("status", ["pending", "accepted"])
    .in("live_item_id", options.itemIds)
    .ilike("notes", `%${orderTag}%`)
    .order("queue_position", { ascending: true })
    .limit(1);
  const linked = (byOrder?.[0]?.id as string | undefined)?.trim() ?? "";
  if (linked.length > 0) return linked;

  const { data: pick } = await supabase
    .from("live_reservation_requests")
    .select("id")
    .eq("live_id", options.liveId)
    .eq("buyer_id", options.buyerId)
    .eq("source", "fleaber_live")
    .in("status", ["pending", "accepted"])
    .in("live_item_id", options.itemIds)
    .order("queue_position", { ascending: true })
    .limit(1);
  return ((pick?.[0]?.id as string | undefined)?.trim() ?? "") || null;
}

function htmlResponse(
  title: string,
  message: string,
  options?: { appUrl?: string; status?: number; autoOpenApp?: boolean },
) {
  const appUrl = options?.appUrl ?? "fleaber://fleaber.com/";
  const safeTitle = title.replace(/[<>&"]/g, "");
  const safeMessage = message.replace(/[<>&"]/g, "");
  const safeAppUrl = appUrl.replace(/"/g, "%22");
  const autoOpenScript = options?.autoOpenApp === true
    ? `<script>window.setTimeout(function(){ window.location.href = "${safeAppUrl}"; }, 250);</script>`
    : "";

  return new Response(`<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Fleaber</title>
    ${autoOpenScript}
  </head>
  <body style="margin:0;background:#F1F4F8;font-family:Arial,sans-serif;color:#101518;">
    <div style="min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;box-sizing:border-box;">
      <div style="width:100%;max-width:420px;background:#fff;border-radius:18px;padding:24px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,.08);">
        <h1 style="margin:0 0 10px;color:#007782;font-size:28px;">${safeTitle}</h1>
        <p style="margin:0 0 18px;line-height:1.45;color:#57636C;">${safeMessage}</p>
        <a href="${safeAppUrl}" style="display:block;background:#007782;color:white;text-decoration:none;padding:14px 16px;border-radius:12px;font-weight:700;">Voltar à app Fleaber</a>
        <p style="margin:14px 0 0;color:#7A858C;font-size:12px;">Se a app não abrir, volta manualmente à Fleaber.</p>
      </div>
    </div>
  </body>
</html>`, {
    status: options?.status ?? 200,
    headers: {
      ...corsHeaders,
      "Content-Type": "text/html; charset=UTF-8",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "no-store",
    },
  });
}

function textResponse(message: string, status = 200) {
  return new Response(message, {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function intentRedirectResponse(appUrl: string) {
  return new Response(null, {
    status: 303,
    headers: {
      ...corsHeaders,
      "Location": appUrl,
      "Cache-Control": "no-store",
    },
  });
}

async function logStripeCheckoutEvent(
  supabase: ReturnType<typeof createClient>,
  event: string,
  detail: Record<string, unknown>,
) {
  try {
    await supabase.from("stripe_checkout_events").insert({
      session_id: (detail.session_id as string | undefined) ?? null,
      order_id: (detail.order_id as string | undefined) ?? null,
      product_id: (detail.product_id as string | undefined) ?? null,
      live_id: (detail.live_id as string | undefined) ?? null,
      buyer_id: (detail.buyer_id as string | undefined) ?? null,
      event,
      detail,
    });
  } catch (e) {
    console.error("stripe_checkout_events insert failed", e);
  }
}

function stripeReturnQuery(
  sessionId: string,
  options?: {
    productId?: string;
    orderId?: string;
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
) {
  const params = new URLSearchParams({ session_id: sessionId });
  if (options?.productId) {
    params.set("product_id", options.productId);
  }
  if (options?.orderId) {
    params.set("order_id", options.orderId);
  }
  if (options?.liveId) {
    params.set("liveId", options.liveId);
    params.set("live_id", options.liveId);
  }
  if (options?.playbackId) {
    params.set("playbackId", options.playbackId);
  }
  if (options?.isLive) {
    params.set("isLive", options.isLive);
  }
  if (options?.sellerId) {
    params.set("sellerId", options.sellerId);
  }
  return params;
}

function fleaberDeepLinkUrl(
  sessionId: string,
  options?: {
    productId?: string;
    orderId?: string;
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
) {
  const q = stripeReturnQuery(sessionId, options).toString();
  return `fleaber://fleaber.com/stripe-success?${q}`;
}

function androidIntentUrl(
  sessionId: string,
  options?: {
    productId?: string;
    orderId?: string;
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
) {
  const deepLinkPath = `fleaber.com/stripe-success?${stripeReturnQuery(sessionId, options).toString()}`;
  const fallback = encodeURIComponent("https://fleaber.app");
  return `intent://${deepLinkPath}#Intent;scheme=fleaber;package=pt.fleaber.app;S.browser_fallback_url=${fallback};end`;
}

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!stripeSecretKey) {
      throw new Error("STRIPE_SECRET_KEY is not configured.");
    }
    if (!supabaseUrl) {
      throw new Error("SUPABASE_URL is not configured.");
    }

    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2024-06-20",
      httpClient: Stripe.createFetchHttpClient(),
    });

    if (req.method === "GET") {
      const url = new URL(req.url);
      const sessionId = url.searchParams.get("session_id");
      const deepLinkUrl =
        sessionId != null
          ? `fleaber://fleaber.com/stripe-success?session_id=${encodeURIComponent(sessionId)}`
          : "fleaber://fleaber.com/";
      const appUrl = sessionId != null ? androidIntentUrl(sessionId) : deepLinkUrl;
      if (!sessionId) {
        return textResponse("Sessão Stripe em falta.", 400);
      }

      // SEC-018b / SEC-005 residual: anti-spam settle via return URL — fail-open.
      // Não muda a lógica de marcar pago; só limita martelar session_id.
      if (serviceRoleKey) {
        const supabaseRate = createClient(supabaseUrl, serviceRoleKey);
        const settleRate = await checkAnonRate(
          supabaseRate,
          `checkout_settle:${sessionId.slice(0, 64)}`,
          "create-payment-intent-get",
          30,
        );
        if (settleRate.rateLimited) {
          return textResponse(
            "Demasiados pedidos. Volta à app Fleaber e espera um momento.",
            429,
          );
        }
      }

      const session = await stripe.checkout.sessions.retrieve(sessionId);
      const productId = session.metadata?.product_id;
      const orderId = session.metadata?.order_id;
      const liveId = session.metadata?.live_id;
      const playbackId = session.metadata?.playback_id;
      const isLive = session.metadata?.is_live;
      const liveSellerId = session.metadata?.live_seller_id;
      const returnOptions = {
        productId,
        orderId,
        liveId,
        playbackId,
        isLive,
        sellerId: liveSellerId,
      };
      const successfulAppUrl = fleaberDeepLinkUrl(sessionId, returnOptions);
      let updateError = "";
      if (
        url.searchParams.get("checkout_return") === "success" &&
        session.payment_status === "paid"
      ) {
        try {
          if (!serviceRoleKey) {
            throw new Error("Supabase service role is not configured.");
          }
          const supabase = createClient(supabaseUrl, serviceRoleKey);
          const buyerId = session.metadata?.buyer_id;
          const sellerId = session.metadata?.seller_id;
          const total = Number(session.metadata?.total ?? 0);

          const liveIdMeta = session.metadata?.live_id?.trim() ?? "";
          const bagLines = parseBagCheckoutLines(session.metadata);
          const isBagPaid =
            session.metadata?.bag_checkout === "true" && bagLines.length > 0;
          const stripeIds = stripeIdsFromSession(session);

          if (isBagPaid && buyerId && sellerId) {
            await settlePaidBagOrders(
              supabase,
              bagLines,
              buyerId,
              sellerId,
              liveIdMeta,
              stripeIds,
            );
            if (liveIdMeta.length === 0) {
              await sendMarketplaceBagPaidChatMessage(
                supabase,
                buyerId,
                sellerId,
                bagLines,
                Number(session.metadata?.total ?? 0),
              );
            }
          } else if (orderId && productId && buyerId && sellerId) {
            const orderPatch: Record<string, unknown> = {
              status: "pago",
              is_reservation: false,
            };
            const liveItemIdMeta = session.metadata?.live_item_id?.trim() ?? "";
            if (liveIdMeta.length > 0) orderPatch.live_id = liveIdMeta;
            if (liveItemIdMeta.length > 0) {
              orderPatch.live_item_id = liveItemIdMeta;
            }
            if (stripeIds.sessionId) {
              orderPatch.stripe_checkout_session_id = stripeIds.sessionId;
            }
            if (stripeIds.paymentIntentId) {
              orderPatch.stripe_payment_intent_id = stripeIds.paymentIntentId;
            }

            const { error: orderUpdateError } = await supabase
              .from("orders")
              .update(orderPatch)
              .eq("id", orderId);
            if (orderUpdateError) {
              throw orderUpdateError;
            }

            // BUG-QA-016: stock (quantity/is_sold) tratado pelo trigger
            // batata_mark_product_sold_on_paid_order ao ficar «pago».
            // Evita duplo decremento — não atualizar products aqui.

            try {
              const { data: existingChat } = await supabase
                .from("chats")
                .select("id")
                .eq("product_id", productId)
                .or(
                  `and(user_a.eq.${buyerId},user_b.eq.${sellerId}),and(user_a.eq.${sellerId},user_b.eq.${buyerId})`,
                )
                .order("created_at", { ascending: false })
                .limit(1)
                .maybeSingle();

              let chatId = existingChat?.id as string | undefined;
              if (!chatId) {
                const { data: newChat } = await supabase
                  .from("chats")
                  .insert({ user_a: buyerId, user_b: sellerId, product_id: productId })
                  .select("id")
                  .single();
                chatId = newChat?.id;
              }

              if (chatId) {
                const amountText =
                  Number.isFinite(total) && total > 0
                    ? ` (${(total / 100).toFixed(2).replace(".", ",")} €)`
                    : "";
                const text = `Compra paga através do Seguro Fleaber${amountText}.`;

                const { data: existingMessage } = await supabase
                  .from("chat_messages")
                  .select("id")
                  .eq("chat_id", chatId)
                  .like("text", "Compra paga através do Seguro Fleaber%")
                  .limit(1)
                  .maybeSingle();

                if (!existingMessage) {
                  await supabase.from("chat_messages").insert({
                    sender_id: buyerId,
                    receiver_id: sellerId,
                    chat_id: chatId,
                    text,
                    is_read: false,
                    is_reservation: false,
                  });
                }

                await supabase
                  .from("chats")
                  .update({
                    last_message: "Compra paga pelo Seguro Fleaber",
                    last_message_time: new Date().toISOString(),
                  })
                  .eq("id", chatId);
              }
            } catch (chatError) {
              console.error("Fleaber chat update failed", chatError);
            }

            // Saco da live: marcar reservas leves como convertidas após pagamento.
            if (liveIdMeta.length > 0 && buyerId) {
              try {
                const itemIds = new Set<string>();
                if (liveItemIdMeta.length > 0) {
                  itemIds.add(liveItemIdMeta);
                }
                if (productId) {
                  const { data: productRow } = await supabase
                    .from("products")
                    .select("ref_code")
                    .eq("id", productId)
                    .maybeSingle();
                  const refCode = (productRow?.ref_code as string | undefined)?.trim() ?? "";
                  if (refCode.length > 0) {
                    const { data: liveItems } = await supabase
                      .from("live_items")
                      .select("id")
                      .eq("live_id", liveIdMeta)
                      .eq("ref_code", refCode);
                    for (const row of liveItems ?? []) {
                      const id = (row.id as string | undefined)?.trim() ?? "";
                      if (id.length > 0) itemIds.add(id);
                    }
                  }
                }
                const ids = [...itemIds];
                if (ids.length > 0) {
                  const reservationRequestIdMeta =
                    session.metadata?.reservation_request_id?.trim() ?? "";
                  const requestId = await resolveStripeBagRequestId(supabase, {
                    liveId: liveIdMeta,
                    buyerId,
                    itemIds: ids,
                    orderId: orderId ?? "",
                    reservationRequestId: reservationRequestIdMeta,
                  });

                  let convertedItemId = liveItemIdMeta;
                  if (requestId) {
                    const { data: convertRes, error: convertErr } =
                      await supabase.rpc("batata_live_reservation_stripe_convert", {
                        p_request_id: requestId,
                        p_order_id: orderId,
                      });
                    if (convertErr) {
                      console.error("stripe convert rpc", convertErr);
                    }
                    const ok =
                      !convertErr &&
                      convertRes &&
                      typeof convertRes === "object" &&
                      (convertRes as { ok?: boolean }).ok === true;
                    if (!ok) {
                      const { error: reconcileErr } = await supabase.rpc(
                        "batata_live_reconcile_stripe_order",
                        {
                          p_order_id: orderId,
                          p_reservation_request_id: requestId,
                        },
                      );
                      if (reconcileErr) {
                        console.error("stripe reconcile fallback", reconcileErr);
                      }
                    }
                    const fromRpc = (convertRes as { live_item_id?: string } | null)
                      ?.live_item_id;
                    if (typeof fromRpc === "string" && fromRpc.trim().length > 0) {
                      convertedItemId = fromRpc.trim();
                    }
                  } else {
                    // Compra directa (sem reserva prévia): registo converted no saco.
                    for (const itemId of ids) {
                      const { data: convertedRows } = await supabase
                        .from("live_reservation_requests")
                        .select("id")
                        .eq("live_id", liveIdMeta)
                        .eq("buyer_id", buyerId)
                        .eq("live_item_id", itemId)
                        .eq("status", "converted")
                        .limit(1);
                      if (!convertedRows || convertedRows.length === 0) {
                        await supabase.from("live_reservation_requests").insert({
                          live_id: liveIdMeta,
                          live_item_id: itemId,
                          seller_id: sellerId,
                          buyer_id: buyerId,
                          requested_qty: 1,
                          source: "fleaber_live",
                          status: "converted",
                          notes: "stripe_paid_direct",
                        });
                      }
                      const { data: stock } = await supabase.rpc(
                        "batata_live_item_stock",
                        { p_live_item_id: itemId },
                      );
                      const avail =
                        stock && typeof stock === "object"
                          ? Number((stock as { available_qty?: number }).available_qty ?? 1)
                          : 1;
                      if (avail <= 0) {
                        await supabase
                          .from("live_items")
                          .update({ status: "sold" })
                          .eq("id", itemId);
                      }
                      try {
                        await supabase.rpc("batata_maybe_fomo_last_unit", {
                          p_live_item_id: itemId,
                        });
                      } catch (fomoError) {
                        console.error(
                          "Fleaber live FOMO last unit failed",
                          fomoError,
                        );
                      }
                    }
                  }

                  const broadcastItemId = convertedItemId.length > 0
                    ? convertedItemId
                    : ids[0];
                  if (broadcastItemId.length > 0) {
                    try {
                      await supabase.rpc("batata_live_purchase_broadcast", {
                        p_live_id: liveIdMeta,
                        p_buyer_id: buyerId,
                        p_live_item_id: broadcastItemId,
                      });
                    } catch (broadcastError) {
                      console.error(
                        "Fleaber live purchase broadcast failed",
                        broadcastError,
                      );
                    }
                  }

                  console.log(
                    JSON.stringify({
                      event: "stripe.live_bag_converted",
                      live_id: liveIdMeta,
                      live_item_ids: ids,
                      reservation_request_id: requestId,
                      order_id: orderId,
                    }),
                  );
                }
              } catch (bagError) {
                console.error("Fleaber live bag convert failed", bagError);
              }
            }
          } else {
            throw new Error("Missing checkout metadata.");
          }
        } catch (error) {
          updateError = error instanceof Error ? error.message : String(error);
        }
      }

      if (url.searchParams.get("checkout_return") === "cancel") {
        console.log(
          JSON.stringify({
            event: "stripe.checkout.cancel",
            session_id: sessionId,
            order_id: orderId,
            live_id: liveId,
          }),
        );
      }

      const paid = session.payment_status === "paid";
      if (serviceRoleKey) {
        const supabaseLog = createClient(supabaseUrl, serviceRoleKey);
        await logStripeCheckoutEvent(supabaseLog, paid ? "checkout.paid" : "checkout.pending", {
          session_id: sessionId,
          order_id: orderId,
          product_id: productId,
          live_id: liveId,
          buyer_id: session.metadata?.buyer_id,
          payment_status: session.payment_status,
          checkout_return: url.searchParams.get("checkout_return"),
          update_error: updateError || null,
          deep_link: successfulAppUrl,
        });
      }
      if (paid && updateError.length === 0) {
        const webAppUrl = (Deno.env.get("FLEABER_WEB_APP_URL") ?? "").trim();
        if (webAppUrl.length > 0) {
          const webReturn = `${webAppUrl.replace(/\/$/, "")}/stripe-success?${stripeReturnQuery(sessionId, returnOptions).toString()}`;
          return new Response(null, {
            status: 303,
            headers: {
              ...corsHeaders,
              "Location": webReturn,
              "Cache-Control": "no-store",
            },
          });
        }
        // Redirect directo (evita Chrome mostrar HTML como texto).
        return intentRedirectResponse(androidIntentUrl(sessionId, returnOptions));
      }
      if (paid && updateError.length > 0) {
        return textResponse(
          `PAGAMENTO RECEBIDO\n\nErro ao atualizar a encomenda:\n${updateError}\n\nVolta à app Fleaber. Se o artigo não ficar vendido, envia este texto.`,
        );
      }
      return textResponse(
        "Pagamento ainda não confirmado. Se já pagaste, aguarda alguns segundos e volta à app Fleaber.",
      );
    }

    const body = (await req.json()) as PaymentIntentRequest;
    const currency = (body.currency ?? "eur").toLowerCase();
    const bagLines = Array.isArray(body.bag_lines) ? body.bag_lines : [];
    const isBagCheckout = body.bag_checkout === true && bagLines.length > 0;

    let amount = Number(body.amount);
    if (isBagCheckout) {
      amount =
        bagLines.reduce(
          (sum, line) => sum + Number(line.line_total_cents ?? 0),
          0,
        ) + Number(body.shipping ?? 0);
    }

    if (!Number.isInteger(amount) || amount < 50) {
      throw new Error("Invalid payment amount.");
    }
    if (!body.product_id || !body.buyer_id || !body.seller_id || !body.order_id) {
      throw new Error("Missing payment metadata.");
    }
    if (!serviceRoleKey) {
      throw new Error("Supabase service role is not configured.");
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("Missing authorization.");
    }
    const supabaseForAuth = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await supabaseForAuth.auth.getUser();
    if (userError || !user || user.id !== body.buyer_id) {
      throw new Error("Invalid checkout user.");
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    // SEC-006c: anti-spam só — fail-open. 60/h >> uso real (não bloqueia checkout normal).
    const checkoutBurst = await checkAnonRate(
      supabaseAdmin,
      `create_payment_intent:${user.id}`,
      "create-payment-intent-post",
      60,
    );
    if (checkoutBurst.rateLimited) {
      return new Response(
        JSON.stringify({ error: "Demasiados checkouts. Tenta daqui a pouco." }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    await assertCheckoutPricesPositive(
      supabaseAdmin,
      body,
      isBagCheckout,
      bagLines,
    );

    await observeCheckoutAmountVsDb(supabaseAdmin, {
      orderId: body.order_id,
      bagLines,
      isBagCheckout,
      amountCents: amount,
      buyerId: body.buyer_id,
    });

    const functionUrl = `${supabaseUrl}/functions/v1/create-payment-intent`;

    const lineItems = isBagCheckout
      ? [
          ...bagLines.map((line) => ({
            price_data: {
              currency,
              product_data: {
                name: (line.item_label ?? "Artigo Fleaber").slice(0, 120),
              },
              unit_amount: Number(line.line_total_cents ?? 0),
            },
            quantity: 1,
          })),
          ...(Number(body.shipping ?? 0) > 0
            ? [{
                price_data: {
                  currency,
                  product_data: { name: "Envio" },
                  unit_amount: Number(body.shipping),
                },
                quantity: 1,
              }]
            : []),
        ]
      : [
          {
            price_data: {
              currency,
              product_data: {
                name: body.prize_shipping === true
                  ? "Envio — Prémio da Rifa"
                  : "Compra Fleaber",
              },
              unit_amount: amount,
            },
            quantity: 1,
          },
        ];

    const metadata: Record<string, string> = {
      product_id: body.product_id,
      buyer_id: body.buyer_id,
      seller_id: body.seller_id,
      order_id: body.order_id,
      total: String(amount),
      item_price: String(body.item_price ?? ""),
      shipping: String(body.shipping ?? ""),
      protection_fee: String(body.protection_fee ?? ""),
      shipping_method: body.shipping_method ?? "",
      live_id: body.live_id ?? "",
      playback_id: body.playback_id ?? "",
      is_live: body.is_live == null ? "" : String(body.is_live),
      live_seller_id: body.live_seller_id ?? "",
      live_item_id: body.live_item_id ?? "",
      reservation_request_id: body.reservation_request_id ?? "",
      prize_shipping: body.prize_shipping === true ? "1" : "",
    };
    if (isBagCheckout) {
      Object.assign(metadata, compactBagStripeMetadata(bagLines));
    }

    const checkoutSession = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      success_url:
        `${functionUrl}?checkout_return=success&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url:
        `${functionUrl}?checkout_return=cancel&session_id={CHECKOUT_SESSION_ID}`,
      line_items: lineItems,
      metadata,
    });

    return new Response(
      JSON.stringify({
        checkoutUrl: checkoutSession.url,
        checkoutSessionId: checkoutSession.id,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : String(error),
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      },
    );
  }
});
