/**
 * ZIP 172-C1 — isolamento Stripe/DPD por encomenda (sticky).
 *
 * Stripe TEST  → STRIPE_SECRET_KEY_TEST | STRIPE_SECRET_KEY (só se sk_test_/rk_test_)
 * Stripe LIVE  → SOMENTE STRIPE_SECRET_KEY_LIVE (+ OPS_STRIPE_LIVE_GO=1
 *                OU piloto ZIP 181: OPS_STRIPE_LIVE_PILOT_ENABLED=1)
 *   NUNCA fallback LIVE → STRIPE_SECRET_KEY global.
 *   Piloto ≠ GO global: allowlist seller/buyer + teto + MONEY_GO separado.
 *
 * DPD QA         → DPD_QA_* + qabusiness.dpd.pt (independente de DPD_MODE)
 * DPD COMERCIAL  → DPD_LIVE_* + business.dpd.pt (+ OPS_DPD_COMMERCIAL_GO=1)
 *   NUNCA escolher COMERCIAL via DPD_MODE global.
 *
 * Nunca logar valores de secrets.
 */

export type StripeOpsMode = "test" | "live";
export type DpdOpsMode = "qa" | "commercial";

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function goOn(name: string): boolean {
  const v = env(name).toLowerCase();
  return v === "1" || v === "true" || v === "yes";
}

export function normalizeStripeMode(raw: unknown): StripeOpsMode {
  return String(raw ?? "test").trim().toLowerCase() === "live" ? "live" : "test";
}

export function normalizeDpdMode(raw: unknown): DpdOpsMode {
  return String(raw ?? "qa").trim().toLowerCase() === "commercial"
    ? "commercial"
    : "qa";
}

export function stripeKeyFingerprint(key: string): string {
  const k = (key ?? "").trim();
  if (k.startsWith("sk_test_")) return "sk_test";
  if (k.startsWith("sk_live_")) return "sk_live";
  if (k.startsWith("rk_test_")) return "rk_test";
  if (k.startsWith("rk_live_")) return "rk_live";
  return k ? "unknown" : "missing";
}

function isTestKey(key: string): boolean {
  const f = stripeKeyFingerprint(key);
  return f === "sk_test" || f === "rk_test";
}

function isLiveKey(key: string): boolean {
  const f = stripeKeyFingerprint(key);
  return f === "sk_live" || f === "rk_live";
}

/** Credencial Stripe TEST explícita (sem usar chave LIVE). */
export function resolveStripeTestSecret(): {
  ok: boolean;
  key: string;
  fingerprint: string;
  source?: string;
  error?: string;
} {
  const explicit = env("STRIPE_SECRET_KEY_TEST");
  if (explicit) {
    if (!isTestKey(explicit)) {
      return {
        ok: false,
        key: "",
        fingerprint: stripeKeyFingerprint(explicit),
        error: "stripe_test_secret_invalid_prefix",
      };
    }
    return {
      ok: true,
      key: explicit,
      fingerprint: stripeKeyFingerprint(explicit),
      source: "STRIPE_SECRET_KEY_TEST",
    };
  }
  const legacy = env("STRIPE_SECRET_KEY");
  if (!legacy) {
    return { ok: false, key: "", fingerprint: "missing", error: "stripe_test_key_missing" };
  }
  if (isLiveKey(legacy)) {
    return {
      ok: false,
      key: "",
      fingerprint: stripeKeyFingerprint(legacy),
      error: "stripe_test_key_missing_global_is_live",
    };
  }
  if (!isTestKey(legacy)) {
    return {
      ok: false,
      key: "",
      fingerprint: stripeKeyFingerprint(legacy),
      error: "stripe_test_unavailable",
    };
  }
  return {
    ok: true,
    key: legacy,
    fingerprint: stripeKeyFingerprint(legacy),
    source: "STRIPE_SECRET_KEY",
  };
}

/** GO global Stripe LIVE (abre LIVE a todo o sticky live). */
export function isStripeLiveGlobalGo(): boolean {
  return goOn("OPS_STRIPE_LIVE_GO");
}

/** Piloto ZIP 181 — master switch (sem GO global). */
export function isStripeLivePilotEnabled(): boolean {
  return goOn("OPS_STRIPE_LIVE_PILOT_ENABLED");
}

/**
 * Autorização explícita para movimento financeiro LIVE no piloto.
 * Independente de OPS_STRIPE_LIVE_GO (mantém-se 0).
 */
