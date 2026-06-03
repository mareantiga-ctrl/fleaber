import {
  createLivekitAdminJwt,
  listActiveEgress,
  livekitHttpHost,
} from "../supabase/functions/_shared/livekit_egress_helpers.ts";

const url = Deno.env.get("LIVEKIT_URL");
const key = Deno.env.get("LIVEKIT_API_KEY");
const secret = Deno.env.get("LIVEKIT_API_SECRET");

if (!url || !key || !secret) {
  console.error("Missing LIVEKIT_URL, LIVEKIT_API_KEY, or LIVEKIT_API_SECRET");
  Deno.exit(1);
}

const active = await listActiveEgress(url, key, secret);
const fleaber = active.filter((e) => {
  const room = (e.roomName ?? e.room_name ?? "").toString();
  return room.startsWith("fleaber_");
});

const host = livekitHttpHost(url);
const adminJwt = await createLivekitAdminJwt(key, secret, "fleaber-room-list");
const roomsRes = await fetch(`${host}/twirp/livekit.RoomService/ListRooms`, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${adminJwt}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({}),
});
const roomsPayload = await roomsRes.json().catch(() => ({}));
const rooms = (roomsPayload?.rooms ?? []) as Array<Record<string, unknown>>;
const fleaberRooms = rooms.filter((r) => {
  const name = (r.name ?? "").toString();
  return name.startsWith("fleaber_");
});

console.log(
  JSON.stringify(
    {
      active_egress_total: active.length,
      active_fleaber_egress: fleaber.length,
      fleaber_rooms_with_egress: [
        ...new Set(
          fleaber.map((e) => (e.roomName ?? e.room_name ?? "").toString()),
        ),
      ],
      active_rooms_total: rooms.length,
      active_fleaber_rooms: fleaberRooms.length,
      fleaber_room_details: fleaberRooms.map((r) => ({
        name: r.name,
        num_participants: r.num_participants,
        creation_time: r.creation_time,
      })),
      egress_summary: active.map((e) => ({
        id: e.egressId ?? e.egress_id,
        room: e.roomName ?? e.room_name,
        status: e.status,
      })),
    },
    null,
    2,
  ),
);
