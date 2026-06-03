import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  stopAllActiveEgressForRoom,
  stopLivekitEgressById,
} from "../_shared/livekit_egress_helpers.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type CompleteMuxLiveRequest = {
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

function roomNameForLive(liveId: string) {
  const safe = liveId.replace(/[^a-zA-Z0-9_-]/g, "");
  return `fleaber_${safe}`;
}

async function stopLivekitForLive(
  livekitUrl: string,
  apiKey: string,
  apiSecret: string,
  liveId: string,
  egressId: string,
  roomName: string,
) {
  const room = roomName.trim() || roomNameForLive(liveId);
  const cleanup = await stopAllActiveEgressForRoom(
    livekitUrl,
    apiKey,
    apiSecret,
    room,
  );
  const id = egressId.trim();
  if (id) {
    await stopLivekitEgressById(livekitUrl, apiKey, apiSecret, id);
  }
  console.log(
    "complete-mux-live stop_egress",
    liveId,
    "room=",
    room,
    "stopped=",
    cleanup.stopped.length,
    "active_before=",
    cleanup.active_before,
  );
  return cleanup;
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

async function resolveAssetPlayback(
  muxLiveId: string,
  muxTokenId: string,
  muxTokenSecret: string,
): Promise<{ assetId: string; playbackId: string } | null> {
  for (let i = 0; i < 8; i++) {
    const streamRes = await muxGet(
      `/video/v1/live-streams/${muxLiveId}`,
      muxTokenId,
      muxTokenSecret,
    );
    if (streamRes.ok) {
      const streamData = (streamRes.body?.data ?? {}) as Record<string, unknown>;
      let assetId =
        (streamData.active_asset_id as string | undefined)?.trim() ?? "";
      const recent = streamData.recent_asset_ids as string[] | undefined;
      if (!assetId && recent?.length) {
        assetId = recent[recent.length - 1]?.trim() ?? "";
      }

      if (assetId) {
        const assetRes = await muxGet(
          `/video/v1/assets/${assetId}`,
          muxTokenId,
          muxTokenSecret,
        );
        if (assetRes.ok) {
          const asset = assetRes.body?.data as Record<string, unknown>;
          const status = (asset?.status as string | undefined) ?? "";
          const playbackId = playbackIdFromAsset(asset);
          if (playbackId && (status === "ready" || status === "preparing")) {
            return { assetId, playbackId };
          }
        }
      }
    }

    const listRes = await muxGet(
      `/video/v1/assets?live_stream_id=${muxLiveId}&limit=3`,
      muxTokenId,
      muxTokenSecret,
    );
    const list = listRes.body?.data as Array<Record<string, unknown>> | undefined;
    if (list?.length) {
      const latest = list[0];
      const assetId = (latest?.id as string | undefined)?.trim() ?? "";
      const playbackId = playbackIdFromAsset(latest);
      if (assetId && playbackId) {
        return { assetId, playbackId };
      }
    }

    await new Promise((r) => setTimeout(r, 3000));
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed.", step: "method" }, 405);
    }

    const muxTokenId = Deno.env.get("MUX_TOKEN_ID");
    const muxTokenSecret = Deno.env.get("MUX_TOKEN_SECRET");
    const livekitUrl = Deno.env.get("LIVEKIT_URL");
    const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY");
    const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authHeader = req.headers.get("Authorization") ?? "";

    if (!muxTokenId || !muxTokenSecret) {
      return jsonResponse(
        { error: "Credenciais Mux em falta no servidor.", step: "config" },
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

    const body = (await req.json().catch(() => ({}))) as CompleteMuxLiveRequest;
    const liveId = (body.live_id ?? "").trim();
    if (!liveId) {
      return jsonResponse({ error: "live_id é obrigatório.", step: "validation" }, 400);
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

    const { data: live, error: liveError } = await supabase
      .from("lives")
      .select(
        "id, vendedor_id, seller_id, mux_live_id, livekit_egress_id, livekit_room_name",
      )
      .eq("id", liveId)
      .maybeSingle();

    if (liveError || !live) {
      return jsonResponse(
        { error: liveError?.message ?? "Live não encontrada.", step: "database" },
        404,
      );
    }

    const ownerId = live.seller_id ?? live.vendedor_id;
    if (ownerId !== userData.user.id) {
      return jsonResponse({ error: "Sem permissão para esta live.", step: "auth" }, 403);
    }

    const muxLiveId = (live.mux_live_id ?? "").trim();
    if (!muxLiveId) {
      return jsonResponse(
        { error: "mux_live_id em falta nesta live.", step: "validation" },
        400,
      );
    }

    let livekitCleanup: { stopped: string[]; active_before: number } | null =
      null;
    if (livekitUrl && livekitApiKey && livekitApiSecret) {
      livekitCleanup = await stopLivekitForLive(
        livekitUrl,
        livekitApiKey,
        livekitApiSecret,
        liveId,
        (live.livekit_egress_id ?? "").toString(),
        (live.livekit_room_name ?? "").toString(),
      );
      await supabase
        .from("lives")
        .update({ livekit_egress_id: null })
        .eq("id", liveId);
    } else {
      console.warn("complete-mux-live: LiveKit config missing — egress not stopped");
    }

    const muxResponse = await fetch(
      `https://api.mux.com/video/v1/live-streams/${muxLiveId}/complete`,
      {
        method: "PUT",
        headers: {
          Authorization: `Basic ${btoa(`${muxTokenId}:${muxTokenSecret}`)}`,
          "Content-Type": "application/json",
        },
      },
    );

    const muxBody = await muxResponse.json().catch(() => ({}));
    if (!muxResponse.ok) {
      const message =
        muxBody?.error?.messages?.join?.("; ") ??
        muxBody?.error?.message ??
        JSON.stringify(muxBody?.error ?? muxBody);
      console.error("complete-mux-live mux failed", muxResponse.status, message);
      await supabase
        .from("lives")
        .update({ status: "ended", is_active: false })
        .eq("id", liveId);
      return jsonResponse(
        {
          error: `Mux API: ${message}`,
          step: "mux",
          mux_status: muxResponse.status,
          ended_marked: true,
        },
        502,
      );
    }

    const resolved = await resolveAssetPlayback(muxLiveId, muxTokenId, muxTokenSecret);
    const updatePayload: Record<string, unknown> = {
      status: "ended",
      is_active: false,
    };
    if (resolved) {
      updatePayload.mux_asset_id = resolved.assetId;
      updatePayload.mux_vod_playback_id = resolved.playbackId;
    }
    await supabase.from("lives").update(updatePayload).eq("id", liveId);

    return jsonResponse({
      ok: true,
      mux_live_id: muxLiveId,
      step: "complete",
      vod_playback_id: resolved?.playbackId ?? null,
      mux_asset_id: resolved?.assetId ?? null,
      livekit_egress_stopped: livekitCleanup?.stopped ?? [],
      livekit_active_egress_before: livekitCleanup?.active_before ?? null,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error.";
    console.error("complete-mux-live unhandled", message);
    return jsonResponse({ error: message, step: "unhandled" }, 500);
  }
});
