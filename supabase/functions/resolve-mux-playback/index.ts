import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

type ResolveMuxPlaybackRequest = {
  live_id?: string;
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

async function muxGet(path: string, muxTokenId: string, muxTokenSecret: string) {
  const res = await fetch(`https://api.mux.com${path}`, {
    headers: {
      Authorization: `Basic ${btoa(`${muxTokenId}:${muxTokenSecret}`)}`,
    },
  });
  const body = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, body };
}

function playbackIdFromAsset(asset: Record<string, unknown>): string {
  const ids = asset?.playback_ids as Array<Record<string, unknown>> | undefined;
  const first = ids?.[0]?.id;
  return typeof first === "string" ? first : "";
}

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed." }, 405);
    }

    const muxTokenId = Deno.env.get("MUX_TOKEN_ID");
    const muxTokenSecret = Deno.env.get("MUX_TOKEN_SECRET");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authHeader = req.headers.get("Authorization") ?? "";

    if (!muxTokenId || !muxTokenSecret || !supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Config em falta no servidor." }, 500);
    }

    const body = (await req.json().catch(() => ({}))) as ResolveMuxPlaybackRequest;
    const liveId = (body.live_id ?? "").trim();
    if (!liveId) {
      return jsonResponse({ error: "live_id obrigatório." }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Hub anon OK: só devolve playback IDs públicos (nunca stream keys).
    void authHeader;

    const { data: live, error: liveError } = await supabase
      .from("lives")
      .select(
        "id, status, is_active, mux_live_id, mux_playback_id, mux_vod_playback_id, mux_asset_id",
      )
      .eq("id", liveId)
      .maybeSingle();

    if (liveError || !live) {
      return jsonResponse({ error: "Live não encontrada." }, 404);
    }

    const vodCached = (live.mux_vod_playback_id ?? "").trim();
    const ended = live.status === "ended" || live.is_active === false;

    // VOD só quando o directo já terminou — senão preferir stream live.
    if (vodCached && ended) {
      return jsonResponse({
        playback_id: vodCached,
        playback_url: `https://stream.mux.com/${vodCached}.m3u8`,
        source: "cache",
        is_live: false,
      });
    }

    const muxLiveId = (live.mux_live_id ?? "").trim();
    const livePlayback = (live.mux_playback_id ?? "").trim();

    // Directo activo: devolver HLS live de imediato (não esperar asset VOD).
    if (!ended && livePlayback) {
      return jsonResponse({
        playback_id: livePlayback,
        playback_url:
          `https://stream.mux.com/${livePlayback}.m3u8?reduced_latency=true`,
        source: "live_active",
        is_live: true,
      });
    }

    // SEC-016: rate-limit chamadas Mux API por live (custo / spam).
    const rate = await checkAnonRate(
      supabase,
      `mux_resolve:${liveId}`,
      "resolve-mux-playback",
      30,
    );
    if (rate.rateLimited) {
      if (livePlayback) {
        return jsonResponse({
          playback_id: livePlayback,
          playback_url: `https://stream.mux.com/${livePlayback}.m3u8`,
          source: "rate_limited_fallback",
          is_live: !ended,
          note: "rate_limited",
        });
      }
      return jsonResponse(
        { error: "Demasiados pedidos. Tenta daqui a pouco.", source: "rate_limited" },
        429,
      );
    }

    if (!muxLiveId) {
      if (livePlayback) {
        return jsonResponse({
          playback_id: livePlayback,
          playback_url: `https://stream.mux.com/${livePlayback}.m3u8`,
          source: "live_playback_only",
          is_live: live.status === "live",
        });
      }
      return jsonResponse({ error: "mux_live_id em falta." }, 400);
    }

    const streamRes = await muxGet(
      `/video/v1/live-streams/${muxLiveId}`,
      muxTokenId,
      muxTokenSecret,
    );
    if (!streamRes.ok) {
      return jsonResponse(
        { error: "Mux live stream indisponível.", mux_status: streamRes.status },
        502,
      );
    }

    const streamData = (streamRes.body?.data ?? {}) as Record<string, unknown>;
    let assetId = (streamData.active_asset_id as string | undefined)?.trim() ?? "";

    const recent = streamData.recent_asset_ids as string[] | undefined;
    if (!assetId && recent?.length) {
      assetId = recent[recent.length - 1]?.trim() ?? "";
    }

    let assetPlayback = "";
    let assetStatus = "";
    const maxAttempts = 10;
    const delayMs = 500;

    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      if (!assetId) {
        const streamRetry = await muxGet(
          `/video/v1/live-streams/${muxLiveId}`,
          muxTokenId,
          muxTokenSecret,
        );
        if (streamRetry.ok) {
          const streamData = (streamRetry.body?.data ?? {}) as Record<
            string,
            unknown
          >;
          assetId =
            (streamData.active_asset_id as string | undefined)?.trim() ?? "";
          const recent = streamData.recent_asset_ids as string[] | undefined;
          if (!assetId && recent?.length) {
            assetId = recent[recent.length - 1]?.trim() ?? "";
          }
        }
        if (!assetId) {
          const listRes = await muxGet(
            `/video/v1/assets?live_stream_id=${muxLiveId}&limit=1`,
            muxTokenId,
            muxTokenSecret,
          );
          const list = listRes.body?.data as
            | Array<Record<string, unknown>>
            | undefined;
          assetId = (list?.[0]?.id as string | undefined)?.trim() ?? "";
        }
      }

      if (assetId) {
        const assetRes = await muxGet(
          `/video/v1/assets/${assetId}`,
          muxTokenId,
          muxTokenSecret,
        );
        if (assetRes.ok) {
          const asset = assetRes.body?.data as Record<string, unknown>;
          assetStatus = (asset?.status as string | undefined) ?? "";
          assetPlayback = playbackIdFromAsset(asset);
          if (
            assetPlayback &&
            (assetStatus === "ready" || assetStatus === "preparing" || !ended)
          ) {
            break;
          }
        }
      }

      assetId = "";
      assetPlayback = "";
      if (attempt < maxAttempts - 1) {
        await new Promise((r) => setTimeout(r, delayMs));
      }
    }

    if (!assetId || !assetPlayback) {
      if (livePlayback) {
        return jsonResponse({
          playback_id: livePlayback,
          playback_url: `https://stream.mux.com/${livePlayback}.m3u8`,
          source: "live_playback_fallback",
          is_live: !ended,
          note: "asset_not_ready",
        });
      }
      return jsonResponse(
        {
          error: "Asset VOD ainda não criado no Mux.",
          source: "asset_missing",
          is_live: false,
        },
        404,
      );
    }

    // SEC-016: nunca sobrescrever VOD já gravado (só preencher se null).
    if (!vodCached) {
      await supabase
        .from("lives")
        .update({
          mux_asset_id: assetId,
          mux_vod_playback_id: assetPlayback,
        })
        .eq("id", liveId)
        .is("mux_vod_playback_id", null);
    }

    return jsonResponse({
      playback_id: assetPlayback,
      playback_url: `https://stream.mux.com/${assetPlayback}.m3u8`,
      asset_id: assetId,
      source: "mux_asset",
      is_live: false,
      asset_status: assetStatus,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error.";
    return jsonResponse({ error: message }, 500);
  }
});
