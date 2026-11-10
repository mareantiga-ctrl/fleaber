/**
 * Regressão v1.7.19 — chat Facebook curto/médio + autor + comerciais.
 *
 * Sequência (pedido C1):
 *   teste, rrr6, rrr5, esta mensagem normal deve aparecer,
 *   cancela rrr5, teste, bla bla, palavras curtas nao aparecem, ok, sim
 *
 * node tool/fleaber_ps_extension/test_chat_short_messages.mjs
 */
import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";
import vm from "node:vm";

const __dirname = dirname(fileURLToPath(import.meta.url));
let failed = 0;
function assert(cond, msg) {
  if (!cond) {
    failed += 1;
    console.error(`FAIL: ${msg}`);
  } else {
    console.log(`PASS: ${msg}`);
  }
}

// --- Parser ---
let parserCode = readFileSync(join(__dirname, "parser.js"), "utf8");
parserCode = parserCode.replace(
  /\nexport\s*\{[\s\S]*$/m,
  "\nglobalThis.parseCommentLine = parseCommentLine;\n",
);
const tmp = join(__dirname, "_tmp_short_parser.cjs");
writeFileSync(tmp, parserCode, "utf8");
createRequire(import.meta.url)(tmp);
unlinkSync(tmp);
const parse = globalThis.parseCommentLine;

// --- Chat display model ---
const chatSrc = readFileSync(join(__dirname, "studio_chat_model.js"), "utf8");
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
vm.runInContext(chatSrc, sandbox);
const Chat = sandbox.FleaberStudioChat;

// --- Extract normalize helpers from content.js (sem DOM) ---
const contentSrc = readFileSync(join(__dirname, "content.js"), "utf8");

function extractFn(src, name) {
  const re = new RegExp(
    `function ${name}\\s*\\([^{]*\\{`,
    "m",
  );
  const m = re.exec(src);
  if (!m) throw new Error(`function ${name} not found`);
  let i = m.index + m[0].length - 1;
  let depth = 0;
  for (; i < src.length; i += 1) {
    const c = src[i];
    if (c === "{") depth += 1;
    else if (c === "}") {
      depth -= 1;
      if (depth === 0) {
        return src.slice(m.index, i + 1);
      }
    }
  }
  throw new Error(`unbalanced ${name}`);
}

function extractFnOrConst(src, name) {
  try {
    return extractFn(src, name);
  } catch {
    const re = new RegExp(
      `(?:const|let|var)\\s+${name}\\s*=\\s*function[^{]*\\{`,
      "m",
    );
    const m = re.exec(src);
    if (!m) throw new Error(`${name} not found`);
    let i = m.index + m[0].length - 1;
    let depth = 0;
    for (; i < src.length; i += 1) {
      if (src[i] === "{") depth += 1;
      else if (src[i] === "}") {
        depth -= 1;
        if (depth === 0) return src.slice(m.index, i + 1);
      }
    }
    throw new Error(`unbalanced ${name}`);
  }
}

// stripFbUi is needed by normalize
function findStripFbUi(src) {
  return extractFn(src, "stripFbUi");
}

const helperSandbox = { console };
helperSandbox.globalThis = helperSandbox;
vm.createContext(helperSandbox);
vm.runInContext(
  [
    findStripFbUi(contentSrc),
    extractFn(contentSrc, "looksLikePersonNameLine"),
    extractFn(contentSrc, "normalizeFbCommentBlock"),
    "globalThis.looksLikePersonNameLine = looksLikePersonNameLine;",
    "globalThis.normalizeFbCommentBlock = normalizeFbCommentBlock;",
    "globalThis.stripFbUi = stripFbUi;",
  ].join("\n"),
  helperSandbox,
);
const normalize = helperSandbox.normalizeFbCommentBlock;
const looksLike = helperSandbox.looksLikePersonNameLine;

// --- A) normalize: short / medium must NOT empty ---
const fbBlocks = [
  {
    id: "teste",
    raw: "Mariana Soares\n1 min\nteste\nGosto\nResponder",
  },
  {
    id: "bla bla",
    raw: "Mariana Soares\n1 min\nbla bla\nGosto\nResponder",
  },
  {
    id: "palavras curtas",
    raw: "Mariana Soares\n1 min\npalavras curtas nao aparecem\nGosto\nResponder",
  },
  {
    id: "ok",
    raw: "Mariana Soares\n1 min\nok\nGosto\nResponder",
  },
  {
    id: "sim",
    raw: "Mariana Soares\n1 min\nsim\nGosto\nResponder",
  },
  {
    id: "rrr6",
    raw: "Mariana Soares\n1 min\nrrr6\nGosto\nResponder",
  },
  {
    id: "cancela",
    raw: "Mariana Soares\n1 min\ncancela rrr5\nGosto\nResponder",
  },
];

for (const b of fbBlocks) {
  const out = normalize(b.raw);
  assert(!!out && out.length >= 1, `normalize «${b.id}» não vazio (got ${JSON.stringify(out)})`);
  assert(
    /mariana/i.test(out) || /teste|bla|palavras|ok|sim|rrr|cancela/i.test(out),
    `normalize «${b.id}» conserva conteúdo útil: ${out}`,
  );
}

assert(
  !looksLike("bla bla"),
  "looksLikePersonNameLine('bla bla') = false (não é nome)",
);
assert(
  !looksLike("palavras curtas nao aparecem"),
  "looksLikePersonNameLine frase média = false",
);
assert(
  looksLike("Mariana Soares"),
  "looksLikePersonNameLine('Mariana Soares') = true",
);

// --- B) sequência completa → Chat 10 + comerciais ---
const AUTHOR = "Mariana Soares";
const sequence = [
  { body: "teste", uid: "c1" },
  { body: "rrr6", uid: "c2" },
  { body: "rrr5", uid: "c3" },
  { body: "esta mensagem normal deve aparecer", uid: "c4" },
  { body: "cancela rrr5", uid: "c5" },
  { body: "teste", uid: "c6" },
  { body: "bla bla", uid: "c7" },
  { body: "palavras curtas nao aparecem", uid: "c8" },
  { body: "ok", uid: "c9" },
  { body: "sim", uid: "c10" },
];

const journal = [];
const transcript = [];
const commercial = [];
let t0 = Date.parse("2026-09-21T09:33:00Z");

for (let i = 0; i < sequence.length; i += 1) {
  const { body, uid } = sequence[i];
  const raw = `${AUTHOR} ${body}`;
  const t = new Date(t0 + i * 5000).toISOString();
  const p = parse(raw);

  transcript.push({
    t: Date.parse(t),
    uid,
    buyer: AUTHOR,
    text: raw,
  });

  if (p && (p.intent === "reserve" || p.intent === "cancel")) {
    commercial.push({ body, intent: p.intent, ref: p.refSlug });
    journal.push({
      t,
      ok: true,
      action: p.intent === "cancel" ? "cancelled" : "reserved",
      intent: p.intent,
      buyer: AUTHOR,
      raw,
      comment_uid: uid,
      ref_slug: p.refSlug,
    });
  } else {
    journal.push({
      t,
      ok: true,
      action: "skipped_chat",
      intent: "chat",
      buyer: AUTHOR,
      raw,
      comment_uid: uid,
    });
  }
}

const chat = Chat.buildUnifiedChat({
  hubMessages: [],
  journal,
  transcript,
  limit: 80,
});

// MVP: só 3 comerciais no Chat
assert(chat.length === 3, `Chat MVP tem 3 comerciais (got ${chat.length})`);
const bodies = chat.map((m) => m.body.toLowerCase());
assert(!bodies.some((b) => b === "teste" || b.endsWith(" teste")), "teste fora");
assert(!bodies.some((b) => /bla bla/.test(b)), "bla bla fora");
assert(!bodies.some((b) => /palavras curtas/.test(b)), "chat social fora");
assert(bodies.some((b) => /rrr6/.test(b) && !/cancela/.test(b)), "rrr6 no Chat");
assert(bodies.some((b) => /rrr5/.test(b) && !/cancela/.test(b)), "rrr5 no Chat");
assert(bodies.some((b) => /cancela rrr5/.test(b)), "cancela rrr5 no Chat");

assert(
  commercial.filter((c) => c.intent === "reserve" && /rrr6/i.test(c.ref || c.body))
    .length === 1,
  "rrr6 → reserve",
);
assert(
  commercial.filter((c) => c.intent === "reserve" && /rrr5/i.test(c.ref || c.body))
    .length === 1,
  "rrr5 → reserve",
);
assert(
  commercial.filter((c) => c.intent === "cancel").length === 1,
  "cancela rrr5 → cancel",
);
assert(commercial.length === 3, `exactamente 3 acções comerciais (got ${commercial.length})`);

assert(
  chat.every((m) => /mariana/i.test(m.name)),
  "autor Mariana Soares nas reservas",
);

// Capture/normalize ainda aceita curtas (pipeline) — só o DISPLAY MVP as esconde
assert(
  !!normalize("Mariana Soares\n1 min\nteste\nGosto\nResponder"),
  "normalize ainda captura «teste» (pipeline intacto)",
);

const orphan = Chat.buildUnifiedChat({
  hubMessages: [],
  journal: [
    {
      t: new Date().toISOString(),
      ok: true,
      intent: "reserve",
      action: "created",
      buyer: null,
      raw: "Mariana Soares rrr6",
      comment_uid: "o1",
    },
  ],
  transcript: [
    {
      t: Date.now(),
      uid: "orphan1",
      buyer: null,
      text: "Mariana Soares afinal ja aparecem, apenas a mensagem Teste nao apareceu",
    },
  ],
  limit: 40,
});
assert(orphan.length === 1, "só reserva órfã (social transcript fora)");
assert(/mariana/i.test(orphan[0].name), `autor da reserva (got «${orphan[0].name}»)`);
assert(/rrr6/i.test(orphan[0].body), "corpo = reserva");

assert(
  /function looksLikePersonNameLine/.test(contentSrc),
  "content.js: looksLikePersonNameLine",
);
assert(
  /function ensureHumanChatEntry/.test(contentSrc),
  "content.js: ensureHumanChatEntry (null parse → chat)",
);
assert(
  /function pushChatTrace/.test(contentSrc),
  "content.js: pushChatTrace",
);
assert(
  /psChatTrace/.test(contentSrc),
  "content.js: persiste psChatTrace",
);
assert(
  /ensureHumanChatEntry\(cfg,\s*text,\s*commentUid,\s*lh,\s*null\)/.test(
    contentSrc,
  ),
  "content.js: null parse sem LLM → ensureHumanChatEntry",
);

const studioHtml = readFileSync(join(__dirname, "studio.html"), "utf8");
assert(
  /FB CHAT TRACE/.test(studioHtml),
  "studio.html: secção FB CHAT TRACE (Modo Técnico)",
);

const manifest = JSON.parse(
  readFileSync(join(__dirname, "manifest.json"), "utf8"),
);
assert(manifest.version === "1.7.29", `manifest ${manifest.version} === 1.7.29`);

if (failed) {
  console.error(`\n${failed} FAIL(s)`);
  process.exit(1);
}
console.log("\nOK — MVP chat só comerciais + pipeline curto intacto");
process.exit(0);
