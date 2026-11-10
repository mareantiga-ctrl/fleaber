import { SignJWT } from "https://deno.land/x/jose@v5.2.0/index.ts";

type VideoGrant = Record<string, unknown>;

export function livekitHttpHost(livekitUrl: string) {
  return livekitUrl.replace(/^wss:/i, "https:").replace(/^ws:/i, "http:");
}

export async function createLivekitAdminJwt(
  apiKey: string,
  apiSecret: string,
  identity: string,
  ttlSeconds = 5 * 60,
) {
  const secret = new TextEncoder().encode(apiSecret);
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({
    video: { roomRecord: true, roomAdmin: true } as VideoGrant,
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer(apiKey)
    .setSubject(identity)
    .setJti(crypto.randomUUID())
    .setIssuedAt(now)
    .setExpirationTime(now + ttlSeconds)
    .sign(secret);
}

export type LivekitEgressInfo = {
  egress_id?: string;
  egressId?: string;
  room_name?: string;
  roomName?: string;
  status?: string | number;
};

/** Extrai live id do room `fleaber_<id>` — sem id fiável → null (fail-closed). */
export function liveIdFromFleaberRoom(roomName: string): string | null {
  const room = (roomName ?? "").trim();
  if (!room.startsWith("fleaber_")) return null;
  const id = room.slice("fleaber_".length).trim();
  if (!id || id.length < 8) return null;
  return id;
}

/**
 * Decide se um egress activo pode ser parado como orphan.
 * Fail-closed: sem prova → false.
 */
export function shouldStopOrphanEgress(opts: {
  roomName: string;
  liveRow: { status?: string | null; is_active?: boolean | null } | null;
  lookupError?: boolean;
}): { stop: boolean; reason: string } {
  if (opts.lookupError) {
    return { stop: false, reason: "lookup_error" };
  }
  const liveId = liveIdFromFleaberRoom(opts.roomName);
  if (!liveId) {
    return { stop: false, reason: "unproven_room" };
  }
  if (!opts.liveRow) {
    return { stop: true, reason: "live_missing" };
  }
  const status = String(opts.liveRow.status ?? "").toLowerCase().trim();
  const isActive = opts.liveRow.is_active === true;
  if (isActive || (status && status !== "ended")) {
    return { stop: false, reason: "live_still_active" };
  }
  return { stop: true, reason: "live_ended" };
}

export async function listActiveEgress(
  livekitUrl: string,
  apiKey: string,
  apiSecret: string,
  roomName?: string,
): Promise<LivekitEgressInfo[]> {
  const host = livekitHttpHost(livekitUrl);
  const adminJwt = await createLivekitAdminJwt(
    apiKey,
    apiSecret,
    "fleaber-egress-list",
  );
  const body: Record<string, unknown> = { active: true };
  if (roomName?.trim()) body.room_name = roomName.trim();

  const res = await fetch(`${host}/twirp/livekit.Egress/ListEgress`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${adminJwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    console.warn("ListEgress failed", payload);
    return [];
  }
  const items = (payload?.items ?? payload?.egress ?? []) as LivekitEgressInfo[];
  return Array.isArray(items) ? items : [];
}

export async function stopLivekitEgressById(
  livekitUrl: string,
  apiKey: string,
  apiSecret: string,
  egressId: string,
): Promise<boolean> {
  const id = egressId.trim();
  if (!id) return false;
  const host = livekitHttpHost(livekitUrl);
  const adminJwt = await createLivekitAdminJwt(
    apiKey,
    apiSecret,
    "fleaber-egress-stop",
  );
  const res = await fetch(`${host}/twirp/livekit.Egress/StopEgress`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${adminJwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ egress_id: id }),
  });
  if (!res.ok) {
    const payload = await res.json().catch(() => ({}));
    console.warn("StopEgress failed", id, payload);
    return false;
  }
  return true;
}

/**
 * Para todos os egress activos numa room concreta.
 * Fail-closed: room vazia / sem prefixo fleaber_ → não lista nem para nada.
 */
export async function stopAllActiveEgressForRoom(
  livekitUrl: string,
  apiKey: string,
  apiSecret: string,
  roomName: string,
): Promise<{ stopped: string[]; active_before: number }> {
  const room = (roomName ?? "").trim();
  if (!room || !room.startsWith("fleaber_")) {
    console.warn(
      "stopAllActiveEgressForRoom refused: room vazia ou não fleaber_*",
      roomName,
    );
    return { stopped: [], active_before: 0 };
  }
  const active = await listActiveEgress(
    livekitUrl,
    apiKey,
    apiSecret,
    room,
  );
  const stopped: string[] = [];
  for (const item of active) {
    const id = (item.egressId ?? item.egress_id ?? "").trim();
    if (!id) continue;
    const ok = await stopLivekitEgressById(
      livekitUrl,
      apiKey,
      apiSecret,
      id,
    );
    if (ok) stopped.push(id);
  }
  return { stopped, active_before: active.length };
}
