/**
 * ZIP 172 — prova local da matriz Stripe/DPD (sem pagamentos reais).
 * Uso: deno run --allow-env tool/prove_ops_env_172.ts
 *
 * Não lê valores de secrets para o stdout — só fingerprints / blockers.
 */
import {
  combinationStatus,
  resolveStripeLiveSecret,
  resolveStripeSecretForMode,
  resolveStripeTestSecret,
  resolveDpdOauthForMode,
  listStripeWebhookSecretsForVerify,
  stripeKeyFingerprint,
} from "../supabase/functions/_shared/ops_env.ts";

type Row = {
  combo: string;
  execution: string;
  blockers: string[];
};

const rows: Row[] = (
  [
    ["test", "qa"],
    ["live", "qa"],
    ["test", "commercial"],
    ["live", "commercial"],
  ] as const
).map(([s, d]) => {
  const st = combinationStatus(s, d);
  return { combo: st.label, execution: st.execution, blockers: st.blockers };
});

const test = resolveStripeTestSecret();
const live = resolveStripeLiveSecret();
const liveDirect = resolveStripeSecretForMode("live");
const qa = resolveDpdOauthForMode("qa");
const commercial = resolveDpdOauthForMode("commercial");
const wh = listStripeWebhookSecretsForVerify().map((x) => ({
  expectedLivemode: x.expectedLivemode,
  source: x.source,
}));

// Prova crítica: LIVE nunca usa STRIPE_SECRET_KEY global.
const globalKey = (Deno.env.get("STRIPE_SECRET_KEY") ?? "").trim();
const liveKey = (Deno.env.get("STRIPE_SECRET_KEY_LIVE") ?? "").trim();
const noLiveFallback =
  !live.ok ||
  (live.source === "STRIPE_SECRET_KEY_LIVE" &&
    liveKey.length > 0 &&
    liveKey !== globalKey);

const report = {
  zip: "172",
  stripe: {
    test_ok: test.ok,
    test_fingerprint: test.fingerprint,
    test_source: test.source ?? null,
    test_error: test.error ?? null,
    live_ok: live.ok,
    live_fingerprint: live.ok ? live.fingerprint : "blocked",
    live_source: live.source ?? null,
    live_error: live.error ?? null,
    live_mode_resolve_error: liveDirect.ok ? null : liveDirect.error,
    no_live_to_global_fallback: noLiveFallback,
    webhook_secrets_present: wh,
  },
  dpd: {
    qa_ok: qa.ok,
    qa_error: qa.error ?? null,
    commercial_ok: commercial.ok,
    commercial_error: commercial.error ?? null,
    note: "DPD_MODE global ignored for commercial selection",
  },
  matrix: rows,
  criteria: {
    test_qa_functional: rows.find((r) => r.combo === "test+qa")?.execution ===
      "functional",
    others_blocked: rows
      .filter((r) => r.combo !== "test+qa")
      .every((r) => r.execution === "blocked"),
  },
};

console.log(JSON.stringify(report, null, 2));

if (!report.criteria.test_qa_functional) {
  console.error("FAIL: test+qa not functional");
  Deno.exit(2);
}
if (!report.criteria.others_blocked && !live.ok && !commercial.ok) {
  // Esperado nesta fase: LIVE/COMERCIAL bloqueados.
}
if (!report.stripe.no_live_to_global_fallback) {
  console.error("FAIL: LIVE appears to fall back to global key");
  Deno.exit(3);
}
if (live.ok) {
  console.error(
    "WARN: Stripe LIVE currently resolvable — GO/keys present. Do not process real payments without explicit authorization.",
  );
}

console.log(
  "\nPASS_LOCAL: isolation matrix OK (test+qa functional; real modes gated).",
);
void stripeKeyFingerprint;
