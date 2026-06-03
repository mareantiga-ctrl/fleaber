/**
 * Cleanup LiveKit egress órfãos (local, via API LiveKit).
 * Opcional: invoca edge function se SUPABASE_SERVICE_ROLE_KEY ou CLEANUP_SECRET estiver definido.
 *
 * Uso:
 *   npx --yes deno@2.3.5 run --allow-net --allow-env scripts/run_livekit_cleanup.ts
 */
import {
  listActiveEgress,
  stopAllActiveEgressForRoom,
  stopLivekitEgressById,
} from "../supabase/functions/_shared/livekit_egress_helpers.ts";

const livekitUrl = Deno.env.get("LIVEKIT_URL");
const livekitKey = Deno.env.get("LIVEKIT_API_KEY");
const livekitSecret = Deno.env.get("LIVEKIT_API_SECRET");
const projectUrl =
  Deno.env.get("SUPABASE_URL") ??
  "https://fxdknzrqjenzqcvnwqqq.supabase.co";
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const cleanupSecret = Deno.env.get("LIVEKIT_EGRESS_CLEANUP_SECRET") ?? "";

if (!livekitUrl || !livekitKey || !livekitSecret) {
  console.error("Missing LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET");
  Deno.exit(1);
}

const activeBefore = await listActiveEgress(livekitUrl, livekitKey, livekitSecret);
const fleaberBefore = activeBefore.filter((e) => {
  const room = (e.roomName ?? e.room_name ?? "").toString();
  return room.startsWith("fleaber_");
});

const stoppedOrphans: string[] = [];
for (const item of fleaberBefore) {
  const id = (item.egressId ?? item.egress_id ?? "").trim();
  if (!id) continue;
  const ok = await stopLivekitEgressById(
    livekitUrl,
    livekitKey,
    livekitSecret,
    id,
  );
  if (ok) stoppedOrphans.push(id);
}

const rooms = [
  ...new Set(
    fleaberBefore.map((e) => (e.roomName ?? e.room_name ?? "").toString()),
  ),
];
for (const room of rooms) {
  if (!room) continue;
  await stopAllActiveEgressForRoom(
    livekitUrl,
    livekitKey,
    livekitSecret,
    room,
  );
}

const activeAfter = await listActiveEgress(livekitUrl, livekitKey, livekitSecret);

let edgeResult: unknown = null;
let edgeError: string | null = null;

if (serviceRole || cleanupSecret) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (serviceRole) {
    headers.Authorization = `Bearer ${serviceRole}`;
  } else {
    headers["x-cleanup-secret"] = cleanupSecret;
  }
  try {
    const res = await fetch(
      `${projectUrl}/functions/v1/livekit-egress-cleanup`,
      { method: "POST", headers, body: "{}" },
    );
    edgeResult = await res.json().catch(() => ({ status: res.status }));
    if (!res.ok) {
      edgeError = `HTTP ${res.status}: ${JSON.stringify(edgeResult)}`;
    }
  } catch (e) {
    edgeError = e instanceof Error ? e.message : String(e);
  }
}

console.log(
  JSON.stringify(
    {
      livekit_api: {
        active_egress_before: activeBefore.length,
        active_fleaber_before: fleaberBefore.length,
        stopped_orphans: stoppedOrphans,
        active_egress_after: activeAfter.length,
      },
      edge_function: edgeResult,
      edge_function_error: edgeError,
      db_cleanup_note: edgeResult
        ? null
        : "Correr supabase/sql/livekit_egress_cleanup_once_batata.sql no SQL Editor para limpar livekit_egress_id na BD.",
    },
    null,
    2,
  ),
);
