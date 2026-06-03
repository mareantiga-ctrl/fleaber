import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  listActiveEgress,
  stopAllActiveEgressForRoom,
  stopLivekitEgressById,
} from "../_shared/livekit_egress_helpers.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cleanup-secret",
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

function isCleanupAuthorized(req: Request, serviceRoleKey: string): boolean {
  const authHeader = req.headers.get("Authorization") ?? "";
  if (authHeader === `Bearer ${serviceRoleKey}`) return true;
  const cronSecret = (Deno.env.get("LIVEKIT_EGRESS_CLEANUP_SECRET") ?? "").trim();
  const headerSecret = (req.headers.get("x-cleanup-secret") ?? "").trim();
  return cronSecret.length > 0 && headerSecret === cronSecret;
}

Deno.serve(async (req) => {
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

    const { data: staleLives } = await supabase
      .from("lives")
      .select("id, livekit_egress_id, livekit_room_name, status")
      .not("livekit_egress_id", "is", null)
      .in("status", ["ended"])
      .limit(100);

    const stoppedFromDb: string[] = [];
    for (const live of staleLives ?? []) {
      const egressId = (live.livekit_egress_id ?? "").trim();
      const room =
        (live.livekit_room_name ?? "").trim() ||
        roomNameForLive(live.id ?? "");
      if (egressId) {
        const ok = await stopLivekitEgressById(
          livekitUrl,
          livekitApiKey,
          livekitApiSecret,
          egressId,
        );
        if (ok) stoppedFromDb.push(egressId);
      }
      await stopAllActiveEgressForRoom(
        livekitUrl,
        livekitApiKey,
        livekitApiSecret,
        room,
      );
      await supabase
        .from("lives")
        .update({ livekit_egress_id: null })
        .eq("id", live.id);
    }

    const allActive = await listActiveEgress(
      livekitUrl,
      livekitApiKey,
      livekitApiSecret,
    );
    const fleaberActive = allActive.filter((e) => {
      const room = (e.roomName ?? e.room_name ?? "").toString();
      return room.startsWith("fleaber_");
    });

    const stoppedOrphans: string[] = [];
    for (const item of fleaberActive) {
      const id = (item.egressId ?? item.egress_id ?? "").trim();
      if (!id) continue;
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
    active_fleaber_egress_before: fleaberActive.length,
    stopped_orphans: stoppedOrphans,
    active_egress_total_now: (await listActiveEgress(
      livekitUrl,
      livekitApiKey,
      livekitApiSecret,
    )).length,
  });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error.";
    console.error("livekit-egress-cleanup", message);
    return jsonResponse({ error: message }, 500);
  }
});