export function isStripeLivePilotMoneyGo(): boolean {
  return goOn("OPS_STRIPE_LIVE_PILOT_MONEY_GO");
}

function parseUuidAllowlist(raw: string): Set<string> {
  const out = new Set<string>();
  for (const part of raw.split(/[,;\s]+/)) {
    const t = part.trim().toLowerCase();
    if (
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(t)
    ) {
      out.add(t);
    }
  }
  return out;
}

export type StripeLivePilotConfig = {
  enabled: boolean;
  moneyGo: boolean;
  maxTotalCents: number;
  sellerIds: Set<string>;
  buyerIds: Set<string>;
};

export function stripeLivePilotConfig(): StripeLivePilotConfig {
  const maxRaw = Number(env("OPS_STRIPE_LIVE_PILOT_MAX_TOTAL_CENTS") || "500");
  const maxTotalCents = Number.isFinite(maxRaw) && maxRaw > 0
    ? Math.floor(maxRaw)
    : 500;
  return {
    enabled: isStripeLivePilotEnabled(),
    moneyGo: isStripeLivePilotMoneyGo(),
    maxTotalCents,
    sellerIds: parseUuidAllowlist(env("OPS_STRIPE_LIVE_PILOT_SELLER_IDS")),
    buyerIds: parseUuidAllowlist(env("OPS_STRIPE_LIVE_PILOT_BUYER_IDS")),
  };
}

export function stripeLiveKeyAccessAllowed(): boolean {
  return isStripeLiveGlobalGo() || isStripeLivePilotEnabled();
}

export function assertStripeLivePilotSeller(userId: string): {
  ok: boolean;
  error?: string;
} {
  const cfg = stripeLivePilotConfig();
  if (!cfg.enabled) return { ok: false, error: "stripe_live_pilot_disabled" };
  const id = String(userId ?? "").trim().toLowerCase();
  if (!id || !cfg.sellerIds.has(id)) {
    return { ok: false, error: "stripe_live_pilot_seller_not_allowlisted" };
  }
  return { ok: true };
}

export function assertStripeLivePilotCheckout(args: {
  sellerId: string;
  buyerId: string;
  totalCents: number;
}): {
  ok: boolean;
  error?: string;
  needs_money_confirmation?: boolean;
  max_total_cents?: number;
} {
  const cfg = stripeLivePilotConfig();
  if (!cfg.enabled) return { ok: false, error: "stripe_live_pilot_disabled" };
  const seller = String(args.sellerId ?? "").trim().toLowerCase();
  const buyer = String(args.buyerId ?? "").trim().toLowerCase();
  if (!seller || !cfg.sellerIds.has(seller)) {
    return { ok: false, error: "stripe_live_pilot_seller_not_allowlisted" };
  }
  if (!buyer || !cfg.buyerIds.has(buyer)) {
    return { ok: false, error: "stripe_live_pilot_buyer_not_allowlisted" };
  }
  const total = Math.floor(Number(args.totalCents) || 0);
  if (total <= 0) return { ok: false, error: "stripe_live_pilot_amount_invalid" };
  if (total > cfg.maxTotalCents) {
    return {
      ok: false,
      error: "stripe_live_pilot_amount_over_cap",
      max_total_cents: cfg.maxTotalCents,
    };
  }
  if (!cfg.moneyGo && !isStripeLiveGlobalGo()) {
    return {
      ok: false,
      error: "stripe_live_pilot_money_go_required",
      needs_money_confirmation: true,
      max_total_cents: cfg.maxTotalCents,
    };
  }
  return { ok: true };
}

export function assertStripeLivePilotPayout(args: {
  sellerId: string;
  amountCents: number;
}): {
  ok: boolean;
  error?: string;
  needs_money_confirmation?: boolean;
  max_total_cents?: number;
} {
  const sellerGate = assertStripeLivePilotSeller(args.sellerId);
  if (!sellerGate.ok) return sellerGate;
  const cfg = stripeLivePilotConfig();
  const amount = Math.floor(Number(args.amountCents) || 0);
  if (amount <= 0) return { ok: false, error: "stripe_live_pilot_amount_invalid" };
  if (amount > cfg.maxTotalCents) {
    return {
      ok: false,
      error: "stripe_live_pilot_amount_over_cap",
      max_total_cents: cfg.maxTotalCents,
    };
  }
  if (!cfg.moneyGo && !isStripeLiveGlobalGo()) {
    return {
      ok: false,
      error: "stripe_live_pilot_money_go_required",
      needs_money_confirmation: true,
      max_total_cents: cfg.maxTotalCents,
    };
  }
  return { ok: true };
}

