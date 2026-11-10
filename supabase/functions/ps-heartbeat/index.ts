import { buildCorsHeaders } from "../_shared/cors.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type HeartbeatBody = {
  live_id?: string;
  device_id?: string;
  status?: string;
  app_version?: string;
  last_error?: string;
  roi_ok?: boolean;
};

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

    const deviceToken =
      req.headers.get("x-device-token")?.trim() ??
      req.headers.get("X-Device-Token")?.trim() ??
      "";

    if (!deviceToken) {
      return jsonResponse({ ok: false, error: "missing_device_token" }, 401);
    }

    const body = (await req.json().catch(() => ({}))) as HeartbeatBody;
    const liveId = (body.live_id ?? "").trim();
    const deviceId = (body.device_id ?? "").trim();

    if (!liveId || !deviceId) {
      return jsonResponse({ ok: false, error: "missing_fields" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data, error } = await supabase.rpc("batata_ps_reader_heartbeat", {
      p_device_token: deviceToken,
      p_live_id: liveId,
      p_device_id: deviceId,
      p_status: (body.status ?? "online").trim(),
      p_app_version: (body.app_version ?? "").trim() || null,
      p_last_error: (body.last_error ?? "").trim() || null,
      p_roi_ok: body.roi_ok ?? null,
    });

    if (error) {
      return jsonResponse(
        { ok: false, error: error.message, code: error.code },
        500,
      );
    }

    return jsonResponse((data ?? {}) as Record<string, unknown>, 200);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return jsonResponse({ ok: false, error: msg }, 500);
  }
});
