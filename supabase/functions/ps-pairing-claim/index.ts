import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type ClaimBody = {
  code?: string;
  device_id?: string;
  app_version?: string;
};

function clientIp(req: Request): string {
  const xf = (req.headers.get("x-forwarded-for") ?? "").split(",")[0]?.trim() ?? "";
  const real = (req.headers.get("x-real-ip") ?? "").trim();
  const cf = (req.headers.get("cf-connecting-ip") ?? "").trim();
  const ip = cf || real || xf;
  if (!ip || ip.length > 64) return "unknown";
  return ip.toLowerCase();
}

function hubLiveUrl(handle: string, liveId: string): string {
  const h = handle.trim().toLowerCase().replace(/^\/+|\/+$/g, "");
  const id = liveId.trim();
  if (!h || !id) return "";
  return `https://fleaber.pt/fleahub/index.html#/${h}/live?liveId=${encodeURIComponent(id)}`;
}

async function enrichHubLink(
  supabase: ReturnType<typeof createClient>,
  result: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const sellerId = String(result.seller_id ?? "").trim();
  const liveId = String(result.live_id ?? "").trim();
  if (!sellerId || !liveId) return result;

  const { data: prof } = await supabase
    .from("profiles")
    .select("handle, handle_suggested")
    .eq("id", sellerId)
    .maybeSingle();

  const handle = String(prof?.handle ?? prof?.handle_suggested ?? "").trim();
  if (!handle) return result;

  const url = hubLiveUrl(handle, liveId);
  const ctx =
    result.live_context && typeof result.live_context === "object"
      ? { ...(result.live_context as Record<string, unknown>) }
      : {};

  ctx.seller_handle = handle;
  ctx.hub_live_url = url;

  return {
    ...result,
    seller_handle: handle,
    hub_live_url: url,
    live_context: ctx,
  };
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ ok: false, error: "server_config" }, 500);
    }

    const body = (await req.json().catch(() => ({}))) as ClaimBody;
    const code = (body.code ?? "").trim();
    const deviceId = (body.device_id ?? "ps-reader-pc").trim();
    const appVersion = (body.app_version ?? "").trim();
    const ip = clientIp(req);

    if (code.length !== 6 || !/^\d{6}$/.test(code)) {
      return jsonResponse({ ok: false, error: "invalid_code" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // RTBB-B-03: rate na Edge por IP (não pelo device_id do body).
    const edgeRate = await checkAnonRate(
      supabase,
      `ps_pairing_claim_edge:ip:${ip}`,
      "ps-pairing-claim",
      40,
    );
    if (edgeRate.rateLimited) {
      return jsonResponse(
        { ok: false, error: "rate_limited", scope: "ip_edge" },
        429,
      );
    }

    const { data, error } = await supabase.rpc("batata_ps_claim_pairing", {
      p_code: code,
      p_device_id: deviceId,
      p_app_version: appVersion || null,
      p_client_ip: ip,
    });

    if (error) {
      return jsonResponse(
        { ok: false, error: error.message, code: error.code },
        500,
      );
    }

    const result = (data ?? {}) as Record<string, unknown>;
    if (result.ok === false) {
      const status = result.error === "rate_limited" ? 429 : 400;
      return jsonResponse(result, status);
    }

    const enriched = await enrichHubLink(supabase, result);

    return jsonResponse({
      ...enriched,
      supabase_url: supabaseUrl,
    }, 200);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return jsonResponse({ ok: false, error: msg }, 500);
  }
});
