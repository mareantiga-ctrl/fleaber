/**
 * Unit tests for LiveKit orphan cleanup decision (A3).
 * Run: deno test supabase/functions/_shared/livekit_egress_helpers_test.ts
 */
import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  liveIdFromFleaberRoom,
  shouldStopOrphanEgress,
} from "./livekit_egress_helpers.ts";

Deno.test("liveIdFromFleaberRoom parses fleaber_<id>", () => {
  assertEquals(
    liveIdFromFleaberRoom("fleaber_abcdefgh"),
    "abcdefgh",
  );
  assertEquals(liveIdFromFleaberRoom(""), null);
  assertEquals(liveIdFromFleaberRoom("other_room"), null);
  assertEquals(liveIdFromFleaberRoom("fleaber_ab"), null); // too short
});

Deno.test("A3 scenario: Live A active → do not stop", () => {
  const d = shouldStopOrphanEgress({
    roomName: "fleaber_liveAAAAAA",
    liveRow: { status: "live", is_active: true },
  });
  assertEquals(d.stop, false);
  assertEquals(d.reason, "live_still_active");
});

Deno.test("A3 scenario: Live A ended → stop orphan OK", () => {
  const d = shouldStopOrphanEgress({
    roomName: "fleaber_liveAAAAAA",
    liveRow: { status: "ended", is_active: false },
  });
  assertEquals(d.stop, true);
  assertEquals(d.reason, "live_ended");
});

Deno.test("A3 scenario: Live B active while cleaning A room → B untouched (decision per room)", () => {
  const b = shouldStopOrphanEgress({
    roomName: "fleaber_liveBBBBBB",
    liveRow: { status: "live", is_active: true },
  });
  assertEquals(b.stop, false);
});

Deno.test("A3 scenario: invalid room → stop none", () => {
  const d = shouldStopOrphanEgress({
    roomName: "not_fleaber",
    liveRow: null,
  });
  assertEquals(d.stop, false);
  assertEquals(d.reason, "unproven_room");
});

Deno.test("A3 scenario: lookup error → fail-closed", () => {
  const d = shouldStopOrphanEgress({
    roomName: "fleaber_liveAAAAAA",
    liveRow: null,
    lookupError: true,
  });
  assertEquals(d.stop, false);
  assertEquals(d.reason, "lookup_error");
});

Deno.test("A3 scenario: live missing in DB → stop orphan", () => {
  const d = shouldStopOrphanEgress({
    roomName: "fleaber_deadbeef01",
    liveRow: null,
  });
  assertEquals(d.stop, true);
  assertEquals(d.reason, "live_missing");
});

Deno.test("A3 scenario: repeated decision idempotent", () => {
  const a = shouldStopOrphanEgress({
    roomName: "fleaber_liveAAAAAA",
    liveRow: { status: "ended", is_active: false },
  });
  const b = shouldStopOrphanEgress({
    roomName: "fleaber_liveAAAAAA",
    liveRow: { status: "ended", is_active: false },
  });
  assertEquals(a, b);
});