/** Credencial Stripe LIVE — SOMENTE STRIPE_SECRET_KEY_LIVE (sem fallback). */
export function resolveStripeLiveSecret(): {
  ok: boolean;
  key: string;
  fingerprint: string;
  source?: string;
  error?: string;
} {
  if (!stripeLiveKeyAccessAllowed()) {
    return {
      ok: false,
      key: "",
      fingerprint: "missing",
      error: "stripe_live_go_missing",
    };
  }
  const liveKey = env("STRIPE_SECRET_KEY_LIVE");
  if (!liveKey) {
    return {
      ok: false,
      key: "",
      fingerprint: "missing",
      error: "stripe_live_secret_not_configured",
    };
  }
  if (!isLiveKey(liveKey)) {
    return {
      ok: false,
      key: "",
      fingerprint: stripeKeyFingerprint(liveKey),
      error: "stripe_live_secret_invalid_prefix",
    };
  }
  return {
    ok: true,
    key: liveKey,
    fingerprint: stripeKeyFingerprint(liveKey),
    source: "STRIPE_SECRET_KEY_LIVE",
  };
}

export function resolveStripeSecretForMode(mode: StripeOpsMode): {
  ok: boolean;
  key: string;
  fingerprint: string;
  source?: string;
  error?: string;
} {
  return mode === "live" ? resolveStripeLiveSecret() : resolveStripeTestSecret();
}

/** Webhook secrets separados por ambiente (processamento — LIVE exige GO). */
export function resolveStripeWebhookSecret(livemode: boolean): {
  ok: boolean;
  secret: string;
  source?: string;
  error?: string;
} {
  if (livemode) {
    // ZIP 181: piloto pode verificar/processar LIVE sem GO global.
    if (!stripeLiveKeyAccessAllowed()) {
      return { ok: false, secret: "", error: "stripe_live_go_missing" };
    }
    const live = env("STRIPE_WEBHOOK_SECRET_LIVE");
    if (!live) {
      return {
        ok: false,
        secret: "",
        error: "stripe_webhook_secret_live_missing",
      };
    }
    return { ok: true, secret: live, source: "STRIPE_WEBHOOK_SECRET_LIVE" };
  }
  const explicit = env("STRIPE_WEBHOOK_SECRET_TEST");
  if (explicit) {
    return { ok: true, secret: explicit, source: "STRIPE_WEBHOOK_SECRET_TEST" };
  }
  const legacy = env("STRIPE_WEBHOOK_SECRET");
  if (!legacy) {
    return { ok: false, secret: "", error: "stripe_webhook_secret_test_missing" };
  }
  return { ok: true, secret: legacy, source: "STRIPE_WEBHOOK_SECRET" };
}

/**
 * Secrets disponíveis só para verificar assinatura (LIVE sem GO ainda pode
 * verificar para recusar com erro claro — não processa).
 */
export function listStripeWebhookSecretsForVerify(): Array<{
  expectedLivemode: boolean;
  secret: string;
  source: string;
}> {
  const out: Array<{
    expectedLivemode: boolean;
    secret: string;
    source: string;
  }> = [];
  const testExplicit = env("STRIPE_WEBHOOK_SECRET_TEST");
  const testLegacy = env("STRIPE_WEBHOOK_SECRET");
  if (testExplicit) {
    out.push({
      expectedLivemode: false,
      secret: testExplicit,
      source: "STRIPE_WEBHOOK_SECRET_TEST",
    });
  } else if (testLegacy) {
    out.push({
      expectedLivemode: false,
      secret: testLegacy,
      source: "STRIPE_WEBHOOK_SECRET",
    });
  }
  const live = env("STRIPE_WEBHOOK_SECRET_LIVE");
  if (live) {
    out.push({
      expectedLivemode: true,
      secret: live,
      source: "STRIPE_WEBHOOK_SECRET_LIVE",
    });
  }
  // Destino Connect (Connected accounts) — whsec distinto do Your account.
  const liveConnect = env("STRIPE_WEBHOOK_SECRET_LIVE_CONNECT");
  if (liveConnect) {
    out.push({
      expectedLivemode: true,
      secret: liveConnect,
      source: "STRIPE_WEBHOOK_SECRET_LIVE_CONNECT",
    });
  }
  return out;
}

