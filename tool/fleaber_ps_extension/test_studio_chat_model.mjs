/**
 * Chat MVP v1.7.21 — só reservas/cancelamentos no Studio Chat.
 * Chat social (transcript / skipped_chat) fica fora até pós-MVP.
 * node tool/fleaber_ps_extension/test_studio_chat_model.mjs
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const __dirname = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(__dirname, "studio_chat_model.js"), "utf8");
const sandbox = {
  console,
  Date,
  Math,
  JSON,
  Number,
  String,
  Array,
  Object,
  Map,
  Set,
};
sandbox.globalThis = sandbox;
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(src, sandbox);

const Chat = sandbox.FleaberStudioChat;
let failed = 0;
function assert(cond, msg) {
  if (!cond) {
    failed += 1;
    console.error(`FAIL: ${msg}`);
  } else {
    console.log(`PASS: ${msg}`);
  }
}

assert(!!Chat, "FleaberStudioChat carregou");

const hub = [
  {
    id: "h1",
    kind: "chat",
    channel: "fleaber",
    body: "Olá do Hub",
    sender_label: "Ana",
    created_at: "2026-09-20T14:00:00.000Z",
  },
  {
    id: "h-fb",
    kind: "chat",
    channel: "facebook",
    body: "teste via hub fb",
    sender_label: "Mariana",
    created_at: "2026-09-20T14:01:00.000Z",
  },
  {
    id: "h3",
    kind: "system",
    channel: "fleaber",
    body: "Mariana Soares reservou Ref RRR6",
    sender_label: "Sistema",
    created_at: "2026-09-20T14:37:35.000Z",
  },
];

const transcript = [
  {
    n: 1,
    t: Date.parse("2026-09-20T15:31:00Z"),
    buyer: "Mariana Soares",
    text: "Mariana Soares teste",
  },
  {
    n: 2,
    t: Date.parse("2026-09-20T15:31:20Z"),
    buyer: "Mariana Soares",
    text: "Mariana Soares boa tarde",
  },
  {
    n: 3,
    t: Date.parse("2026-09-20T15:31:40Z"),
    buyer: "Mariana Soares",
    text: "Mariana Soares quero rrr6",
  },
];

const journal = [
  {
    t: "2026-09-20T15:31:00.000Z",
    ok: true,
    intent: "chat",
    action: "skipped_chat",
    buyer: "Mariana Soares",
    raw: "Mariana Soares teste",
  },
  {
    t: "2026-09-20T15:31:40.100Z",
    ok: true,
    intent: "reserve",
    action: "created",
    buyer: "Mariana Soares",
    raw: "Mariana Soares quero rrr6",
    comment_uid: "c-rrr6",
  },
];

const items = Chat.buildUnifiedChat({
  hubMessages: hub,
  journal,
  transcript,
  limit: 40,
});

assert(
  !items.some((m) => /teste/i.test(m.body)),
  "MVP: «teste» NÃO aparece (transcript/skipped_chat fora)",
);
assert(
  !items.some((m) => /boa tarde/i.test(m.body)),
  "MVP: chat social fora",
);
assert(
  items.filter((m) => /quero rrr6/i.test(m.body)).length === 1,
  "reserva aparece uma vez (journal comercial)",
);
assert(
  !items.some((m) => /reservou Ref/i.test(m.body)),
  "system filtrado",
);
assert(
  !items.some((m) => /teste via hub fb/i.test(m.body)),
  "MVP: hub channel=facebook fora",
);
assert(
  items.some((m) => m.origin === "fleaber" && m.body === "Olá do Hub"),
  "Fleaber hub presente",
);

// Dirty still filtered if somehow commercial
const dirtyItems = Chat.buildUnifiedChat({
  hubMessages: [],
  journal: [
    {
      t: "2026-09-20T16:00:00Z",
      ok: true,
      intent: "reserve",
      action: "created",
      buyer: "X",
      raw: "comentario",
    },
  ],
  transcript: [],
  limit: 20,
});
assert(
  !dirtyItems.some((m) => /^(comentario)$/i.test(m.body)),
  "«comentario» sujo filtrado",
);

// Cancel commercial
const cancelItems = Chat.buildUnifiedChat({
  hubMessages: [],
  journal: [
    {
      t: "2026-09-20T16:10:00Z",
      ok: true,
      intent: "cancel",
      action: "cancelled",
      buyer: "Mariana Soares",
      raw: "Mariana Soares cancela rrr6",
      comment_uid: "c-cancel",
    },
  ],
  transcript: [{ text: "Mariana Soares blabla", buyer: "Mariana Soares", t: Date.now() }],
  limit: 20,
});
assert(cancelItems.length === 1, "só 1 linha (cancel; blabla ignorado)");
assert(/cancela rrr6/i.test(cancelItems[0].body), "cancel no Chat");

assert(
  /MVP|só eventos comerciais|pós-MVP/i.test(src),
  "comentário MVP no modelo",
);

if (failed) {
  console.error(`\n${failed} FAIL(s)`);
  process.exit(1);
}
console.log("\nAll chat model tests PASS (MVP comercial)");
process.exit(0);
