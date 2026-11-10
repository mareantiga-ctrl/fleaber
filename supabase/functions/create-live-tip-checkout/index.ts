import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { sanitizeWebReturnOrigin } from "../_shared/web_return.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type LiveTipCheckoutRequest = {
  tip_id?: string;
  live_id?: string;
  seller_id?: string;
  amount_eur?: number;
  message?: string;
  playback_id?: string;
  is_live?: boolean;
  web_return_origin?: string;
};

function stripeReturnQuery(
  sessionId: string,
  options: {
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
) {
  const params = new URLSearchParams({ session_id: sessionId });
  if (options.liveId) {
    params.set("liveId", options.liveId);
    params.set("live_id", options.liveId);
  }
  if (options.playbackId) params.set("playbackId", options.playbackId);
  if (options.isLive) params.set("isLive", options.isLive);
  if (options.sellerId) params.set("sellerId", options.sellerId);
  return params;
}

function fleaberDeepLinkUrl(
  sessionId: string,
  options: {
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
) {
  return `fleaber://fleaber.com/stripe-success?${stripeReturnQuery(sessionId, options).toString()}`;
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

async function logStripeCheckoutEvent(
  supabase: ReturnType<typeof createClient>,
  event: string,
  detail: Record<string, unknown>,
) {
  try {
    await supabase.from("stripe_checkout_events").insert({
      session_id: (detail.session_id as string | undefined) ?? null,
      order_id: null,
      product_id: null,
      live_id: (detail.live_id as string | undefined) ?? null,
      buyer_id: (detail.buyer_id as string | undefined) ?? null,
      event,
      detail,
    });
  } catch (e) {
    console.error("stripe_checkout_events insert failed", e);
  }
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

function isMobileUserAgent(ua: string): boolean {
  return /Android|iPhone|iPad|iPod/i.test(ua);
}

function htmlResponse(
  title: string,
  message: string,
  options?: { appUrl?: string; status?: number; autoOpenApp?: boolean },
) {
  const appUrl = options?.appUrl ?? "fleaber://fleaber.com/";
  const esc = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  const safeTitle = esc(title);
  const safeMessage = esc(message);
  const safeAppUrl = appUrl.replace(/"/g, "%22");
  const autoOpenScript = options?.autoOpenApp === true
    ? `<script>window.setTimeout(function(){ window.location.href = "${safeAppUrl}"; }, 250);</script>`
    : "";

  const html =
    `<!DOCTYPE html><html lang="pt"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Fleaber</title>${autoOpenScript}</head>` +
    `<body style="margin:0;background:#F1F4F8;font-family:Arial,sans-serif;color:#101518;">` +
    `<div style="min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;box-sizing:border-box;">` +
    `<div style="width:100%;max-width:420px;background:#fff;border-radius:18px;padding:24px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,.08);">` +
    `<h1 style="margin:0 0 10px;color:#007782;font-size:28px;">${safeTitle}</h1>` +
    `<p style="margin:0 0 18px;line-height:1.45;color:#57636C;">${safeMessage}</p>` +
    `<a href="${safeAppUrl}" style="display:block;background:#007782;color:white;text-decoration:none;padding:14px 16px;border-radius:12px;font-weight:700;">Voltar &agrave; app Fleaber</a>` +
    `<p style="margin:14px 0 0;color:#7A858C;font-size:12px;">Se a app n&atilde;o abrir, volta manualmente &agrave; Fleaber.</p>` +
    `</div></div></body></html>`;

  const headers = new Headers(corsHeaders);
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.delete("X-Content-Type-Options");

  return new Response(html, {
    status: options?.status ?? 200,
    headers,
  });
}

function androidIntentUrl(
  sessionId: string,
  options: {
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
) {
  const deepLinkPath =
    `fleaber.com/stripe-success?${stripeReturnQuery(sessionId, options).toString()}`;
  const fallback = encodeURIComponent("https://fleaber.app");
  return `intent://${deepLinkPath}#Intent;scheme=fleaber;package=pt.fleaber.app;S.browser_fallback_url=${fallback};end`;
}

/** Após Stripe: telemóvel → Intent; Chrome desktop → HTML com deep link. */
function stripePaidReturnResponse(
  req: Request,
  sessionId: string,
  returnOptions: {
    liveId?: string;
    playbackId?: string;
    isLive?: string;
    sellerId?: string;
  },
  sessionMetadata?: Record<string, string> | null,
) {
  const webReturnOrigin = sanitizeWebReturnOrigin(
    sessionMetadata?.web_return_origin ?? "",
  );
  if (webReturnOrigin) {
    const webReturn =
      `${webReturnOrigin.replace(/\/$/, "")}/stripe-success?${stripeReturnQuery(sessionId, returnOptions).toString()}`;
    return intentRedirectResponse(webReturn);
  }

  const deep = fleaberDeepLinkUrl(sessionId, returnOptions);
  const ua = req.headers.get("user-agent") ?? "";
  if (isMobileUserAgent(ua)) {
    return intentRedirectResponse(androidIntentUrl(sessionId, returnOptions));
  }

  return htmlResponse(
    "Pagamento recebido",
    "O pagamento foi confirmado. Se a app não abrir sozinha, toca no botão abaixo.",
    { appUrl: deep, autoOpenApp: true },
  );
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
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Supabase is not configured.");
    }

    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2024-06-20",
      httpClient: Stripe.createFetchHttpClient(),
    });
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const functionUrl = `${supabaseUrl}/functions/v1/create-live-tip-checkout`;

    if (req.method === "GET") {
      const url = new URL(req.url);
      const sessionId = url.searchParams.get("session_id");
      if (!sessionId) {
        return textResponse("Sessão Stripe em falta.", 400);
      }

      // SEC-034: rate-limit settle via return URL (sem JWT) — BATATA gorjetas.
      const tipRate = await checkAnonRate(
        supabase,
        `tip_settle:${sessionId.slice(0, 64)}`,
        "create-live-tip-checkout-get",
        20,
      );
      if (tipRate.rateLimited) {
        return textResponse(
          "Demasiados pedidos. Volta à app Fleaber e espera um momento.",
          429,
        );
      }

      let session: Stripe.Checkout.Session;
      try {
        session = await stripe.checkout.sessions.retrieve(sessionId);
      } catch (_) {
        // BC-P3: não ecoar «No such checkout.session» (oráculo Stripe).
        return textResponse(
          "Pagamento ainda não confirmado. Se já pagaste, aguarda alguns segundos e volta à app Fleaber.",
          400,
        );
      }
      const tipId = session.metadata?.tip_id;
      const liveId = session.metadata?.live_id ?? "";
      const playbackId = session.metadata?.playback_id ?? "";
      const isLive = session.metadata?.is_live ?? "true";
      const sellerId = session.metadata?.seller_id ?? "";
      const returnOptions = {
        liveId,
        playbackId,
        isLive,
        sellerId,
      };

      let settleError = "";
      if (
        url.searchParams.get("checkout_return") === "success" &&
        session.payment_status === "paid" &&
        tipId
      ) {
        try {
          const paidCents = session.amount_total;
          if (paidCents == null || !Number.isFinite(paidCents) || paidCents < 100) {
            throw new Error("Montante Stripe da gorjeta inválido.");
          }
          const { data, error } = await supabase.rpc(
            "batata_settle_live_tip_from_stripe",
            {
              p_tip_id: tipId,
              p_stripe_session_id: sessionId,
              p_paid_amount_cents: paidCents,
            },
          );
          if (error) throw error;
          if (data !== true) {
            throw new Error("Não foi possível concluir a gorjeta.");
          }
        } catch (error) {
          settleError = error instanceof Error ? error.message : String(error);
          // Não ecoar detalhes Stripe / Postgres ao browser
          if (/stripe|checkout\.session|no such|22P02|PGRST/i.test(settleError)) {
            settleError = "Não foi possível concluir a gorjeta.";
          }
        }
      }

      const paid = session.payment_status === "paid";
      if (paid && settleError.length === 0) {
        return stripePaidReturnResponse(
          req,
          sessionId,
          returnOptions,
          session.metadata as Record<string, string> | null,
        );
      }
      if (paid && settleError.length > 0) {
        return textResponse(
          `PAGAMENTO RECEBIDO\n\nErro ao registar gorjeta:\n${settleError}\n\nVolta à app Fleaber.`,
          500,
        );
      }
      return textResponse(
        "Pagamento ainda não confirmado. Se já pagaste, aguarda alguns segundos e volta à app Fleaber.",
      );
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("Missing authorization.");
    }

    const body = (await req.json()) as LiveTipCheckoutRequest;
    const sellerId = body.seller_id?.trim();
    const amountEur = Number(body.amount_eur);
    if (!sellerId) {
      throw new Error("Missing seller_id.");
    }
    if (!Number.isFinite(amountEur) || amountEur < 1) {
      throw new Error("Invalid tip amount.");
    }

    const supabaseForAuth = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await supabaseForAuth.auth.getUser();
    if (userError || !user) {
      throw new Error("Invalid checkout user.");
    }

    await logStripeCheckoutEvent(supabase, "tip_checkout_request", {
      buyer_id: user.id,
      live_id: body.live_id?.trim() || null,
      seller_id: body.seller_id?.trim() || null,
      amount_eur: body.amount_eur,
      web_return_origin: body.web_return_origin?.trim() || null,
    });

    // SEC-034b: anti-spam só — fail-open. 30/h >> gorjetas reais.
    const tipCreateRate = await checkAnonRate(
      supabase,
      `tip_create:${user.id}`,
      "create-live-tip-checkout-post",
      30,
    );
    if (tipCreateRate.rateLimited) {
      return new Response(
        JSON.stringify({ error: "Demasiadas gorjetas. Tenta daqui a pouco." }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const amountCents = Math.round(amountEur * 100);
    if (amountCents < 100) {
      throw new Error("Invalid tip amount.");
    }
    // FASE3: teto servidor (cliente não define montantes ilimitados).
    if (amountCents > 50000) {
      throw new Error("Tip amount too high.");
    }

    const liveId = body.live_id?.trim() || null;
    if (!liveId) {
      throw new Error("live_id is required for tip checkout.");
    }
    const { data: tipLive, error: tipLiveErr } = await supabase
      .from("lives")
      .select("id, status, is_active, seller_id, vendedor_id")
      .eq("id", liveId)
      .maybeSingle();
    if (tipLiveErr || !tipLive) {
      throw new Error("Live not found for tip.");
    }
    const tipLiveOwner = String(tipLive.seller_id ?? tipLive.vendedor_id ?? "");
    if (tipLiveOwner !== sellerId) {
      throw new Error("Tip seller does not own this live.");
    }
    const { data: tipSellerProf, error: tipSellerProfErr } = await supabase
      .from("profiles")
      .select("hub_published")
      .eq("id", tipLiveOwner)
      .maybeSingle();
    if (tipSellerProfErr || tipSellerProf?.hub_published !== true) {
      throw new Error("Tips only allowed for published hub sellers.");
    }
    const { data: tipBroadcasting, error: tipBroadcastErr } = await supabase
      .rpc("batata_live_is_broadcasting", { p_live_id: liveId });
    if (tipBroadcastErr) {
      throw new Error("Tips only allowed while the live is broadcasting.");
    }
    if (tipBroadcasting !== true) {
      throw new Error("Tips only allowed while the live is broadcasting.");
    }
    const message = body.message?.trim() || null;
    const playbackId = body.playback_id?.trim() || "";
    const isLive = body.is_live === false ? "false" : "true";
    const webReturnOrigin = sanitizeWebReturnOrigin(body.web_return_origin) ??
      "";

    // FASE3B: nunca confiar em tip_id do cliente (pay B / credit A).
    // Autoridade: criar pending com o mesmo montante que será cobrado no Stripe.
    if (body.tip_id != null && String(body.tip_id).trim().length > 0) {
      throw new Error("Client tip_id is not allowed.");
    }

    const { data: createdTipId, error: createTipError } = await supabaseForAuth
      .rpc("batata_create_live_tip_pending", {
        p_live_id: liveId,
        p_seller_id: sellerId,
        p_amount: amountEur,
        p_message: message,
      });
    if (createTipError || !createdTipId) {
      throw createTipError ?? new Error("Could not create pending tip.");
    }
    const tipId = String(createdTipId);

    // Re-ler tip (service) e cobrar exactamente tip.amount — não o body isolado.
    const { data: tipRow, error: tipLoadErr } = await supabase
      .from("live_tips")
      .select("id, buyer_id, seller_id, amount, status, stripe_session_id")
      .eq("id", tipId)
      .maybeSingle();
    if (tipLoadErr || !tipRow) {
      throw tipLoadErr ?? new Error("Pending tip missing after create.");
    }
    if (tipRow.buyer_id !== user.id) {
      throw new Error("Tip buyer mismatch.");
    }
    if (tipRow.seller_id !== sellerId) {
      throw new Error("Tip seller mismatch.");
    }
    if (tipRow.status !== "pending") {
      throw new Error("Tip is not pending.");
    }
    const tipAmountCents = Math.round(Number(tipRow.amount) * 100);
    if (!Number.isFinite(tipAmountCents) || tipAmountCents !== amountCents) {
      throw new Error("Tip amount desync.");
    }
    if (
      typeof tipRow.stripe_session_id === "string" &&
      tipRow.stripe_session_id.trim().length > 0
    ) {
      throw new Error("Tip already has a checkout session.");
    }

    const checkoutSession = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      success_url:
        `${functionUrl}?checkout_return=success&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url:
        `${functionUrl}?checkout_return=cancel&session_id={CHECKOUT_SESSION_ID}`,
      line_items: [
        {
          price_data: {
            currency: "eur",
            product_data: {
              name: "Gorjeta Fleaber",
              description: "Gorjeta ao vendedor em direto",
            },
            unit_amount: tipAmountCents,
          },
          quantity: 1,
        },
      ],
      metadata: {
        purpose: "live_tip",
        tip_id: tipId,
        buyer_id: user.id,
        seller_id: sellerId,
        live_id: liveId ?? "",
        playback_id: playbackId,
        is_live: isLive,
        amount_eur: String(tipRow.amount),
        amount_cents: String(tipAmountCents),
        ...(webReturnOrigin.length > 0
          ? { web_return_origin: webReturnOrigin }
          : {}),
      },
    });

    const { data: boundRows, error: bindErr } = await supabase
      .from("live_tips")
      .update({ stripe_session_id: checkoutSession.id })
      .eq("id", tipId)
      .eq("buyer_id", user.id)
      .eq("status", "pending")
      .is("stripe_session_id", null)
      .select("id");
    if (bindErr || !boundRows?.length) {
      throw bindErr ??
        new Error("Could not bind tip to checkout session (race).");
    }

    await logStripeCheckoutEvent(supabase, "tip_checkout_session_created", {
      session_id: checkoutSession.id,
      buyer_id: user.id,
      live_id: liveId,
      tip_id: tipId,
      seller_id: sellerId,
      amount_eur: amountEur,
      has_checkout_url: Boolean(checkoutSession.url),
    });

    return new Response(
      JSON.stringify({
        checkoutUrl: checkoutSession.url,
        checkoutSessionId: checkoutSession.id,
        tipId,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    const errMsg = error instanceof Error ? error.message : String(error);
    console.error("create-live-tip-checkout error", errMsg);
    try {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (supabaseUrl && serviceRoleKey) {
        const admin = createClient(supabaseUrl, serviceRoleKey);
        await logStripeCheckoutEvent(admin, "tip_checkout_error", {
          error: errMsg,
        });
      }
    } catch (_) {
      /* ignore secondary log failure */
    }
    return new Response(
      JSON.stringify({
        error: errMsg,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      },
    );
  }
});
