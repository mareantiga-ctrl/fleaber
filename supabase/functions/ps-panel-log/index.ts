import { buildCorsHeaders } from "../_shared/cors.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type PanelLogBody = {
  live_id?: string;
  device_id?: string;
  event_kind?: string;
  message?: string;
  detail?: string;
  meta?: Record<string, unknown>;
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

    const body = (await req.json().catch(() => ({}))) as PanelLogBody;
    const liveId = (body.live_id ?? "").trim();
    if (!liveId) {
      return jsonResponse({ ok: false, error: "missing_live_id" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data, error } = await supabase.rpc("batata_ps_panel_log", {
      p_device_token: deviceToken,
      p_live_id: liveId,
      p_device_id: (body.device_id ?? "").trim() || null,
      p_event_kind: (body.event_kind ?? "info").trim() || "info",
      p_message: (body.message ?? "").trim(),
      p_detail: (body.detail ?? "").trim() || null,
      p_meta: body.meta ?? null,
    });

    if (error) {
      return jsonResponse(
        { ok: false, error: error.message, code: error.code },
        500,
      );
    }

    const result = (data ?? {}) as Record<string, unknown>;
    if (result.ok === false) {
      const err = String(result.error ?? "panel_log_failed");
      const status = err === "invalid_token" ? 401 : 400;
      return jsonResponse(result, status);
    }

    return jsonResponse(result, 200);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return jsonResponse({ ok: false, error: msg }, 500);
  }
});
