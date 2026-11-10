import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  listActiveEgress,
  liveIdFromFleaberRoom,
  shouldStopOrphanEgress,
  stopAllActiveEgressForRoom,
  stopLivekitEgressById,
} from "../_shared/livekit_egress_helpers.ts";
import { buildCorsHeaders } from "../_shared/cors.ts";

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

function roomNameForLive(liveId: string) {
  const safe = liveId.replace(/[^a-zA-Z0-9_-]/g, "");
  return `fleaber_${safe}`;
}

function isCleanupAuthorized(req: Request, serviceRoleKey: string): boolean {
  // ZIP 168: trim + aceitar Authorization ou apikey (gateway Supabase).
  const expected = (serviceRoleKey ?? "").trim();
  if (!expected) return false;
  const authHeader = (req.headers.get("Authorization") ?? "").trim();
  if (authHeader === `Bearer ${expected}`) return true;
  const apiKey = (req.headers.get("apikey") ?? "").trim();
  if (apiKey === expected) return true;
  const cronSecret = (Deno.env.get("LIVEKIT_EGRESS_CLEANUP_SECRET") ?? "").trim();
  const headerSecret = (req.headers.get("x-cleanup-secret") ?? "").trim();
  return cronSecret.length > 0 && headerSecret === cronSecret;
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

    const livekitUrl = Deno.env.get("LIVEKIT_URL");
    const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY");
    const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!livekitUrl || !livekitApiKey || !livekitApiSecret) {
      return jsonResponse({ error: "LiveKit config missing." }, 500);
    }
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Supabase config missing." }, 500);
    }
    if (!isCleanupAuthorized(req, serviceRoleKey)) {
      return jsonResponse({ error: "Unauthorized." }, 401);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // 1) Só lives já ended com egress conhecido — alvo concreto por row.
    const { data: staleLives, error: staleErr } = await supabase
      .from("lives")
      .select("id, livekit_egress_id, livekit_room_name, status, is_active")
      .not("livekit_egress_id", "is", null)
      .in("status", ["ended"])
      .limit(100);

    if (staleErr) {
      console.error("livekit-egress-cleanup stale query", staleErr.message);
      return jsonResponse({
        ok: false,
        error: "Não foi possível listar lives ended — nenhum egress parado.",
        detail: staleErr.message,
      }, 500);
    }

    const stoppedFromDb: string[] = [];
    const roomsCleaned: string[] = [];
    for (const live of staleLives ?? []) {
      const liveId = (live.id ?? "").trim();
      if (!liveId) continue;
      const egressId = (live.livekit_egress_id ?? "").trim();
      const room =
        (live.livekit_room_name ?? "").trim() || roomNameForLive(liveId);
      if (!room.startsWith("fleaber_")) {
        console.warn(
          "livekit-egress-cleanup skip non-fleaber room for ended live",
          liveId,
        );
        continue;
      }
      if (egressId) {
        const ok = await stopLivekitEgressById(
          livekitUrl,
          livekitApiKey,
          livekitApiSecret,
          egressId,
        );
        if (ok) stoppedFromDb.push(egressId);
      }
      // Room scoped — never empty room (helper fails closed).
      const roomStop = await stopAllActiveEgressForRoom(
        livekitUrl,
        livekitApiKey,
        livekitApiSecret,
        room,
      );
      roomsCleaned.push(room);
      for (const id of roomStop.stopped) {
        if (!stoppedFromDb.includes(id)) stoppedFromDb.push(id);
      }
      await supabase
        .from("lives")
        .update({ livekit_egress_id: null })
        .eq("id", liveId);
    }

    // 2) Orphans: só stop se room → liveId parseável E live ended/inexistente.
    // NUNCA "listar todos fleaber_* e parar" sem prova de ownership.
    const listResult = await listActiveEgress(
      livekitUrl,
      livekitApiKey,
      livekitApiSecret,
    );
    // listActiveEgress returns [] on API error — treat as fail-closed (stop none).
    const fleaberActive = listResult.filter((e) => {
      const room = (e.roomName ?? e.room_name ?? "").toString();
      return room.startsWith("fleaber_");
    });

    const stoppedOrphans: string[] = [];
    const skippedActive: string[] = [];
    const skippedUnproven: string[] = [];

    for (const item of fleaberActive) {
      const id = (item.egressId ?? item.egress_id ?? "").trim();
      const room = (item.roomName ?? item.room_name ?? "").toString().trim();
      if (!id) continue;

      const liveId = liveIdFromFleaberRoom(room);
      if (!liveId) {
        skippedUnproven.push(id);
        console.warn(
          "livekit-egress-cleanup orphan skip: room sem liveId fiável",
          room,
        );
        continue;
      }

      const { data: liveRow, error: liveErr } = await supabase
        .from("lives")
        .select("id, status, is_active")
        .eq("id", liveId)
        .maybeSingle();

      const decision = shouldStopOrphanEgress({
        roomName: room,
        liveRow: liveRow ?? null,
        lookupError: !!liveErr,
      });
      if (!decision.stop) {
        if (decision.reason === "live_still_active") skippedActive.push(id);
        else skippedUnproven.push(id);
        if (liveErr) {
          console.error(
            "livekit-egress-cleanup orphan skip: lookup failed",
            liveId,
            liveErr.message,
          );
        }
        continue;
      }

      const ok = await stopLivekitEgressById(
        livekitUrl,
        livekitApiKey,
        livekitApiSecret,
        id,
      );
      if (ok) stoppedOrphans.push(id);
    }

    return jsonResponse({
      ok: true,
      db_lives_checked: staleLives?.length ?? 0,
      stopped_from_db: stoppedFromDb,
      rooms_cleaned: roomsCleaned,
      active_fleaber_egress_seen: fleaberActive.length,
      stopped_orphans: stoppedOrphans,
      skipped_active_lives: skippedActive,
      skipped_unproven: skippedUnproven,
      note:
        "Fail-closed: never stops fleaber egress without ended/missing live proof.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error.";
    console.error("livekit-egress-cleanup", message);
    return jsonResponse({ error: message }, 500);
  }
});
