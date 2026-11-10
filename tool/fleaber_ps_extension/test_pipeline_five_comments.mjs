/**
 * Regressão exacta do teste real v1.7.16:
 * teste → rrr6 → teste → rrr4 → cancela rrr6
 *
 * Cobre o caminho que falhou: parser intent=chat sem journal → Chat vazio para «teste».
 * node tool/fleaber_ps_extension/test_pipeline_five_comments.mjs
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

// Parser
let parserCode = readFileSync(join(__dirname, "parser.js"), "utf8");
parserCode = parserCode.replace(
  /\nexport\s*\{[\s\S]*$/m,
  "\nglobalThis.parseCommentLine = parseCommentLine;\n",
);
const tmp = join(__dirname, "_tmp_five_parser.cjs");
writeFileSync(tmp, parserCode, "utf8");
createRequire(import.meta.url)(tmp);
unlinkSync(tmp);
const parse = globalThis.parseCommentLine;

// Chat display
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

// isSocialChat (replica content.js — cumprimentos only)
function isSocialChat(text) {
  const parts = String(text || "").trim().split(/\s+/);
  let body = text;
  if (parts.length >= 2) {
    for (let n = Math.min(3, parts.length - 1); n >= 1; n -= 1) {
      const name = parts.slice(0, n).join(" ");
      const b = parts.slice(n).join(" ");
      if (/^[A-Za-zÀ-ú]/.test(name) && b) {
        body = b;
        break;
      }
    }
  }
  const work = (body || text || "").trim().toLowerCase();
  if (!work) return true;
  if (
    /\b(quero|queria|kero|qero|cancela|tira|retira|afinal|apenas|troca|mesminho|o\s+mesmo|tamb[eé]m|mais\s+um)\b/i.test(
      work,
    )
  ) {
    return false;
  }
  if (/\b(AM|KK|CB|CM|HS|RF|TT|FX|PT)\s*\d{1,4}\b/i.test(work)) return false;
  if (/\b\d{3}\/\d+\b/.test(work)) return false;
  if (/^\d{1,2}$/.test(work)) return false;
  return /^(bom\s+dia|boa\s+tarde|boa\s+noite|ola|olá|oi|hey|hello|obrigad[oa]|obrigado|valeu|ok|okay|perfeito|fixe|top|ainda\s+tem\s+stock|quanto\s+custa|podes\s+separar|ainda\s+da|fechado|fechou)([\s!.?]|$)/i.test(
    work,
  );
}

/**
 * Simula harvest + processOneComment journal/transcript (v1.7.17).
 * NÃO injeta Chat já normalizado — gera as mesmas estruturas que content.js.
 */
function simulateSession(rawLines) {
  const transcript = [];
  const journal = [];
  const commercial = [];
  let t0 = Date.parse("2026-09-20T18:00:00.000Z");

  rawLines.forEach((body, i) => {
    const line = `Mariana Soares ${body}`;
    const uid = `fb_comment_${i + 1}`;
    const t = t0 + i * 5000; // 5s apart — dois «teste» distintos
    // A) harvest → transcript (sempre)
    transcript.push({
      n: i + 1,
      t,
      uid,
      buyer: "Mariana Soares",
      text: line,
    });

    const social = isSocialChat(line);
    const parsed = parse(line) || { intent: "chat", displayName: "Mariana Soares" };

    // B) process path
    if (social || parsed.intent === "chat" || !parsed.intent) {
      // v1.7.17: journal skipped_chat (v1.7.16 NÃO fazia isto para intent=chat)
      journal.push({
        t: new Date(t + 10).toISOString(),
        ok: true,
        intent: "chat",
        action: "skipped_chat",
        buyer: parsed.displayName || "Mariana Soares",
        raw: line,
        comment_uid: uid,
      });
      commercial.push({ body, action: "none" });
      return;
    }
    if (parsed.intent === "reserve") {
      journal.push({
        t: new Date(t + 10).toISOString(),
        ok: true,
        intent: "reserve",
        action: "created",
        buyer: parsed.displayName || "Mariana Soares",
        raw: line,
        ref: parsed.refSlug,
        comment_uid: uid,
      });
      commercial.push({
        body,
        action: "reserve",
        ref: String(parsed.refSlug || "").toUpperCase(),
      });
      return;
    }
    if (parsed.intent === "cancel") {
      journal.push({
        t: new Date(t + 10).toISOString(),
        ok: true,
        intent: "cancel",
        action: "cancelled",
        buyer: parsed.displayName || "Mariana Soares",
        raw: line,
        ref: parsed.refSlug,
        comment_uid: uid,
      });
      commercial.push({
        body,
        action: "cancel",
        ref: String(parsed.refSlug || "").toUpperCase(),
      });
    }
  });

  const chat = Chat.buildUnifiedChat({
    hubMessages: [],
    journal,
    transcript,
    limit: 40,
  });

  return { transcript, journal, commercial, chat };
}

