import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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
  bag_checkout?: boolean;
  bag_lines?: BagCheckoutLine[];
};

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

async function settlePaidBagOrders(
  supabase: ReturnType<typeof createClient>,
  lines: BagCheckoutLine[],
  buyerId: string,
  sellerId: string,
  liveIdMeta: string,
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

    const { error: orderUpdateError } = await supabase
      .from("orders")
      .update(orderPatch)
      .eq("id", orderId);
    if (orderUpdateError) throw orderUpdateError;

    await supabase
      .from("products")
      .update({ is_sold: true, list_on_marketplace: false })
      .eq("id", productId);

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
  return `intent://${deepLinkPath}#Intent;scheme=fleaber;package=com.mycompany.fleaber;S.browser_fallback_url=${fallback};end`;
}

Deno.serve(async (req) => {
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

          if (isBagPaid && buyerId && sellerId) {
            await settlePaidBagOrders(
              supabase,
              bagLines,
              buyerId,
              sellerId,
              liveIdMeta,
            );
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

            const { error: orderUpdateError } = await supabase
              .from("orders")
              .update(orderPatch)
              .eq("id", orderId);
            if (orderUpdateError) {
              throw orderUpdateError;
            }

            const { error: productUpdateError } = await supabase
              .from("products")
              .update({ is_sold: true, list_on_marketplace: false })
              .eq("id", productId);
            if (productUpdateError) {
              throw productUpdateError;
            }

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
              product_data: { name: "Compra Fleaber" },
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
