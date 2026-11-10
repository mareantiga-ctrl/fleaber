/**
 * ZIP 174 — auditoria de ambientes Stripe/DPD (sem valores de secrets).
 * Auth: Bearer service_role OU x-ops-health-secret == OPS_HEALTH_SECRET
 * Não chama Stripe LIVE nem DPD comercial. Não cria pagamentos/etiquetas.
 */
import {
  combinationStatus,
  isStripeLiveGlobalGo,
  isStripeLivePilotEnabled,
  isStripeLivePilotMoneyGo,
  listStripeWebhookSecretsForVerify,
  resolveDpdOauthForMode,
  resolveStripeLiveSecret,
  resolveStripeTestSecret,
  stripeKeyFingerprint,
  stripeLivePilotConfig,
} from "../_shared/ops_env.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-ops-health-secret",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function goOn(name: string): boolean {
  const v = (Deno.env.get(name) ?? "").trim().toLowerCase();
  return v === "1" || v === "true" || v === "yes";
}

function present(name: string): boolean {
  return (Deno.env.get(name) ?? "").trim().length > 0;
}

function authorized(req: Request): boolean {
  const service = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const auth = (req.headers.get("Authorization") ?? "").trim();
  if (service && auth === `Bearer ${service}`) return true;
  const secret = (Deno.env.get("OPS_HEALTH_SECRET") ?? "").trim();
  const hdr = (req.headers.get("x-ops-health-secret") ?? "").trim();
  return secret.length > 0 && hdr === secret;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "GET" && req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }
  if (!authorized(req)) {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  const test = resolveStripeTestSecret();
  const live = resolveStripeLiveSecret();
  const qa = resolveDpdOauthForMode("qa");
  const commercial = resolveDpdOauthForMode("commercial");
  const wh = listStripeWebhookSecretsForVerify().map((x) => ({
    expected_livemode: x.expectedLivemode,
    source: x.source,
  }));

  const globalFp = stripeKeyFingerprint(Deno.env.get("STRIPE_SECRET_KEY") ?? "");
  const liveKeyPresent = present("STRIPE_SECRET_KEY_LIVE");
  const liveWhPresent = present("STRIPE_WEBHOOK_SECRET_LIVE");

  const matrix = (
    [
      ["test", "qa"],
      ["live", "qa"],
      ["test", "commercial"],
      ["live", "commercial"],
    ] as const
  ).map(([s, d]) => combinationStatus(s, d));

  return json({
    ok: true,
    zip: "174",
    stripe: {
      test: {
        resolvable: test.ok,
        fingerprint: test.fingerprint,
        source: test.source ?? null,
        error: test.error ?? null,
      },
      live: {
        key_present: liveKeyPresent,
        webhook_secret_present: liveWhPresent,
        webhook_connect_secret_present: present("STRIPE_WEBHOOK_SECRET_LIVE_CONNECT"),
        go_on: goOn("OPS_STRIPE_LIVE_GO"),
        resolvable: live.ok,
        fingerprint: live.ok ? live.fingerprint : "blocked",
        source: live.source ?? null,
        error: live.error ?? null,
      },
      global_secret_fingerprint: globalFp,
      no_live_fallback_to_global: !live.ok || live.source === "STRIPE_SECRET_KEY_LIVE",
      webhook_secrets_for_verify: wh,
      endpoints: {
        webhook_edge:
          "https://bpmpkzwnrbmuqnhgdscf.supabase.co/functions/v1/stripe-webhook",
        note:
          "LIVE deve usar endpoint Dashboard separado + STRIPE_WEBHOOK_SECRET_LIVE",
      },
    },
    dpd: {
      qa: {
        oauth_complete: qa.ok,
        error: qa.error ?? null,
        create_enabled_flag: goOn("DPD_QA_CREATE_ENABLED") ||
          (Deno.env.get("DPD_QA_CREATE_ENABLED") ?? "").trim() === "1",
        base: "https://qabusiness.dpd.pt",
      },
      commercial: {
        username_present: present("DPD_LIVE_USERNAME"),
        password_present: present("DPD_LIVE_PASSWORD"),
        client_id_present: present("DPD_LIVE_CLIENT_ID"),
        client_secret_present: present("DPD_LIVE_CLIENT_SECRET"),
        go_on: goOn("OPS_DPD_COMMERCIAL_GO"),
        create_enabled: goOn("DPD_LIVE_CREATE_ENABLED"),
        oauth_resolvable: commercial.ok,
        error: commercial.error ?? null,
        base: "https://business.dpd.pt",
      },
      proxy: {
        url_present: present("DPD_PROXY_URL"),
        bearer_present: present("DPD_PROXY_BEARER"),
        documented_egress_ip: "135.125.254.159",
        documented_allowlist_note:
          "VPS FLEABER_DPD_ALLOWED_HOSTS historically QA-only; add business.dpd.pt only with GO",
      },
      dpd_mode_global_present: present("DPD_MODE"),
      note: "ZIP172: DPD_MODE global ignored for commercial selection",
    },
    gates: {
      OPS_STRIPE_LIVE_GO: goOn("OPS_STRIPE_LIVE_GO"),
      OPS_STRIPE_LIVE_PILOT_ENABLED: isStripeLivePilotEnabled(),
      OPS_STRIPE_LIVE_PILOT_MONEY_GO: isStripeLivePilotMoneyGo(),
      OPS_DPD_COMMERCIAL_GO: goOn("OPS_DPD_COMMERCIAL_GO"),
      DPD_LIVE_CREATE_ENABLED: goOn("DPD_LIVE_CREATE_ENABLED"),
      DPD_TRACKING_SYNC_ENABLED: goOn("DPD_TRACKING_SYNC_ENABLED"),
    },
    pilot_zip181: (() => {
      const p = stripeLivePilotConfig();
      return {
        enabled: p.enabled,
        money_go: p.moneyGo,
        max_total_cents: p.maxTotalCents,
        seller_allowlist_count: p.sellerIds.size,
        buyer_allowlist_count: p.buyerIds.size,
        global_go: isStripeLiveGlobalGo(),
        note:
          "Piloto ≠ GO global. Checkout/transfer exigem allowlist + MONEY_GO.",
      };
    })(),
    matrix,
    red_teams_ready_structurally: true,
    real_ops_blocked: !goOn("OPS_STRIPE_LIVE_GO") &&
      !isStripeLivePilotMoneyGo() &&
      !goOn("OPS_DPD_COMMERCIAL_GO") &&
      !goOn("DPD_LIVE_CREATE_ENABLED"),
  });
});