// ——— Prova regressão v1.7.16 ———
assert(
  isSocialChat("Mariana Soares teste") === false,
  "«teste» NÃO é isSocialChat (whitelist cumprimentos) — ia ao parser",
);
const pTeste = parse("Mariana Soares teste");
assert(
  pTeste?.intent === "chat" || !pTeste?.refSlug,
  `parser «teste» → chat/sem ref (got ${pTeste?.intent})`,
);

// Simular v1.7.16 bug: intent=chat sem journal
{
  const transcript = [
    { n: 1, t: Date.now(), uid: "1", buyer: "Mariana Soares", text: "Mariana Soares teste" },
    { n: 2, t: Date.now() + 5000, uid: "2", buyer: "Mariana Soares", text: "Mariana Soares rrr6" },
  ];
  const journalOnlyCommercial = [
    {
      t: new Date().toISOString(),
      ok: true,
      intent: "reserve",
      action: "created",
      buyer: "Mariana Soares",
      raw: "Mariana Soares rrr6",
      comment_uid: "2",
    },
  ];
  // Se transcript falhar/atrasar e só houver journal comercial:
  const chatBroken = Chat.buildUnifiedChat({
    hubMessages: [],
    journal: journalOnlyCommercial,
    transcript: [],
    limit: 20,
  });
  assert(
    !chatBroken.some((m) => /teste/i.test(m.body)),
    "MVP: «teste» fora do Chat sem journal comercial",
  );
  assert(
    chatBroken.some((m) => /rrr6/i.test(m.body)),
    "MVP: reserva journal aparece no Chat",
  );
}

// ——— Sessão real dos 5 comentários ———
const session = simulateSession([
  "teste",
  "rrr6",
  "teste",
  "rrr4",
  "cancela rrr6",
]);

console.log("\n--- Trace tabela ---");
console.log(
  "COMMENT | TRANSCRIPT | JOURNAL | PARSER/COMMERCIAL | CHAT",
);
const bodies = ["teste", "rrr6", "teste", "rrr4", "cancela rrr6"];
bodies.forEach((b, i) => {
  const tr = session.transcript[i];
  const j = session.journal.find((e) => e.comment_uid === tr.uid);
  const c = session.commercial[i];
  const inChat = session.chat.filter((m) =>
    normMatch(m.body, b),
  );
  console.log(
    `${b.padEnd(14)} | yes | ${j?.action || "?"} | ${c.action}${c.ref ? " " + c.ref : ""} | chatHits=${inChat.length}`,
  );
});

function normMatch(body, expect) {
  const b = String(body || "").toLowerCase().replace(/\s+/g, " ").trim();
  const e = String(expect || "").toLowerCase().trim();
  return b === e || b.endsWith(e);
}

// MVP Chat = só 3 comerciais
assert(
  session.chat.length === 3,
  `Chat MVP tem 3 comerciais (got ${session.chat.length})`,
);
assert(
  !session.chat.some((m) => {
    const b = String(m.body || "").toLowerCase().replace(/\s+/g, " ").trim();
    return b === "teste" || b.endsWith(" teste");
  }),
  "teste fora do Chat MVP",
);
assert(
  session.chat.some((m) => /rrr6/i.test(m.body) && !/cancela/i.test(m.body)),
  "rrr6 no Chat",
);
assert(session.chat.some((m) => /rrr4/i.test(m.body)), "rrr4 no Chat");
assert(
  session.chat.some((m) => /cancela rrr6/i.test(m.body)),
  "cancela rrr6 no Chat",
);

assert(session.commercial[0].action === "none", "teste#1 → nenhuma acção");
assert(
  session.commercial[1].action === "reserve" &&
    /RRR6/i.test(session.commercial[1].ref),
  "rrr6 → reserve RRR6",
);
assert(session.commercial[2].action === "none", "teste#2 → nenhuma acção");
assert(
  session.commercial[3].action === "reserve" &&
    /RRR4/i.test(session.commercial[3].ref),
  "rrr4 → reserve RRR4",
);
assert(
  session.commercial[4].action === "cancel" &&
    /RRR6/i.test(session.commercial[4].ref),
  "cancela rrr6 → cancel RRR6",
);

// Pipeline continua a gravar skipped_chat (para pós-MVP / TRACE)
const contentSrc = readFileSync(join(__dirname, "content.js"), "utf8");
assert(
  /function ensureHumanChatEntry[\s\S]{0,800}skipped_chat/.test(contentSrc),
  "content.js: ensureHumanChatEntry grava skipped_chat no journal",
);
assert(
  /parsed\.intent === "chat"[\s\S]{0,200}ensureHumanChatEntry/.test(contentSrc),
  "content.js: intent=chat → ensureHumanChatEntry",
);
assert(
  /comment_uid:\s*commentUid/.test(contentSrc),
  "content.js: comment_uid no journal skipped_chat",
);

if (failed) {
  console.error(`\n${failed} FAIL`);
  process.exit(1);
}
console.log("\nAll five-comment pipeline tests PASS (MVP chat = comerciais)");
