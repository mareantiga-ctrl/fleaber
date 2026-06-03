import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { SignJWT } from "https://deno.land/x/jose@v5.2.0/index.ts";
import {
  listActiveEgress,
  stopAllActiveEgressForRoom,
  stopLivekitEgressById,
} from "../_shared/livekit_egress_helpers.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type LivekitMuxPublishRequest = {
  step?: "token" | "egress" | "stop_egress";
  live_id?: string;
  stream_key?: string;
  use_rtmps?: boolean;
  egress_id?: string;
  video_track_id?: string;
  audio_track_id?: string;
  /** true = preset 0 (1280×720); app roda no player. false = preset 4 portrait. */
  mux_encode_landscape?: boolean;
};

type VideoGrant = Record<string, unknown>;

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

function muxRtmpUrl(streamKey: string, useRtmps: boolean) {
  if (useRtmps) {
    return `rtmps://global-live.mux.com:443/app/${streamKey}`;
  }
  return `rtmp://global-live.mux.com:5222/app/${streamKey}`;
}

function livekitHttpHost(livekitUrl: string) {
  return livekitUrl.replace(/^wss:/i, "https:").replace(/^ws:/i, "http:");
}

async function createLivekitJwt(
  apiKey: string,
  apiSecret: string,
  identity: string,
  videoGrant: VideoGrant,
  ttlSeconds = 4 * 60 * 60,
) {
  const secret = new TextEncoder().encode(apiSecret);
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({ video: videoGrant })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer(apiKey)
    .setSubject(identity)
    .setJti(crypto.randomUUID())
    .setIssuedAt(now)
    .setExpirationTime(now + ttlSeconds)
    .sign(secret);
}

/** Preset 0 = H264_720P_30 (1280×720 landscape, ~3 Mbps). */
const EGRESS_LANDSCAPE_PRESET = 0;

/** Preset 4 = PORTRAIT_H264_720P_30 (720×1280). */
const EGRESS_PORTRAIT_PRESET = 4;

/** Modo teste: bitrate mais alto no RTMP→Mux (qualidade tipo FB). */
const EGRESS_LANDSCAPE_ADVANCED = {
  width: 1280,
  height: 720,
  framerate: 30,
  video_bitrate: 8000,
  audio_bitrate: 192,
};

function egressPresetForBody(body: LivekitMuxPublishRequest): number {
  return body.mux_encode_landscape === true
    ? EGRESS_LANDSCAPE_PRESET
    : EGRESS_PORTRAIT_PRESET;
}

/** Layout built-in: um participante em ecrã cheio (melhor que ParticipantEgress para 9:16). */
const ROOM_COMPOSITE_LAYOUT = "single-speaker";

async function livekitEgressAdminJwt(apiKey: string, apiSecret: string) {
  return await createLivekitJwt(
    apiKey,
    apiSecret,
    "fleaber-egress",
    { roomRecord: true, roomAdmin: true },
    10 * 60,
  );
}

