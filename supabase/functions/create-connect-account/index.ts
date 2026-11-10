import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import {
  assertStripeLivePilotPayout,
  assertStripeLivePilotSeller,
  isStripeLiveGlobalGo,
  isStripeLivePilotEnabled,
  resolveStripeSecretForMode,
} from "../_shared/ops_env.ts";
import {
  safeWalletReturnLocation,
  sanitizeWebReturnOrigin,
} from "../_shared/web_return.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

type ConnectAccountRequest = {
  user_id?: string;
  amount?: number;
  /** Cliente pode reenviar a mesma key em retry — evita 2ª transferência Stripe. */
  idempotency_key?: string;
  web_return_origin?: string;
  /** Staging/TEST only */
  crash_inject?: string;
};

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

function timingSafeEqualStr(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const aa = enc.encode(a);
  const bb = enc.encode(b);
  if (aa.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < aa.length; i++) diff |= aa[i]! ^ bb[i]!;
  return diff === 0;
}

/** AR1 + BJ4-P0 + BP-P2 + BV-P2 + CH-P2: idempotency Unicode.
 *  NFKC; strip marks/ZW; fold lookalikes (cirílico/grego/arménio/georgiano);
 *  toLowerCase (I/i); apagar resto non-ASCII. */
async function payoutIdempotencyKey(
  userId: string,
  rawKey: string,
): Promise<string> {
  const folded = rawKey
    .normalize("NFKC")
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/\p{M}/gu, "")
    .replace(/[\u00A0\u2000-\u200A\u202F\u205F\u3000\s]+/g, "")
    .replace(/[аАαΑⲁᎪ]/g, "a")
    .replace(/[еЕёЁεΕⲉ]/g, "e")
    .replace(/[оОοΟօՕოⲟᎾ]/g, "o")
    .replace(/[рРρΡⲣ]/g, "p")
    .replace(/[іІιΙİⲓ]/g, "i")
    .replace(/[кКκΚⲕ]/g, "k")
    .replace(/[сС]/g, "c")
    .replace(/[уУ]/g, "y")
    .replace(/[υΥ]/g, "u")
    .replace(/[хХχΧ]/g, "x")
    .replace(/[ј]/g, "j")
    .replace(/[ѕЅſ]/g, "s")
    .replace(/[νΝ]/g, "v")
    .replace(/[τΤ]/g, "t")
    .replace(/[ηΗ]/g, "n")
    .replace(/[μΜ]/g, "m")
    .replace(/[βΒ]/g, "b")
    .toLowerCase()
    .replace(/[^\x20-\x7E]/g, "");
  const material = `${userId}\n${folded}`;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(material),
  );
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `p_${hex.slice(0, 62)}`;
}

function allowPayoutCrashInject(
  stripeSecretKey: string,
  req: Request,
  body: ConnectAccountRequest,
): string | null {
  if (!isStripeTestKey(stripeSecretKey)) return null;
  const secret = Deno.env.get("FLEABER_STAGING_CRASH_INJECT_SECRET") ?? "";
  if (!secret || secret.length < 16) return null;
  const hdr = (req.headers.get("x-fleaber-crash-inject-secret") ?? "").trim();
  if (!timingSafeEqualStr(hdr, secret)) return null;
  const point = (body.crash_inject ??
    req.headers.get("x-fleaber-crash-inject") ?? "").trim();
  if (
    point === "after_debit_before_stripe" ||
    point === "after_stripe_before_finish" ||
    point === "after_finish_before_response"
  ) {
    return point;
  }
  return null;
}

function htmlResponse(
  title: string,
  message: string,
  options?: { appUrl?: string; status?: number; autoOpenApp?: boolean },
) {
  const appUrl = options?.appUrl ?? "fleaber://fleaber.com/wallet";
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

  // Headers sem cors Content-Type; sem nosniff (se o gateway forçar text/plain, o browser ainda pode renderizar HTML).
  const headers = new Headers(corsHeaders);
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.delete("X-Content-Type-Options");

  return new Response(html, {
    status: options?.status ?? 200,
    headers,
  });
}

