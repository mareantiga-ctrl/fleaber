/**
 * Testes automáticos do ciclo de vida Seller Studio (sem Chrome).
 * node tool/fleaber_ps_extension/test_studio_lifecycle.mjs
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const __dirname = dirname(fileURLToPath(import.meta.url));
const hubSrc = readFileSync(join(__dirname, "studio_hub.js"), "utf8");

const sandbox = { console, Date, Math, JSON, Number, String, Array, Object, Map, Set };
sandbox.globalThis = sandbox;
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(hubSrc, sandbox);

const Hub = sandbox.FleaberStudioHub;
if (!Hub) {
  console.error("FAIL: FleaberStudioHub não carregou");
  process.exit(1);
}

let failed = 0;
function assert(cond, msg) {
  if (!cond) {
    failed += 1;
    console.error(`FAIL: ${msg}`);
  } else {
    console.log(`PASS: ${msg}`);
  }
}

const t0 = Date.parse("2026-09-01T10:00:00.000Z");
const nowActive = t0 + 90 * 1000; // 90s
const nowDaysLater = t0 + 164 * 3600 * 1000; // ~164h later

const liveActive = {
  id: "live-active-1",
  title: "Directo teste",
  status: "live",
  is_active: true,
  went_live_at: "2026-09-01T10:00:00.000Z",
  viewer_count: 12,
  seller_handle: "demo",
  seller_id: "seller-1",
};

const liveEnded = {
  ...liveActive,
  id: "live-ended-1",
  status: "ended",
  is_active: false,
};

// 1) Activa vs terminada
assert(Hub.isHubLiveActive(liveActive) === true, "live activa reconhecida");
assert(Hub.isHubLiveActive(liveEnded) === false, "live ended não é activa");
assert(
  Hub.isHubLiveActive({ status: "live", is_active: false }) === true,
  "status=live conta como activa mesmo com is_active false",
);
assert(
  Hub.isHubLiveActive({ status: "ended", is_active: true }) === false,
  "status=ended nunca é activa (mesmo com is_active true)",
);

// 2) Contador só enquanto activa
const durActive = Hub.computeDurationSec(liveActive, null, nowActive);
assert(durActive === 90, `duração activa = 90s (got ${durActive})`);

const durEndedNoFreeze = Hub.computeDurationSec(liveEnded, null, nowDaysLater);
assert(
  durEndedNoFreeze === null,
  `ended sem freeze → null (não conta ~164h); got ${durEndedNoFreeze}`,
);

const durFrozen = Hub.computeDurationSec(liveEnded, 95, nowDaysLater);
assert(durFrozen === 95, `ended com freeze → 95s (got ${durFrozen})`);

// 3) Metrics: liveActive flag + duração
const mActive = Hub.computeMetrics({
  hubLive: liveActive,
  fomo: { viewer_count: 12 },
  products: [],
  journal: [],
  frozenDurationSec: null,
});
// computeMetrics uses Date.now() internally for active — only check liveActive + that duration is finite when active
assert(mActive.liveActive === true, "metrics.liveActive true");

const mEnded = Hub.computeMetrics({
  hubLive: liveEnded,
  fomo: {},
  products: [{ pendingQueue: 3, reservedQty: 1, title: "X" }],
  journal: [{ intent: "reserve", ok: true, action: "created" }],
  frozenDurationSec: 120,
});
assert(mEnded.liveActive === false, "metrics.liveActive false quando ended");
assert(mEnded.durationSec === 120, `metrics duração congelada 120 (got ${mEnded.durationSec})`);

const mEndedNoFreeze = Hub.computeMetrics({
  hubLive: liveEnded,
  products: [],
  journal: [],
  frozenDurationSec: null,
});
assert(
  mEndedNoFreeze.durationSec === null,
  "sem freeze, duração null (estado limpo / sem contador infinito)",
);

// 4) Histórico: build + merge (sem inventar duração Hub)
const entry = Hub.buildHistoryEntry({
  hubLive: liveEnded,
  metrics: mEnded,
  frozenDurationSec: 120,
  archivedAt: "2026-09-01T10:02:00.000Z",
  snapshot: {
    chatTranscript: [{ n: 1, buyer: "Ana", text: "Ana oi", t: 1 }],
    journal: [{ ok: true, intent: "reserve", buyer: "Ana", raw: "quero r1" }],
    queueRows: [{ id: "q1", status: "accepted", ref_code: "R1" }],
    products: [{ refCode: "R1" }],
    liveMessages: [],
  },
});
assert(entry?.liveId === "live-ended-1", "history entry liveId");
assert(entry?.durationSec === 120, "history entry duração congelada");
assert(entry?.readOnly === true, "history entry readOnly");
assert(entry?.viewerCount === 12, "history entry viewers do metrics/hub");
assert(
  entry?.snapshot?.chatTranscript?.length === 1,
  "history snapshot inclui chat FB transcript",
);
assert(
  entry?.snapshot?.queueRows?.[0]?.id === "q1",
  "history snapshot inclui reservas",
);

const hubRows = [
  {
    id: "live-ended-1",
    title: "Directo teste",
    status: "ended",
    is_active: false,
    went_live_at: "2026-09-01T10:00:00.000Z",
    created_at: "2026-09-01T09:50:00.000Z",
    viewer_count: 9,
    seller_handle: "demo",
    mux_vod_playback_id: "vod1",
  },
  {
    id: "live-active-should-skip",
    title: "Ainda live",
    status: "live",
    is_active: true,
    went_live_at: "2026-09-20T10:00:00.000Z",
    created_at: "2026-09-20T09:00:00.000Z",
    viewer_count: 3,
  },
  {
    id: "live-hub-only",
    title: "Só Hub",
    status: "ended",
    is_active: false,
    went_live_at: "2026-08-01T12:00:00.000Z",
    created_at: "2026-08-01T11:00:00.000Z",
    viewer_count: 4,
  },
];

const merged = Hub.mergeHistoryLists([entry], hubRows);
assert(
  !merged.some((e) => e.liveId === "live-active-should-skip"),
  "merge exclui lives ainda activas",
);
const mergedEnded = merged.find((e) => e.liveId === "live-ended-1");
assert(mergedEnded?.durationSec === 120, "merge preserva duração local");
assert(mergedEnded?.hasVod === true, "merge traz hasVod do Hub");
const hubOnly = merged.find((e) => e.liveId === "live-hub-only");
assert(hubOnly?.durationSec === null, "Hub-only sem duração inventada");
assert(hubOnly?.viewerCount === 4, "Hub-only mostra viewer_count real");

// 5) Ciclo simulado: activa → terminar → freeze → limpar ops (modelo)
const cycle = {
  ops: {
    liveId: liveActive.id,
    deviceToken: "tok",
    liveDurationSnapshotSec: 90,
    products: ["a", "b"],
  },
  seller: { sellerAccessToken: "jwt-keep" },
  history: [],
};

function simulateEnd(state, hubLive) {
  const frozen = state.ops.liveDurationSnapshotSec;
  const hist = Hub.buildHistoryEntry({
    hubLive: { ...hubLive, status: "ended", is_active: false },
    metrics: { viewersFleaber: 12, soldTotal: 2, gmvEur: 10, productsCount: 2 },
    frozenDurationSec: frozen,
  });
  state.history.unshift(hist);
  state.ops = {}; // clear ops — seller untouched
  return state;
}

const after = simulateEnd(cycle, liveActive);
assert(!after.ops.liveId, "após terminar: sem liveId operacional");
assert(after.seller.sellerAccessToken === "jwt-keep", "login vendedor preservado");
assert(after.history[0].durationSec === 90, "histórico com duração congelada 90s");
assert(
  Hub.computeDurationSec(
    { ...liveActive, status: "ended", is_active: false },
    after.history[0].durationSec,
    nowDaysLater,
  ) === 90,
  "reabrir dias depois: duração continua 90 (não 164h)",
);

// 6) Reabrir sem live activa = estado limpo (modelo)
assert(
  Object.keys(after.ops).length === 0 && after.history.length === 1,
  "reabrir Studio: ops vazio + histórico consultável",
);

assert(
  Hub.buildHubLiveWebUrl("Vendora-MuxB-0913", "live-uuid-1", "https://fleaber.pt") ===
    "https://fleaber.pt/fleahub/index.html#/vendora-muxb-0913/live?liveId=live-uuid-1",
  "buildHubLiveWebUrl espelha HubUrls.liveWebHash",
);
assert(Hub.buildHubLiveWebUrl("", "x") === "", "buildHubLiveWebUrl sem handle → vazio");
assert(Hub.buildHubLiveWebUrl("demo", "") === "", "buildHubLiveWebUrl sem liveId → vazio");

if (failed) {
  console.error(`\n${failed} teste(s) falharam`);
  process.exit(1);
}
console.log("\nOK — ciclo de vida Seller Studio");
process.exit(0);
