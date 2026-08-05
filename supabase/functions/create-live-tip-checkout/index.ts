import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
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

      const session = await stripe.checkout.sessions.retrieve(sessionId);
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
          const { data, error } = await supabase.rpc(
            "batata_settle_live_tip_from_stripe",
            {
              p_tip_id: tipId,
              p_stripe_session_id: sessionId,
            },
          );
          if (error) throw error;
          if (data !== true) {
            throw new Error("Não foi possível concluir a gorjeta.");
          }
        } catch (error) {
          settleError = error instanceof Error ? error.message : String(error);
        }
      }

      const paid = session.payment_status === "paid";
      if (paid && settleError.length === 0) {
        const webAppUrl = (
          Deno.env.get("FLEABER_WEB_APP_URL") ??
          session.metadata?.web_return_origin ??
          ""
        ).trim();
        if (webAppUrl.length > 0) {
          const webReturn =
            `${webAppUrl.replace(/\/$/, "")}/stripe-success?${stripeReturnQuery(sessionId, returnOptions).toString()}`;
          return intentRedirectResponse(webReturn);
        }
        return intentRedirectResponse(
          androidIntentUrl(sessionId, returnOptions),
        );
      }
      if (paid && settleError.length > 0) {
        return textResponse(
          `PAGAMENTO RECEBIDO\n\nErro ao registar gorjeta:\n${settleError}\n\nVolta à app Fleaber.`,
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

    const liveId = body.live_id?.trim() || null;
    const message = body.message?.trim() || null;
    const playbackId = body.playback_id?.trim() || "";
    const isLive = body.is_live === false ? "false" : "true";
    const webReturnOrigin = body.web_return_origin?.trim() || "";

    let tipId = body.tip_id?.trim();
    if (!tipId) {
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
      tipId = String(createdTipId);
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
            unit_amount: amountCents,
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
        amount_eur: String(amountEur),
        ...(webReturnOrigin.length > 0
          ? { web_return_origin: webReturnOrigin }
          : {}),
      },
    });

    await supabase
      .from("live_tips")
      .update({ stripe_session_id: checkoutSession.id })
      .eq("id", tipId)
      .eq("buyer_id", user.id);

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