async function callLivekitEgressRpc(
  livekitUrl: string,
  adminJwt: string,
  rpc:
    | "StartRoomCompositeEgress"
    | "StartParticipantEgress"
    | "StartTrackCompositeEgress",
  body: Record<string, unknown>,
) {
  const host = livekitHttpHost(livekitUrl);
  const res = await fetch(`${host}/twirp/livekit.Egress/${rpc}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${adminJwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const message =
      payload?.msg ??
      payload?.message ??
      payload?.error ??
      JSON.stringify(payload);
    throw new Error(`LiveKit ${rpc} ${res.status}: ${message}`);
  }

  return payload as { egress_id?: string; egressId?: string };
}

/**
 * Room Composite: headless recorder com layout portrait (evita letterbox do ParticipantEgress).
 * O vendedor já deve estar na room com vídeo publicado antes de chamar isto.
 */
async function startRoomCompositeEgressToMux(
  livekitUrl: string,
  apiKey: string,
  apiSecret: string,
  roomName: string,
  rtmpUrl: string,
  preset: number,
) {
  const adminJwt = await livekitEgressAdminJwt(apiKey, apiSecret);
  return await callLivekitEgressRpc(
    livekitUrl,
    adminJwt,
    "StartRoomCompositeEgress",
    {
      room_name: roomName,
      layout: ROOM_COMPOSITE_LAYOUT,
      stream_outputs: [
        {
          protocol: 1, // StreamProtocol.RTMP
          urls: [rtmpUrl],
        },
      ],
      preset,
    },
  );
}

/**
 * Track Composite: mux directo das tracks publicadas (sem template Chrome).
 * Requer video_track_id da app (câmara já publicada na room).
 */
async function startTrackCompositeEgressToMux(
  livekitUrl: string,
  apiKey: string,
  apiSecret: string,
  roomName: string,
  videoTrackId: string,
  audioTrackId: string | null,
  rtmpUrl: string,
  preset: number,
  muxEncodeLandscape: boolean,
) {
  const adminJwt = await livekitEgressAdminJwt(apiKey, apiSecret);
  const body: Record<string, unknown> = {
    room_name: roomName,
    video_track_id: videoTrackId,
    stream_outputs: [
      {
        protocol: 1,
        urls: [rtmpUrl],
      },
    ],
  };
  if (muxEncodeLandscape) {
    body.advanced = EGRESS_LANDSCAPE_ADVANCED;
  } else {
    body.preset = preset;
  }
  if (audioTrackId) {
    body.audio_track_id = audioTrackId;
  }
  return await callLivekitEgressRpc(
    livekitUrl,
    adminJwt,
    "StartTrackCompositeEgress",
    body,
  );
}

/** Fallback legado — ParticipantEgress (letterbox em alguns Android/MTK). */
async function startParticipantEgressToMux(
  livekitUrl: string,
  apiKey: string,
  apiSecret: string,
  roomName: string,
  participantIdentity: string,
  rtmpUrl: string,
  preset: number,
) {
  const adminJwt = await livekitEgressAdminJwt(apiKey, apiSecret);
  return await callLivekitEgressRpc(
    livekitUrl,
    adminJwt,
    "StartParticipantEgress",
    {
      room_name: roomName,
      identity: participantIdentity,
      stream_outputs: [
        {
          protocol: 1,
          urls: [rtmpUrl],
        },
      ],
      preset,
    },
  );
}

async function stopLivekitEgress(
  livekitUrl: string,
  apiKey: string,
  apiSecret: string,
  egressId: string,
) {
  await stopLivekitEgressById(livekitUrl, apiKey, apiSecret, egressId);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed.", step: "method" }, 405);
    }

    const livekitUrl = Deno.env.get("LIVEKIT_URL");
    const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY");
    const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authHeader = req.headers.get("Authorization") ?? "";

    if (!livekitUrl || !livekitApiKey || !livekitApiSecret) {
      return jsonResponse(
        {
          error:
            "LiveKit em falta no servidor (LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET).",
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

    const body = (await req.json().catch(() => ({}))) as LivekitMuxPublishRequest;
    const step = body.step ?? "token";
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
        "id, vendedor_id, seller_id, mux_stream_key, stream_key, livekit_egress_id",
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

    const roomName = roomNameForLive(liveId);

    if (step === "token") {
      const token = await createLivekitJwt(
        livekitApiKey,
        livekitApiSecret,
        `seller_${userData.user.id}`,
        {
          roomJoin: true,
          room: roomName,
          canPublish: true,
          canSubscribe: true,
          canPublishData: true,
        },
      );

      const updatePayload: Record<string, unknown> = {
        livekit_room_name: roomName,
      };
      // Colunas opcionais (SQL live_streaming_livekit_batata.sql).
      try {
        await supabase
          .from("lives")
          .update({ ...updatePayload, publish_backend: "livekit_mux" })
          .eq("id", liveId);
      } catch (_) {
        await supabase.from("lives").update(updatePayload).eq("id", liveId);
      }

      return jsonResponse({
        step: "token",
        livekit_url: livekitUrl,
        token,
        room_name: roomName,
        live_id: liveId,
      });
    }

    if (step === "stop_egress") {
      const egressId =
        (body.egress_id ?? "").trim() ||
        (live.livekit_egress_id ?? "").trim();
      const cleanup = await stopAllActiveEgressForRoom(
        livekitUrl,
        livekitApiKey,
        livekitApiSecret,
        roomName,
      );
      if (egressId) {
        await stopLivekitEgress(
          livekitUrl,
          livekitApiKey,
          livekitApiSecret,
          egressId,
        );
      }
      console.log(
        "stop_egress",
        liveId,
        "active_before=",
        cleanup.active_before,
        "stopped=",
        cleanup.stopped,
      );
      await supabase
        .from("lives")
        .update({ livekit_egress_id: null })
        .eq("id", liveId);
      return jsonResponse({
        step: "stop_egress",
        stopped: egressId || null,
        active_egress_stopped: cleanup.stopped.length,
        active_egress_before: cleanup.active_before,
      });
    }

    if (step === "egress") {
      const streamKey =
        (body.stream_key ?? "").trim() ||
        (live.mux_stream_key ?? live.stream_key ?? "").trim();
      if (!streamKey) {
        return jsonResponse(
          { error: "stream_key em falta para egress Mux.", step: "validation" },
          400,
        );
      }

      const useRtmps = body.use_rtmps !== false;
      const rtmpUrl = muxRtmpUrl(streamKey, useRtmps);

      const staleEgress = (live.livekit_egress_id ?? "").trim();
      if (staleEgress) {
        await stopLivekitEgress(
          livekitUrl,
          livekitApiKey,
          livekitApiSecret,
          staleEgress,
        );
      }

      const preCleanup = await stopAllActiveEgressForRoom(
        livekitUrl,
        livekitApiKey,
        livekitApiSecret,
        roomName,
      );
      const activeBefore = await listActiveEgress(
        livekitUrl,
        livekitApiKey,
        livekitApiSecret,
        roomName,
      );
      const videoTrackId = (body.video_track_id ?? "").trim();
      const audioTrackId = (body.audio_track_id ?? "").trim() || null;
      const egressPreset = egressPresetForBody(body);

      let egressMode: string;
      let info: { egress_id?: string; egressId?: string };

      if (videoTrackId) {
        egressMode = "track_composite";
        console.log(
          "egress.start",
          liveId,
          "room=",
          roomName,
          "mode=track_composite",
          "video_track_id=",
          videoTrackId,
          "preset=",
          egressPreset,
          "mux_encode_landscape=",
          body.mux_encode_landscape === true,
          "pre_cleanup_stopped=",
          preCleanup.stopped.length,
          "active_before=",
          activeBefore.length,
        );
        info = await startTrackCompositeEgressToMux(
          livekitUrl,
          livekitApiKey,
          livekitApiSecret,
          roomName,
          videoTrackId,
          audioTrackId,
          rtmpUrl,
          egressPreset,
          body.mux_encode_landscape === true,
        );
      } else {
        egressMode = "room_composite";
        console.log(
          "egress.start",
          liveId,
          "room=",
          roomName,
          "mode=room_composite",
          "layout=",
          ROOM_COMPOSITE_LAYOUT,
          "preset=",
          egressPreset,
          "pre_cleanup_stopped=",
          preCleanup.stopped.length,
          "active_before=",
          activeBefore.length,
        );
        info = await startRoomCompositeEgressToMux(
          livekitUrl,
          livekitApiKey,
          livekitApiSecret,
          roomName,
          rtmpUrl,
          egressPreset,
        );
      }

      const egressId = info.egressId ?? info.egress_id ?? "";
      const activeAfter = await listActiveEgress(
        livekitUrl,
        livekitApiKey,
        livekitApiSecret,
        roomName,
      );

      const egressUpdate: Record<string, unknown> = {
        livekit_room_name: roomName,
        livekit_egress_id: egressId || null,
      };
      try {
        await supabase
          .from("lives")
          .update({ ...egressUpdate, publish_backend: "livekit_mux" })
          .eq("id", liveId);
      } catch (_) {
        await supabase.from("lives").update(egressUpdate).eq("id", liveId);
      }

      return jsonResponse({
        step: "egress",
        egress_id: egressId,
        egress_mode: egressMode,
        egress_layout: egressMode === "room_composite"
          ? ROOM_COMPOSITE_LAYOUT
          : null,
        egress_video_track_id: videoTrackId || null,
        egress_preset: egressPreset,
        egress_advanced: body.mux_encode_landscape === true
          ? EGRESS_LANDSCAPE_ADVANCED
          : null,
        mux_encode_landscape: body.mux_encode_landscape === true,
        room_name: roomName,
        rtmp_target: useRtmps ? "rtmps:443" : "rtmp:5222",
        live_id: liveId,
        active_egress_before: preCleanup.active_before,
        stale_egress_stopped: preCleanup.stopped,
        active_egress_after_start: activeAfter.length,
      });
    }

    return jsonResponse({ error: "step inválido.", step: "validation" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error.";
    console.error("livekit-mux-publish unhandled", message);
    const isQuota =
      message.includes("429") || message.toLowerCase().includes("egress minutes");
    return jsonResponse(
      {
        error: isQuota
          ? "Limite de minutos LiveKit atingido. Para o directo anterior ou aguarda/actualiza o plano LiveKit."
          : message,
        step: "unhandled",
      },
      isQuota ? 429 : 500,
    );
  }
});
