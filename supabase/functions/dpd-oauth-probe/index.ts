/**
 * ZIP 189 — OAuth probe QA/PROD (token only). Never returns the token.
 * Create/collect/fecho: not available here.
 */
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { dpdOauthTokenForMode } from "../_shared/dpd_client.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);

  let mode: "qa" | "commercial" = "qa";
  try {
    const body = await req.json();
    const raw = String(body?.mode ?? "qa").trim().toLowerCase();
    if (raw === "commercial" || raw === "live" || raw === "prod") {
      mode = "commercial";
    }
  } catch {
    // default qa
  }

  // PROD probe uses DPD_LIVE_* directly (GO not required for oauth-only).
  // Create remains gated by DPD_LIVE_CREATE_ENABLED / OPS_DPD_COMMERCIAL_GO elsewhere.
  try {
    if (mode === "commercial") {
      const username = (Deno.env.get("DPD_LIVE_USERNAME") ?? "").trim();
      const password = (Deno.env.get("DPD_LIVE_PASSWORD") ?? "").trim();
      const clientId = (Deno.env.get("DPD_LIVE_CLIENT_ID") ?? "").trim();
      const clientSecret = (Deno.env.get("DPD_LIVE_CLIENT_SECRET") ?? "").trim();
      const baseUrl =
        (Deno.env.get("DPD_LIVE_BASE") ?? "").trim() ||
        "https://business.dpd.pt";
      if (!username || !password || !clientId || !clientSecret) {
        return json({
          ok: false,
          mode,
          error: "dpd_live_credentials_missing",
          create_enabled: Deno.env.get("DPD_LIVE_CREATE_ENABLED") === "1",
          commercial_go: ["1", "true", "yes"].includes(
            (Deno.env.get("OPS_DPD_COMMERCIAL_GO") ?? "").toLowerCase(),
          ),
        }, 400);
      }
      const { dpdForward } = await import("../_shared/dpd_client.ts");
      const body = new URLSearchParams({
        username,
        password,
        client_id: clientId,
        client_secret: clientSecret,
        grant_type: "password",
      }).toString();
      const fwd = await dpdForward({
        url: `${baseUrl}/api/v1/pt/oauth/token`,
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body,
      });
      let hasToken = false;
      let expiresIn: number | null = null;
      let tokenType: string | null = null;
      try {
        const j = JSON.parse(fwd.bodyText) as {
          result?: {
            access_token?: string;
            expires_in?: number | string;
            token_type?: string;
          };
        };
        hasToken = Boolean(j.result?.access_token);
        const exp = j.result?.expires_in;
        if (typeof exp === "number") expiresIn = exp;
        else if (typeof exp === "string" && exp.trim()) {
          const n = Number(exp);
          expiresIn = Number.isFinite(n) ? n : null;
        }
        if (typeof j.result?.token_type === "string") {
          tokenType = j.result.token_type;
        }
      } catch {
        hasToken = false;
      }
      return json({
        ok: fwd.ok && hasToken,
        mode,
        oauth_http: fwd.status,
        has_access_token: hasToken,
        expires_in_sec: expiresIn,
        token_type: tokenType,
        // Renewal = fresh password-grant each call (no shared cache in Edge).
        renewal: "password_grant_per_call",
        create_enabled: Deno.env.get("DPD_LIVE_CREATE_ENABLED") === "1",
        commercial_go: ["1", "true", "yes"].includes(
          (Deno.env.get("OPS_DPD_COMMERCIAL_GO") ?? "").toLowerCase(),
        ),
        body_snip: hasToken
          ? undefined
          : (fwd.bodyText ?? "").slice(0, 180),
      });
    }

    const token = await dpdOauthTokenForMode("qa");
    return json({
      ok: Boolean(token),
      mode: "qa",
      has_access_token: Boolean(token),
      create_enabled: Deno.env.get("DPD_QA_CREATE_ENABLED") === "1",
    });
  } catch (e) {
    return json({
      ok: false,
      mode,
      error: String(e).slice(0, 200),
      create_enabled: mode === "commercial"
        ? Deno.env.get("DPD_LIVE_CREATE_ENABLED") === "1"
        : Deno.env.get("DPD_QA_CREATE_ENABLED") === "1",
      commercial_go: ["1", "true", "yes"].includes(
        (Deno.env.get("OPS_DPD_COMMERCIAL_GO") ?? "").toLowerCase(),
      ),
    }, 500);
  }
});