function isMobileUserAgent(ua: string): boolean {
  return /Android|iPhone|iPad|iPod/i.test(ua);
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

function isStripeTestKey(key: string): boolean {
  return key.startsWith("sk_test_");
}

type PayoutDb = ReturnType<typeof createClient>;

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function stripeMeta(error: unknown): { code: string; type: string; message: string } {
  const obj = typeof error === "object" && error !== null
    ? error as Record<string, unknown>
    : {};
  const raw = typeof obj.raw === "object" && obj.raw !== null
    ? obj.raw as Record<string, unknown>
    : {};
  return {
    code: String(obj.code ?? raw.code ?? ""),
    type: String(obj.type ?? raw.type ?? ""),
    message: error instanceof Error ? error.message : String(error),
  };
}

function publicPayoutError(error: unknown): string {
  const { code, message } = stripeMeta(error);
  if (code === "balance_insufficient" || /insufficient (available )?funds/i.test(message)) {
    return "A Stripe de testes ainda está a libertar fundos. Espera uns segundos e tenta outra vez.";
  }
  if (/row-level security|violates row-level/i.test(message)) {
    return "Não foi possível gravar o levantamento na carteira. Tenta outra vez.";
  }
  if (
    code === "account_invalid" ||
    (/destination/i.test(message) && /capabilit/i.test(message))
  ) {
    return "A conta bancária Stripe ainda não está pronta para receber transferências.";
  }
  if (message.length > 0 && message.length <= 180) return message;
  return "Não foi possível concluir o levantamento. Tenta outra vez.";
}

async function logPayout(db: PayoutDb | null, event: Record<string, unknown>) {
  const line = JSON.stringify(event);
  console.error("FLEABER_PAYOUT", line);
  if (!db) return;
  try {
    const { error } = await db.from("app_logs").insert({
      category: "wallet_payout",
      error_message: line.slice(0, 8000),
      device_info: { source: "create-connect-account", ...event },
    });
    if (error) {
      console.error("FLEABER_PAYOUT log_insert_failed", error.message);
    }
  } catch (e) {
    console.error("FLEABER_PAYOUT log_insert_failed", e);
  }
}

function isInsufficientAvailableFunds(error: unknown): boolean {
  const { code, message } = stripeMeta(error);
  return code === "balance_insufficient" ||
    /insufficient (available )?funds/i.test(message);
}

async function availableBalanceCents(
  stripe: Stripe,
  currency: string,
): Promise<number> {
  const balance = await stripe.balance.retrieve();
  const row = balance.available.find((item) => item.currency === currency);
  return row?.amount ?? 0;
}

async function addSandboxPlatformFunds(
  stripe: Stripe,
  amount: number,
  currency: string,
  db: PayoutDb,
): Promise<void> {
  try {
    await stripe.charges.create({
      amount,
      currency,
      source: "tok_bypassPending",
      description: "Fleaber sandbox: fundos de teste para levantamento",
    });
    await logPayout(db, { step: "sandbox_charge_ok", amount, currency });
    return;
  } catch (chargeError) {
    await logPayout(db, {
      step: "sandbox_charge_failed",
      amount,
      currency,
      ...stripeMeta(chargeError),
    });
  }

  // Stripe exige return_url em confirmações que possam redireccionar (alerta TEST).
  await stripe.paymentIntents.create({
    amount,
    currency,
    confirm: true,
    payment_method: "pm_card_bypassPending",
    payment_method_types: ["card"],
    return_url: "https://fleaber.pt/wallet/return",
  });
  await logPayout(db, { step: "sandbox_payment_intent_ok", amount, currency });
}

async function createPayoutTransfer(
  stripe: Stripe,
  secretKey: string,
  params: Stripe.TransferCreateParams,
  db: PayoutDb,
  idempotencyKey?: string,
): Promise<Stripe.Transfer> {
  // Chave Stripe distinta após top-up: reutilizar a mesma após balance_insufficient
  // devolve o erro em cache e nunca cria a Transfer.
  const stripeIdem = (suffix: string) =>
    idempotencyKey
      ? { idempotencyKey: `fleaber_wd_${idempotencyKey}${suffix}` }
      : undefined;

  try {
    return await stripe.transfers.create(params, stripeIdem(""));
  } catch (error) {
    if (!isStripeTestKey(secretKey) || !isInsufficientAvailableFunds(error)) {
      throw error;
    }

    const currency = String(params.currency ?? "eur");
    const needed = Number(params.amount ?? 0);
    const topUp = Math.max(needed, 100) + 5000;
    await logPayout(db, {
      step: "sandbox_topup_start",
      needed,
      topUp,
      currency,
      ...stripeMeta(error),
    });
    await addSandboxPlatformFunds(stripe, topUp, currency, db);

    for (let attempt = 1; attempt <= 12; attempt++) {
      const available = await availableBalanceCents(stripe, currency);
      await logPayout(db, {
        step: "sandbox_balance_check",
        attempt,
        available,
        needed,
      });
      if (available >= needed) {
        return await stripe.transfers.create(params, stripeIdem("_funded"));
      }
      await sleep(1000);
    }

    return await stripe.transfers.create(params, stripeIdem("_funded_last"));
  }
}

function isConnectReady(account: Stripe.Account): boolean {
  return account.details_submitted === true &&
    account.capabilities?.transfers === "active";
}

function connectReadinessError(account: Stripe.Account): string {
  const due = (account.requirements?.currently_due ?? []).map(String);
  const transfers = account.capabilities?.transfers ?? "n/d";
  if (due.includes("external_account")) {
    return "Falta associar a conta bancária no Stripe. Abre outra vez Configurar conta bancária e adiciona o IBAN de teste.";
  }
  if (account.details_submitted !== true) {
    return "Ainda falta completar os dados no Stripe. Abre outra vez Configurar conta bancária.";
  }
  if (account.capabilities?.transfers !== "active") {
    return `A Stripe ainda está a activar transferências (${transfers}). Espera um minuto, ou completa o que faltar em Configurar conta bancária.`;
  }
  return "A conta bancária ainda não está pronta para receber levantamentos. Completa primeiro a configuração Stripe Connect.";
}

async function resolveConnectAccount(
  stripe: Stripe,
  userId: string,
  savedId: string | null | undefined,
): Promise<Stripe.Account | null> {
  const byId = new Map<string, Stripe.Account>();
  if (savedId) {
    try {
      const saved = await stripe.accounts.retrieve(savedId);
      byId.set(saved.id, saved);
    } catch {
      // Conta gravada na carteira já não existe no Stripe.
    }
  }
  try {
    const found = await stripe.accounts.search({
      query: `metadata["fleaber_user_id"]:"${userId}"`,
      limit: 10,
    });
    for (const row of found.data) {
      byId.set(row.id, row);
    }
  } catch {
    // Search pode não estar activo; usa só a conta gravada.
  }

  const candidates = [...byId.values()];
  if (candidates.length === 0) return null;
  return candidates.find(isConnectReady) ??
    candidates.find((a) => a.details_submitted === true) ??
    candidates[0];
}

function walletDeepLinkUrl() {
  return "fleaber://fleaber.com/wallet";
}

function walletAndroidIntentUrl() {
  const deepLinkPath = "fleaber.com/wallet";
  const fallback = encodeURIComponent("https://fleaber.app");
  return `intent://${deepLinkPath}#Intent;scheme=fleaber;package=pt.fleaber.app;S.browser_fallback_url=${fallback};end`;
}

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method === "GET") {
    const url = new URL(req.url);
    const webReturnOrigin = (url.searchParams.get("web_return_origin") ?? "")
      .trim();
    const safeWallet = safeWalletReturnLocation(webReturnOrigin);
    if (safeWallet) {
      return new Response(null, {
        status: 303,
        headers: {
          ...corsHeaders,
          Location: safeWallet,
          "Cache-Control": "no-store",
        },
      });
    }

    // Mesmo padrão do checkout Stripe (create-payment-intent):
    // telemóvel → Intent 303 (HTML no gateway aparece como «linhas de código»);
    // Chrome desktop → página HTML com deep link.
    const userAgent = req.headers.get("user-agent") ?? "";
    if (isMobileUserAgent(userAgent)) {
      return intentRedirectResponse(walletAndroidIntentUrl());
    }
    return htmlResponse(
      "Conta bancária configurada",
      "Podes voltar &agrave; tua carteira Fleaber para continuar o levantamento.",
      { appUrl: walletDeepLinkUrl(), autoOpenApp: true },
    );
  }

  // AX1: só POST cria levantamento / onboarding com body
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed." }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let payoutLogDb: PayoutDb | null = null;
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    // ZIP 178/181: default TEST. LIVE = GO global OU piloto allowlisted (sem GO global).
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("Missing authorization.");
    }
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Stripe Connect is not configured.");
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

    const pilotSeller = assertStripeLivePilotSeller(user.id);
    const goLive = isStripeLiveGlobalGo() ||
      (isStripeLivePilotEnabled() && pilotSeller.ok);
    const stripeResolved = resolveStripeSecretForMode(goLive ? "live" : "test");
    const stripeSecretKey = stripeResolved.ok ? stripeResolved.key : "";

    if (!stripeSecretKey) {
      throw new Error(
        goLive && !stripeResolved.ok
          ? `Stripe Connect LIVE bloqueado (${stripeResolved.error}).`
          : "Stripe Connect is not configured.",
      );
    }

    // Validar key em falta ANTES do rate-limit (resposta estável para clientes/hostiles).
    // RTC-C-P2-02: amount≤0 / negativo ≠ onboarding silencioso 200.
    // AX3: rejeitar boolean / hex / Number() frouxo (true→1, "0x64"→100).
    const amountEarlyRaw = body.amount;
    const amountEarlyProvided = amountEarlyRaw !== undefined &&
      amountEarlyRaw !== null &&
      `${amountEarlyRaw}`.trim() !== "";
    let amountEarly = 0;
    if (amountEarlyProvided) {
      if (
        typeof amountEarlyRaw === "boolean" ||
        (typeof amountEarlyRaw === "string" &&
          (/^\s*0x/i.test(amountEarlyRaw) ||
            /e/i.test(amountEarlyRaw.trim())))
      ) {
        throw new Error("Valor de levantamento inválido.");
      }
      if (
        typeof amountEarlyRaw !== "number" &&
        typeof amountEarlyRaw !== "string"
      ) {
        throw new Error("Valor de levantamento inválido.");
      }
      const amountEarlyParsed = typeof amountEarlyRaw === "number"
        ? amountEarlyRaw
        : Number(String(amountEarlyRaw).trim());
      if (
        !Number.isFinite(amountEarlyParsed) ||
        amountEarlyParsed <= 0 ||
        !Number.isInteger(amountEarlyParsed)
      ) {
        throw new Error(
          !Number.isInteger(amountEarlyParsed) && Number.isFinite(amountEarlyParsed)
            ? "O valor do levantamento tem de ser em cêntimos."
            : "Valor de levantamento inválido.",
        );
      }
      amountEarly = amountEarlyParsed;
    }
    if (Number.isFinite(amountEarly) && amountEarly > 0) {
      const rawKeyEarly = typeof body.idempotency_key === "string"
        ? body.idempotency_key.trim()
        : "";
      // Allowlist charset (app usa wd_{uuid}_{cents}_{ms}) — corta Coptic/Cherokee/…
      if (rawKeyEarly.length < 8 || rawKeyEarly.length > 200) {
        throw new Error(
          "idempotency_key em falta. Reinicia o levantamento na app.",
        );
      }
      const rawKeyAscii = rawKeyEarly.normalize("NFKC");
      if (!/^[a-zA-Z0-9_-]+$/.test(rawKeyAscii)) {
        throw new Error(
          "idempotency_key inválida. Reinicia o levantamento na app.",
        );
      }
    }

    // SEC-037: anti-spam onboarding/levantamento — fail-open. 20/h >> uso real wallet.
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);
    const connectRate = await checkAnonRate(
      supabaseAdmin,
      `connect_account:${user.id}`,
      "create-connect-account",
      60,
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
    payoutLogDb = supabaseAdmin;

    const { data: wallet } = await supabase
      .from("wallets")
      .select("id,stripe_account_id,balance")
      .eq("id", user.id)
      .maybeSingle();

    let account = await resolveConnectAccount(
      stripe,
      user.id,
      wallet?.stripe_account_id as string | null | undefined,
    );

    if (!account) {
      // Conta Express própria do vendedor (metadata fleaber_user_id).
      // business_type individual por defeito — particulares não herdam a
      // entidade da plataforma (ex. Mare Antiga). Empresas alteram no onboarding.
      account = await stripe.accounts.create({
        type: "express",
        country: "PT",
        business_type: "individual",
        email: user.email ?? undefined,
        capabilities: {
          transfers: { requested: true },
        },
        metadata: {
          fleaber_user_id: user.id,
        },
      });
    }

    const accountId = account.id;

    if (accountId && accountId !== wallet?.stripe_account_id) {
      if (wallet?.id) {
        const { data: updated, error: walletUpdateError } = await supabaseAdmin
          .from("wallets")
          .update({ stripe_account_id: accountId })
          .eq("id", user.id)
          .select("id");
        if (walletUpdateError) {
          throw walletUpdateError;
        }
        if (!updated?.length) {
          throw new Error("Não foi possível gravar a conta Stripe na carteira.");
        }
      } else {
        const { error: walletInsertError } = await supabaseAdmin.from("wallets").insert({
          id: user.id,
          stripe_account_id: accountId,
          balance: 0,
        });
        if (walletInsertError) {
          throw walletInsertError;
        }
      }
    }

    // AX3: mesma validação estrita no caminho Transfer (não só early).
    let amount = 0;
    if (amountEarlyProvided) {
      amount = amountEarly;
    } else if (
      body.amount !== undefined &&
      body.amount !== null &&
      `${body.amount}`.trim() !== ""
    ) {
      throw new Error("Valor de levantamento inválido.");
    }
    if (Number.isFinite(amount) && amount > 0) {
      if (!Number.isInteger(amount)) {
        throw new Error("O valor do levantamento tem de ser em cêntimos.");
      }

      // ZIP 181: levantamento LIVE piloto exige allowlist + MONEY_GO (sem GO global).
      if (goLive && !isStripeLiveGlobalGo()) {
        const payoutGate = assertStripeLivePilotPayout({
          sellerId: user.id,
          amountCents: amount,
        });
        if (!payoutGate.ok) {
          return new Response(
            JSON.stringify({
              ok: false,
              error: payoutGate.error,
              needs_money_confirmation: payoutGate.needs_money_confirmation ===
                true,
              max_total_cents: payoutGate.max_total_cents ?? null,
              message: payoutGate.needs_money_confirmation
                ? "Levantamento LIVE piloto à espera de confirmação de valor (MONEY_GO)."
                : "Levantamento LIVE piloto bloqueado.",
            }),
            {
              status: 403,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }

      const latest = await stripe.accounts.retrieve(accountId);
      if (!isConnectReady(latest)) {
        throw new Error(connectReadinessError(latest));
      }

      // FASE3B+/PRE-F4: idempotency_key obrigatória; retomar débito órfão.
      const rawKey = typeof body.idempotency_key === "string"
        ? body.idempotency_key.trim()
        : "";
      if (rawKey.length < 8 || rawKey.length > 200) {
        throw new Error(
          "idempotency_key em falta. Reinicia o levantamento na app.",
        );
      }
      const rawKeyAscii = rawKey.normalize("NFKC");
      if (!/^[a-zA-Z0-9_-]+$/.test(rawKeyAscii)) {
        throw new Error(
          "idempotency_key inválida. Reinicia o levantamento na app.",
        );
      }
      let idempotencyKey = await payoutIdempotencyKey(user.id, rawKeyAscii);
      const crashPoint = allowPayoutCrashInject(stripeSecretKey, req, body);

      // Retomar só a MESMA idempotency_key (CEGA-P2-01).
      // Remap por amount_cents fundia 2 intenções concorrentes da mesma conta.
      // Crash recovery: a app reenvia a mesma key.

      const { data: debitRaw, error: debitErr } = await supabaseAdmin.rpc(
        "batata_wallet_payout_debit",
        {
          p_user_id: user.id,
          p_amount_cents: amount,
          p_idempotency_key: idempotencyKey,
        },
      );
      if (debitErr) {
        throw debitErr;
      }
      const debit = (debitRaw ?? {}) as Record<string, unknown>;
      if (debit.ok !== true) {
        const err = String(debit.error ?? "debit_failed");
        if (err === "insufficient_balance") {
          throw new Error("Saldo disponível insuficiente para este levantamento.");
        }
        if (err === "idempotency_key_foreign") {
          throw new Error(
            "Chave de levantamento inválida. Reinicia o levantamento na app.",
          );
        }
        throw new Error("Não foi possível reservar o saldo para levantamento.");
      }

      if (
        debit.status === "transferred" &&
        typeof debit.stripe_transfer_id === "string"
      ) {
        return new Response(
          JSON.stringify({
            success: true,
            transferId: debit.stripe_transfer_id,
            balance: debit.balance_after,
            idempotent: true,
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 200,
          },
        );
      }

      if (debit.status === "failed") {
        throw new Error(
          "Este pedido de levantamento já falhou. Inicia um novo levantamento.",
        );
      }

      if (debit.status !== "debited") {
        throw new Error("Estado de levantamento inválido. Tenta outra vez.");
      }

      if (crashPoint === "after_debit_before_stripe") {
        return new Response(
          JSON.stringify({
            success: false,
            error: "crash_inject:after_debit_before_stripe",
            code: "payout_pending_reconcile",
            needs_reconcile: true,
            idempotency_key: idempotencyKey,
            crash_inject: true,
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 500,
          },
        );
      }

      await logPayout(payoutLogDb, {
        step: "payout_start",
        userId: user.id,
        amount,
        destination: accountId,
        idempotencyKey,
      });

      let transfer: Stripe.Transfer;
      try {
        transfer = await createPayoutTransfer(
          stripe,
          stripeSecretKey,
          {
            amount,
            currency: "eur",
            destination: accountId,
            metadata: {
              fleaber_user_id: user.id,
              type: "wallet_withdrawal",
              fleaber_payout_key: idempotencyKey,
            },
          },
          supabaseAdmin,
          idempotencyKey,
        );
      } catch (transferErr) {
        await supabaseAdmin.rpc("batata_wallet_payout_finish", {
          p_idempotency_key: idempotencyKey,
          p_stripe_transfer_id: null,
          p_failed: true,
        });
        await logPayout(payoutLogDb, {
          step: "transfer_failed_refunded",
          userId: user.id,
          idempotencyKey,
          message: transferErr instanceof Error
            ? transferErr.message
            : String(transferErr),
        });
        throw transferErr;
      }

      await logPayout(payoutLogDb, {
        step: "transfer_ok",
        userId: user.id,
        amount,
        transferId: transfer.id,
        idempotencyKey,
      });

      if (crashPoint === "after_stripe_before_finish") {
        return new Response(
          JSON.stringify({
            success: false,
            error: "crash_inject:after_stripe_before_finish",
            code: "payout_pending_reconcile",
            needs_reconcile: true,
            transferId: transfer.id,
            idempotency_key: idempotencyKey,
            crash_inject: true,
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 500,
          },
        );
      }

      const { data: finishRaw, error: finishErr } = await supabaseAdmin.rpc(
        "batata_wallet_payout_finish",
        {
          p_idempotency_key: idempotencyKey,
          p_stripe_transfer_id: transfer.id,
          p_failed: false,
        },
      );
      if (finishErr) {
        await logPayout(payoutLogDb, {
          step: "payout_finish_failed",
          transferId: transfer.id,
          message: finishErr.message,
        });
        // Transfer Stripe já existe — NÃO marcar failed; retry deve finish.
        return new Response(
          JSON.stringify({
            success: false,
            error: finishErr.message,
            code: "payout_pending_reconcile",
            needs_reconcile: true,
            transferId: transfer.id,
            idempotency_key: idempotencyKey,
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 500,
          },
        );
      }
      const finish = (finishRaw ?? {}) as Record<string, unknown>;

      await logPayout(payoutLogDb, {
        step: "payout_ok",
        userId: user.id,
        transferId: transfer.id,
        balance: finish.balance_after ?? debit.balance_after,
      });

      // ZIP 166 — notificação in-app (idempotente por payout key)
      try {
        const amountEur = typeof debit.amount_eur === "number"
          ? debit.amount_eur
          : Number(debit.amount_cents ?? 0) / 100;
        await supabaseAdmin.rpc("batata_notify_wallet_payout_sent", {
          p_user_id: user.id,
          p_amount_eur: amountEur,
          p_idempotency_key: idempotencyKey,
        });
      } catch (notifyErr) {
        console.warn("payout notify soft-fail", notifyErr);
      }

      if (crashPoint === "after_finish_before_response") {
        return new Response(
          JSON.stringify({
            success: false,
            error: "crash_inject:after_finish_before_response",
            code: "payout_pending_reconcile",
            needs_reconcile: true,
            transferId: transfer.id,
            idempotency_key: idempotencyKey,
            crash_inject: true,
            note: "Ledger já transferred — retry idempotente",
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 500,
          },
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          transferId: transfer.id,
          balance: finish.balance_after ?? debit.balance_after,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        },
      );
    }

    const safeOrigin = sanitizeWebReturnOrigin(body.web_return_origin) ?? "";
    const walletReturnUrl = new URL(
      `${supabaseUrl.replace(/\/$/, "")}/functions/v1/create-connect-account`,
    );
    walletReturnUrl.searchParams.set("wallet_return", "1");
    if (safeOrigin) {
      walletReturnUrl.searchParams.set("web_return_origin", safeOrigin);
    }
    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: walletReturnUrl.toString(),
      return_url: walletReturnUrl.toString(),
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
    const meta = stripeMeta(error);
    const publicError = publicPayoutError(error);
    await logPayout(payoutLogDb, {
      step: "payout_failed",
      publicError,
      ...meta,
    });
    return new Response(
      JSON.stringify({
        error: publicError,
        code: meta.code || "payout_failed",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      },
    );
  }
});
