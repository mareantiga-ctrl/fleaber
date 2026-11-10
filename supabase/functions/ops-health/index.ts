/**
 * ZIP 169-C1 — health + critical alerts (fail-closed, no PII/secrets in payloads).
 *
 * Auth: Bearer service_role OR header x-ops-health-secret == OPS_HEALTH_SECRET
 * Optional email: OPS_ALERT_EMAIL + RESEND_API_KEY + MAIL_FROM (only on critical / force_alert)
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { buildCorsHeaders } from "../_shared/cors.ts";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type Check = {
  id: string;
  severity: "ok" | "warn" | "critical";
  detail: string;
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function authorized(req: Request, serviceRole: string): boolean {
  const expected = (serviceRole ?? "").trim();
  const auth = (req.headers.get("Authorization") ?? "").trim();
  if (expected && auth === `Bearer ${expected}`) return true;
  const apiKey = (req.headers.get("apikey") ?? "").trim();
  if (expected && apiKey === expected) return true;
  const secret = (Deno.env.get("OPS_HEALTH_SECRET") ?? "").trim();
  const header = (req.headers.get("x-ops-health-secret") ?? "").trim();
  return secret.length > 0 && header === secret;
}

async function sendAlertEmail(
  subject: string,
  text: string,
): Promise<{ attempted: boolean; ok: boolean; ref?: string; error?: string }> {
  const to = (Deno.env.get("OPS_ALERT_EMAIL") ?? "").trim();
  const apiKey = (Deno.env.get("RESEND_API_KEY") ?? "").trim();
  const from = (Deno.env.get("MAIL_FROM") ?? "").trim();
  if (!to || !apiKey || !from) {
    return { attempted: false, ok: false, error: "alert_email_not_configured" };
  }
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [to],
        subject,
        text,
      }),
    });
    const body = await res.text();
    if (!res.ok) {
      return { attempted: true, ok: false, error: body.slice(0, 200) };
    }
    let ref = "";
    try {
      ref = String(JSON.parse(body).id ?? "");
    } catch {
      /* ignore */
    }
    return { attempted: true, ok: true, ref };
  } catch (e) {
    return { attempted: true, ok: false, error: String(e).slice(0, 200) };
  }
}

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    if (req.method !== "POST" && req.method !== "GET") {
      return json({ error: "Method not allowed." }, 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRole) {
      return json({ error: "Supabase config missing." }, 500);
    }
    if (!authorized(req, serviceRole)) {
      return json({ error: "Unauthorized." }, 401);
    }

    let forceAlert = false;
    let probeOnly = false;
    if (req.method === "POST") {
      try {
        const body = await req.json();
        forceAlert = body?.force_alert === true;
        probeOnly = body?.probe_only === true;
      } catch {
        /* empty body ok */
      }
    }

    const sb = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false },
    });

    const checks: Check[] = [];

    // 1) Zombie lives
    const { count: liveActive, error: liveErr } = await sb
      .from("lives")
      .select("id", { count: "exact", head: true })
      .or("is_active.eq.true,status.eq.live");
    if (liveErr) {
      checks.push({
        id: "lives_query",
        severity: "critical",
        detail: "lives_query_failed",
      });
    } else {
      const n = liveActive ?? 0;
      checks.push({
        id: "lives_active",
        severity: n > 5 ? "warn" : "ok",
        detail: `active_or_live=${n}`,
      });
    }

    // 2) Stale egress markers on ended lives
    const { count: staleEgress, error: egErr } = await sb
      .from("lives")
      .select("id", { count: "exact", head: true })
      .eq("status", "ended")
      .not("livekit_egress_id", "is", null);
    if (egErr) {
      checks.push({
        id: "egress_query",
        severity: "warn",
        detail: "egress_query_failed",
      });
    } else {
      const n = staleEgress ?? 0;
      checks.push({
        id: "ended_with_egress_id",
        severity: n > 0 ? "warn" : "ok",
        detail: `count=${n}`,
      });
    }

    // 3) Hub reachability (no body scrape of PII)
    let hubOk = false;
    try {
      const hubRes = await fetch("https://fleaber.pt/fleahub/", {
        method: "GET",
        redirect: "follow",
        signal: AbortSignal.timeout(12000),
      });
      hubOk = hubRes.status >= 200 && hubRes.status < 500;
      checks.push({
        id: "hub_web",
        severity: hubOk ? "ok" : "critical",
        detail: `http=${hubRes.status}`,
      });
    } catch {
      checks.push({
        id: "hub_web",
        severity: "critical",
        detail: "hub_unreachable",
      });
    }

    // 4) Edge commercial flags (env) — must stay OFF until authorized.
    const dpdTrackEnv = (Deno.env.get("DPD_TRACKING_SYNC_ENABLED") ?? "0").trim();
    const dpdCreateEnv = (Deno.env.get("DPD_QA_CREATE_ENABLED") ?? "0").trim();
    checks.push({
      id: "flag_dpd_tracking_env",
      severity: dpdTrackEnv === "1" || dpdTrackEnv.toLowerCase() === "true"
        ? "warn"
        : "ok",
      detail: `DPD_TRACKING_SYNC_ENABLED=${dpdTrackEnv || "0"}`,
    });
    checks.push({
      id: "flag_dpd_create_env",
      severity: dpdCreateEnv === "1" || dpdCreateEnv.toLowerCase() === "true"
        ? "warn"
        : "ok",
      detail: `DPD_QA_CREATE_ENABLED=${dpdCreateEnv || "0"}`,
    });

    // 5) Stripe webhook edge reachable (signature required → 400 expected)
    try {
      const wh = await fetch(`${supabaseUrl}/functions/v1/stripe-webhook`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
        signal: AbortSignal.timeout(10000),
      });
      // missing signature should not be 5xx
      checks.push({
        id: "stripe_webhook_edge",
        severity: wh.status < 500 ? "ok" : "critical",
        detail: `http=${wh.status}`,
      });
    } catch {
      checks.push({
        id: "stripe_webhook_edge",
        severity: "critical",
        detail: "unreachable",
      });
    }

    const critical = checks.filter((c) => c.severity === "critical");
    const warn = checks.filter((c) => c.severity === "warn");
    const status = critical.length
      ? "critical"
      : warn.length
      ? "warn"
      : "ok";

    const snapshot = {
      ok: status === "ok",
      status,
      ts: new Date().toISOString(),
      checks,
      note: "No secrets/PII in checks; ZIP169 ops-health",
    };

    if (!probeOnly) {
      await sb.from("app_logs").insert({
        category: "ops_health",
        error_message: `ops-health ${status}`,
        device_info: snapshot,
      }).then(() => {}).catch(() => {});

      // Best-effort dedicated table (created by migration SQL)
      await sb.from("ops_health_snapshots").insert({
        status,
        payload: snapshot,
      }).then(() => {}).catch(() => {});
    }

    let email:
      | { attempted: boolean; ok: boolean; ref?: string; error?: string }
      | undefined;
    if (forceAlert || critical.length > 0) {
      const text = [
        `Fleaber ops-health: ${status}`,
        `ts: ${snapshot.ts}`,
        ...checks.map((c) => `- [${c.severity}] ${c.id}: ${c.detail}`),
        "",
        "(sem tokens/passwords/PII)",
      ].join("\n");
      email = await sendAlertEmail(
        forceAlert
          ? `[Fleaber][TEST] ops-health ${status}`
          : `[Fleaber][CRITICAL] ops-health`,
        text,
      );
    }

    return json({
      ...snapshot,
      email,
    });
  } catch (e) {
    console.error("ops-health", String(e).slice(0, 200));
    return json({ error: "ops_health_failed" }, 500);
  }
});
