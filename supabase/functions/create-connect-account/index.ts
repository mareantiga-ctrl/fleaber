import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

type ConnectAccountRequest = {
  user_id?: string;
  amount?: number;
};

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!stripeSecretKey || !supabaseUrl || !serviceRoleKey) {
      throw new Error("Stripe Connect is not configured.");
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("Missing authorization.");
    }

    const body = (await req.json()) as ConnectAccountRequest;
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError || !user) {
      throw new Error("Invalid user.");
    }
    if (body.user_id && body.user_id !== user.id) {
      throw new Error("Cannot create another user Stripe account.");
    }

    // SEC-037: anti-spam onboarding/levantamento — fail-open. 20/h >> uso real wallet.
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);
    const connectRate = await checkAnonRate(
      supabaseAdmin,
      `connect_account:${user.id}`,
      "create-connect-account",
      20,
    );
    if (connectRate.rateLimited) {
      return new Response(
        JSON.stringify({ error: "Demasiados pedidos. Tenta daqui a pouco." }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2024-06-20",
      httpClient: Stripe.createFetchHttpClient(),
    });

    const { data: wallet } = await supabase
      .from("wallets")
      .select("id,stripe_account_id,balance")
      .eq("id", user.id)
      .maybeSingle();

    let accountId = wallet?.stripe_account_id as string | null | undefined;

    if (!accountId) {
      const account = await stripe.accounts.create({
        type: "express",
        country: "PT",
        email: user.email ?? undefined,
        capabilities: {
          transfers: { requested: true },
        },
        metadata: {
          fleaber_user_id: user.id,
        },
      });
      accountId = account.id;

      if (wallet?.id) {
        await supabase
          .from("wallets")
          .update({ stripe_account_id: accountId })
          .eq("id", user.id);
      } else {
        await supabase.from("wallets").insert({
          id: user.id,
          stripe_account_id: accountId,
          balance: 0,
        });
      }
    }

    const amount = Number(body.amount ?? 0);
    if (Number.isFinite(amount) && amount > 0) {
      if (!Number.isInteger(amount)) {
        throw new Error("O valor do levantamento tem de ser em cêntimos.");
      }

      const availableBalance = Number(wallet?.balance ?? 0);
      const requestedEuros = amount / 100;
      if (requestedEuros <= 0 || requestedEuros > availableBalance) {
        throw new Error("Saldo disponível insuficiente para este levantamento.");
      }

      const account = await stripe.accounts.retrieve(accountId);
      if (
        account.details_submitted !== true ||
        account.capabilities?.transfers !== "active"
      ) {
        throw new Error(
          "A conta bancária ainda não está pronta para receber levantamentos. Completa primeiro a configuração Stripe Connect.",
        );
      }

      const transfer = await stripe.transfers.create({
        amount,
        currency: "eur",
        destination: accountId,
        metadata: {
          fleaber_user_id: user.id,
          type: "wallet_withdrawal",
        },
      });

      const newBalance = Math.round((availableBalance - requestedEuros) * 100) / 100;
      const { error: walletUpdateError } = await supabase
        .from("wallets")
        .update({ balance: newBalance })
        .eq("id", user.id);
      if (walletUpdateError) {
        throw walletUpdateError;
      }

      const { error: transactionError } = await supabase
        .from("wallet_transactions")
        .insert({
          wallet_id: user.id,
          amount: -requestedEuros,
          type: "levantamento",
          description: "Levantamento para conta bancária",
        });
      if (transactionError) {
        throw transactionError;
      }

      return new Response(
        JSON.stringify({
          success: true,
          transferId: transfer.id,
          balance: newBalance,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        },
      );
    }

    const origin = req.headers.get("origin") ?? "https://fleaber.pt";
    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: `${origin.replace(/\/$/, "")}/wallet`,
      return_url: `${origin.replace(/\/$/, "")}/wallet`,
      type: "account_onboarding",
    });

    return new Response(
      JSON.stringify({
        stripeAccountId: accountId,
        url: accountLink.url,
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
