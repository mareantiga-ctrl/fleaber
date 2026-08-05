import { buildCorsHeaders } from "../_shared/cors.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type CreateMuxLiveRequest = {
  title?: string;
};

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

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
      return jsonResponse({ error: "Method not allowed.", step: "method" }, 405);
    }

    const muxTokenId = Deno.env.get("MUX_TOKEN_ID");
    const muxTokenSecret = Deno.env.get("MUX_TOKEN_SECRET");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authHeader = req.headers.get("Authorization") ?? "";

    if (!muxTokenId || !muxTokenSecret) {
      return jsonResponse(
        {
          error: "Credenciais Mux em falta no servidor (MUX_TOKEN_ID/SECRET).",
          step: "config",
        },
        500,
      );
    }
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse(
        { error: "Credenciais Supabase em falta no servidor.", step: "config" },
        500,
      );
    }
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return jsonResponse({ error: "Missing authenticated user.", step: "auth" }, 401);
    }

    const body = (await req.json().catch(() => ({}))) as CreateMuxLiveRequest;
    const title = (body.title ?? "").trim();
    if (title.length < 3) {
      return jsonResponse({ error: "O título do direto é obrigatório.", step: "validation" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    const { data: userData, error: userError } = await supabase.auth.getUser(jwt);
    if (userError || !userData.user?.id) {
      return jsonResponse(
        { error: userError?.message ?? "Utilizador inválido.", step: "auth" },
        401,
      );
    }

    // SEC-017: quota diária de creates Mux (custo) — BATATA: não bloqueia 1.º directo.
    const uid = userData.user.id;
    const sinceIso = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const maxMuxCreatesPerDay = 10;
    const { count: muxCreatesToday, error: quotaError } = await supabase
      .from("lives")
      .select("id", { count: "exact", head: true })
      .or(`seller_id.eq.${uid},vendedor_id.eq.${uid}`)
      .not("mux_live_id", "is", null)
      .gte("created_at", sinceIso);
    if (quotaError) {
      console.warn("create-mux-live quota check failed (continue)", quotaError.message);
    } else if ((muxCreatesToday ?? 0) >= maxMuxCreatesPerDay) {
      return jsonResponse(
        {
          error:
            "Limite diário de diretos Mux atingido. Tenta amanhã ou contacta suporte.",
          step: "quota",
          max_per_day: maxMuxCreatesPerDay,
        },
        429,
      );
    }

    const muxResponse = await fetch("https://api.mux.com/video/v1/live-streams", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${btoa(`${muxTokenId}:${muxTokenSecret}`)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        playback_policy: ["public"],
        new_asset_settings: { playback_policy: ["public"] },
        reduced_latency: true,
      }),
    });

    const muxBody = await muxResponse.json().catch(() => ({}));
    if (!muxResponse.ok) {
      const message =
        muxBody?.error?.messages?.join?.("; ") ??
        muxBody?.error?.message ??
        muxBody?.error?.type ??
        JSON.stringify(muxBody?.error ?? muxBody);
      console.error("create-mux-live mux failed", muxResponse.status, message);
      return jsonResponse(
        {
          error: `Mux API: ${message}`,
          step: "mux",
          mux_status: muxResponse.status,
        },
        502,
      );
    }

    const muxData = muxBody?.data ?? {};
    const muxLiveId = muxData.id?.toString() ?? "";
    const streamKey = muxData.stream_key?.toString() ?? "";
    const playbackId = muxData.playback_ids?.[0]?.id?.toString() ?? "";

    if (!muxLiveId || !streamKey || !playbackId) {
      return jsonResponse(
        {
          error: "Mux response missing live id, stream key or playback id.",
          step: "mux_parse",
        },
        502,
      );
    }

    // Só «AO VIVO» / is_active no go-live (egress/RTMP). Create = preparar Mux.
    // Antes: is_active=true aqui → Hub/Admin Lab mostravam directo sem sinal Mux.
    const insertPayload: Record<string, unknown> = {
      title,
      status: "scheduled",
      is_active: false,
      vendedor_id: userData.user.id,
      mux_live_id: muxLiveId,
      mux_stream_key: streamKey,
      stream_key: streamKey,
      mux_playback_id: playbackId,
      playback_id: playbackId,
    };

    // Coluna opcional (alguns schemas só têm vendedor_id).
    insertPayload.seller_id = userData.user.id;

    const { data: live, error: liveError } = await supabase
      .from("lives")
      .insert(insertPayload)
      .select()
      .single();

    if (liveError) {
      console.error("create-mux-live lives insert failed", liveError);
      return jsonResponse(
        {
          error: `Base de dados: ${liveError.message}`,
          step: "database",
          db_code: liveError.code,
        },
        500,
      );
    }

    return jsonResponse({
      live,
      mux_live_id: muxLiveId,
      stream_key: streamKey,
      playback_id: playbackId,
      rtmp_url: "rtmp://global-live.mux.com:5222/app",
      playback_url: `https://stream.mux.com/${playbackId}.m3u8?reduced_latency=true`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error.";
    console.error("create-mux-live unhandled", message);
    return jsonResponse({ error: message, step: "unhandled" }, 500);
  }
});