export function webhookLivemodeAllowed(
  eventLivemode: boolean,
  orderStripeMode: StripeOpsMode,
): { ok: boolean; error?: string } {
  if (eventLivemode && orderStripeMode === "test") {
    return { ok: false, error: "livemode_event_blocked_on_test_order" };
  }
  if (!eventLivemode && orderStripeMode === "live") {
    return { ok: false, error: "testmode_event_blocked_on_live_order" };
  }
  return { ok: true };
}

export const DPD_QA_BASE = "https://qabusiness.dpd.pt";
export const DPD_LIVE_BASE_DEFAULT = "https://business.dpd.pt";

export function dpdApiBaseForMode(mode: DpdOpsMode): string {
  if (mode === "commercial") {
    return env("DPD_LIVE_BASE") || DPD_LIVE_BASE_DEFAULT;
  }
  return env("DPD_QA_BASE") || DPD_QA_BASE;
}

export function dpdCreateEnabledForMode(mode: DpdOpsMode): boolean {
  if (mode === "commercial") {
    return goOn("DPD_LIVE_CREATE_ENABLED");
  }
  return env("DPD_QA_CREATE_ENABLED") === "1";
}

export type DpdOauthCreds = {
  username: string;
  password: string;
  clientId: string;
  clientSecret: string;
  baseUrl: string;
  source: string;
};

/** Credenciais DPD por modo da encomenda — sem DPD_MODE global. */
export function resolveDpdOauthForMode(mode: DpdOpsMode): {
  ok: boolean;
  creds?: DpdOauthCreds;
  error?: string;
} {
  if (mode === "qa") {
    const username = env("DPD_QA_USERNAME");
    const password = env("DPD_QA_PASSWORD");
    const clientId = env("DPD_QA_CLIENT_ID");
    const clientSecret = env("DPD_QA_CLIENT_SECRET");
    if (!username || !password || !clientId || !clientSecret) {
      return { ok: false, error: "dpd_qa_oauth_incomplete" };
    }
    return {
      ok: true,
      creds: {
        username,
        password,
        clientId,
        clientSecret,
        baseUrl: dpdApiBaseForMode("qa"),
        source: "DPD_QA_*",
      },
    };
  }

  if (!goOn("OPS_DPD_COMMERCIAL_GO")) {
    return { ok: false, error: "dpd_commercial_go_missing" };
  }
  const username = env("DPD_LIVE_USERNAME");
  const password = env("DPD_LIVE_PASSWORD");
  const clientId = env("DPD_LIVE_CLIENT_ID");
  const clientSecret = env("DPD_LIVE_CLIENT_SECRET");
  if (!username || !password || !clientId || !clientSecret) {
    return { ok: false, error: "dpd_live_credentials_missing" };
  }
  return {
    ok: true,
    creds: {
      username,
      password,
      clientId,
      clientSecret,
      baseUrl: dpdApiBaseForMode("commercial"),
      source: "DPD_LIVE_*",
    },
  };
}

/**
 * Pode executar create/validate real neste modo?
 * QA: creds QA + (create gated à parte).
 * COMERCIAL: GO + creds LIVE + create flag LIVE.
 */
export function assertDpdExecutionAllowed(orderDpdMode: DpdOpsMode): {
  ok: boolean;
  error?: string;
} {
  const oauth = resolveDpdOauthForMode(orderDpdMode);
  if (!oauth.ok) return { ok: false, error: oauth.error };
  if (orderDpdMode === "commercial" && !dpdCreateEnabledForMode("commercial")) {
    return { ok: false, error: "dpd_commercial_create_disabled" };
  }
  return { ok: true };
}

export function combinationStatus(
  stripe: StripeOpsMode,
  dpd: DpdOpsMode,
): {
  label: string;
  execution: "functional" | "blocked";
  blockers: string[];
} {
  const blockers: string[] = [];
  const s = resolveStripeSecretForMode(stripe);
  if (!s.ok) blockers.push(s.error ?? "stripe_blocked");
  const d = resolveDpdOauthForMode(dpd);
  if (!d.ok) blockers.push(d.error ?? "dpd_blocked");
  if (dpd === "commercial" && !dpdCreateEnabledForMode("commercial")) {
    blockers.push("dpd_commercial_create_disabled");
  }
  return {
    label: `${stripe}+${dpd}`,
    execution: blockers.length ? "blocked" : "functional",
    blockers,
  };
}

export function combinationLabel(
  stripe: StripeOpsMode,
  dpd: DpdOpsMode,
): string {
  return `${stripe}+${dpd}`;
}
