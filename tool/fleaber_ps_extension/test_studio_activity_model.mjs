/**
 * Testes do read-model de actividade comercial (sem Chrome).
 * node tool/fleaber_ps_extension/test_studio_activity_model.mjs
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const __dirname = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(__dirname, "studio_activity_model.js"), "utf8");
const sandbox = { console, Date, Math, JSON, Number, String, Array, Object, Map, Set };
sandbox.globalThis = sandbox;
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(src, sandbox);

const Act = sandbox.FleaberStudioActivity;
let failed = 0;
function assert(cond, msg) {
  if (!cond) {
    failed += 1;
    console.error(`FAIL: ${msg}`);
  } else {
    console.log(`PASS: ${msg}`);
  }
}

assert(!!Act, "FleaberStudioActivity carregou");

const journal = [
  {
    t: "2026-09-20T14:37:34.000Z",
    ok: true,
    intent: "reserve",
    action: "created",
    buyer: "Mariana Soares",
    ref_out: "RRR6",
    qty_out: 1,
  },
];

const queue = [
  {
    id: "02af65ae-68e5-44cc-aaa1-4709a2d530ea",
    status: "pending",
    external_display_name: "Mariana Soares",
    ref_code: "#RRR6",
    requested_qty: 1,
    created_at: "2026-09-20T14:37:34.931Z",
  },
];

function mapJournal(entry) {
  if (entry.intent === "reserve" && entry.ok) {
    return {
      kind: "ok",
      title: `${entry.buyer} · Reservou ${entry.ref_out} ×${entry.qty_out}`,
      t: entry.t,
      isReserve: true,
    };
  }
  if (entry.intent === "cancel") {
    return {
      kind: "warn",
      title: `${entry.buyer} cancelou · ${entry.ref_out || entry.ref || ""}`,
      t: entry.t,
      isReserve: false,
      matchKey: Act.journalMatchKey(entry),
    };
  }
  return null;
}

const pendingFeeds = Act.buildCommercialFeeds({
  journal,
  queueRows: queue,
  mapJournalEntry: mapJournal,
});
assert(pendingFeeds.activity.length === 1, `pending: 1 linha (got ${pendingFeeds.activity.length})`);
assert(
  /No saco|por aceitar/i.test(pendingFeeds.activity[0].detail || pendingFeeds.activity[0].title),
  `pending = No saco (${pendingFeeds.activity[0].detail || pendingFeeds.activity[0].title})`,
);
assert(pendingFeeds.reserves.length === 1, "pending reservas feed = 1");

// Journal + fila com nomes OCR diferentes → ainda 1 linha (só fila)
const mismatchedJournal = [
  {
    t: "2026-09-20T14:37:34.000Z",
    ok: true,
    intent: "reserve",
    action: "created",
    buyer: "Mariana Soarez",
    ref_out: "RRR6",
    qty_out: 1,
  },
];
const mismatchFeeds = Act.buildCommercialFeeds({
  journal: mismatchedJournal,
  queueRows: queue,
  mapJournalEntry: mapJournal,
});
assert(
  mismatchFeeds.activity.length === 1,
  `OCR name mismatch ainda 1 linha (got ${mismatchFeeds.activity.length})`,
);

assert(Act.activeFaceReserveCount(queue) === 1, "activeFace pending = 1");
assert(
  Act.canonicalReserveCount({ queueRows: queue, journal }) === 1,
  "canonical = active quando há fila",
);

// RRR5 cancelada + RRR6 pending → Face ativas = 1; activity sem duplicar cancel journal
const queueMixed = [
  {
    id: "a",
    status: "rejected",
    notes: "buyer_cancelled",
    external_display_name: "Mariana Soares",
    ref_code: "RRR5",
    requested_qty: 1,
    created_at: "2026-09-21T08:01:00.000Z",
  },
  {
    id: "b",
    status: "pending",
    external_display_name: "Mariana Soares",
    ref_code: "RRR6",
    requested_qty: 1,
    created_at: "2026-09-21T08:01:10.000Z",
  },
];
const journalMixed = [
  {
    t: "2026-09-21T08:01:00.000Z",
    ok: true,
    intent: "reserve",
    action: "created",
    buyer: "Mariana Soares",
    ref_out: "RRR5",
  },
  {
    t: "2026-09-21T08:01:05.000Z",
    ok: true,
    intent: "cancel",
    action: "cancelled",
    buyer: "Mariana Soares",
    ref_out: "RRR5",
  },
  {
    t: "2026-09-21T08:01:10.000Z",
    ok: true,
    intent: "reserve",
    action: "created",
    buyer: "Mariana Soares",
    ref_out: "RRR6",
  },
];
assert(Act.activeFaceReserveCount(queueMixed) === 1, "Face ativas = 1 (só RRR6)");
const mixedFeeds = Act.buildCommercialFeeds({
  journal: journalMixed,
  queueRows: queueMixed,
  mapJournalEntry: mapJournal,
});
assert(
  mixedFeeds.activity.length === 2,
  `lifecycle: 2 linhas canónicas (got ${mixedFeeds.activity.length})`,
);
assert(
  !mixedFeeds.activity.some((a) => /cancelou/i.test(a.title)),
  "sem linha journal «cancelou» duplicada",
);
assert(
  mixedFeeds.activity.some((a) => /Cancelada/i.test(a.detail || "")),
  "RRR5 aparece como Cancelada (fila)",
);
assert(
  mixedFeeds.activity.some((a) => /No saco/i.test(a.detail || "")),
  "RRR6 aparece No saco",
);

// aceite
const accepted = [
  {
    id: "c",
    status: "accepted",
    external_display_name: "Mariana Soares",
    ref_code: "RRR6",
    requested_qty: 1,
  },
];
const accState = Act.commercialState(accepted[0]);
assert(/aguarda pagamento/i.test(accState.label), `aceite label (${accState.label})`);
assert(Act.activeFaceReserveCount(accepted) === 1, "aceite conta como Face activa");

const sold = [{ id: "d", status: "converted", ref_code: "RRR6", requested_qty: 1 }];
assert(Act.activeFaceReserveCount(sold) === 0, "vendida NÃO conta Face activa");

const prod = { liveItemId: "li6", refCode: "RRR6" };
const sumBag = Act.productCommercialSummary(prod, queueMixed);
assert(/No saco/i.test(sumBag.line), `produto RRR6 no saco (${sumBag.line})`);
const sumCancel = Act.productCommercialSummary(
  { refCode: "RRR5" },
  queueMixed,
);
assert(
  /Disponível/i.test(sumCancel.line) && /cancelad/i.test(sumCancel.sub || ""),
  `produto RRR5 disponível após cancel (${sumCancel.line} / ${sumCancel.sub})`,
);

assert(Act.badgeActionableCount(queueMixed, {
  isPsNeedsReview: () => false,
  canActPending: (r) => String(r.status).toLowerCase() === "pending" && !Act.isBuyerCancelled(r),
}) === 1, "badge actionable = 1");

// Regressão prints 21/09: «5 ccc5» → created + superseded (OCR Soares5) sem fila
function mapJournalCcc(entry) {
  const action = String(entry.action || "").toLowerCase();
  const intent = String(entry.intent || "").toLowerCase();
  if (intent === "cancel" || /cancel/.test(action)) {
    return {
      kind: "warn",
      title: `${entry.buyer} cancelou · ${entry.ref_out}`,
      t: entry.t,
      isReserve: false,
    };
  }
  if (intent === "reserve" || /created|superseded|updated/.test(action)) {
    const verb = action === "superseded" ? "Actualizou reserva" : "Reservou";
    return {
      kind: "ok",
      title: `${entry.buyer} · ${verb} ${entry.ref_out} ×${entry.qty_out}`,
      detail: entry.raw || "",
      t: entry.t,
      isReserve: true,
    };
  }
  return null;
}

const journalCcc5Dup = [
  {
    t: "2026-09-21T10:17:39.000Z",
    ok: true,
    intent: "reserve",
    action: "created",
    buyer: "Mariana Soares",
    ref_out: "CCC5",
    qty_out: 5,
    raw: "Mariana Soares 5 ccc5",
  },
  {
    t: "2026-09-21T10:17:45.000Z",
    ok: true,
    intent: "reserve",
    action: "superseded",
    buyer: "Mariana",
    ref_out: "CCC5",
    qty_out: 5,
    raw: "Mariana Soares5 ccc5",
  },
];
const journalCcc3 = [
  {
    t: "2026-09-21T10:18:18.000Z",
    ok: true,
    intent: "reserve",
    action: "created",
    buyer: "Mariana Soares",
    ref_out: "CCC3",
    qty_out: 1,
    raw: "Mariana Soares ccc3",
  },
  {
    t: "2026-09-21T10:18:27.000Z",
    ok: true,
    intent: "cancel",
    action: "cancelled",
    buyer: "Mariana Soares",
    ref_out: "CCC3",
    qty_out: 1,
    raw: "Mariana Soares cancela ccc3",
  },
];

assert(
  Act.sameJournalEntity(journalCcc5Dup[0], journalCcc5Dup[1]),
  "Mariana Soares ≈ Mariana · mesma REF CCC5",
);
assert(
  Act.canonicalReserveCount({ queueRows: [], journal: journalCcc5Dup }) === 1,
  "Face journal «5 ccc5» create+supersede = 1",
);
const ccc5Feeds = Act.buildCommercialFeeds({
  journal: journalCcc5Dup,
  queueRows: [],
  mapJournalEntry: mapJournalCcc,
});
assert(
  ccc5Feeds.activity.length === 1,
  `CCC5 actividade = 1 linha (got ${ccc5Feeds.activity.length})`,
);
assert(
  ccc5Feeds.reserves.length === 1,
  `CCC5 reservas feed = 1 (got ${ccc5Feeds.reserves.length})`,
);
assert(
  /Reservou/i.test(ccc5Feeds.activity[0].title) &&
    !/Actualizou/i.test(ccc5Feeds.activity[0].title),
  `CCC5 título = Reservou (${ccc5Feeds.activity[0].title})`,
);
assert(
  /×5/.test(ccc5Feeds.activity[0].title),
  `CCC5 qty ×5 (${ccc5Feeds.activity[0].title})`,
);

const cccFull = Act.buildCommercialFeeds({
  journal: [...journalCcc5Dup, ...journalCcc3],
  queueRows: [],
  mapJournalEntry: mapJournalCcc,
});
assert(
  cccFull.activity.length === 3,
  `CCC5+CCC3: 3 linhas (1 CCC5 + reservou+cancel CCC3) got ${cccFull.activity.length}`,
);
assert(
  Act.canonicalReserveCount({
    queueRows: [],
    journal: [...journalCcc5Dup, ...journalCcc3],
  }) === 1,
  "após cancel CCC3, Face = 1 (só CCC5)",
);

if (failed) {
  console.error(`\n${failed} FAIL`);
  process.exit(1);
}
console.log("\nAll activity model tests PASS");
