/**
 * Regressão integrada pipeline FB → captura gate → parser → chat display.
 * Cobre a falha real v1.7.15 (isDirtyCaptureText no harvest).
 *
 * node tool/fleaber_ps_extension/test_pipeline_fb_fixture.mjs
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

const contentSrc = readFileSync(join(__dirname, "content.js"), "utf8");
const content14 = (() => {
  try {
    return readFileSync(
      join(
        __dirname,
        "../reports/_diff_v1714_extract/content.js",
      ),
      "utf8",
    );
  } catch {
    return "";
  }
})();

// ——— A) Prova da regressão v1.7.15 (filtro no compact da linha inteira) ———
function dirtyFilterV1715Regression(text) {
  const t = String(text || "").trim();
  if (!t) return true;
  const compact = t.replace(/\s+/g, "").toLowerCase();
  if (/\bcomentario\b/i.test(t) && t.split(/\s+/).length <= 5) return true;
  if (/\d+\s*min\.?\s*$/i.test(t) || /\d+min/i.test(compact)) return true;
  if (/1min|soaresteste|soaresrrr|soarescancela/i.test(compact)) return true;
  return false;
}

const cases = [
  { line: "Mariana Soares teste", expectChat: true, expectReserve: false },
  { line: "Mariana Soares boa tarde", expectChat: true, expectReserve: false },
  { line: "Mariana Soares quero rrr6", expectChat: true, expectReserve: true },
  { line: "Mariana Soares rrr6", expectChat: true, expectReserve: true },
  { line: "Mariana Soares cancela rrr6", expectChat: true, expectReserve: false, expectCancel: true },
];

assert(
  dirtyFilterV1715Regression("Mariana Soares teste") === true,
  "v1.7.15 dirty BLOQUEAVA «Mariana Soares teste» (soaresteste no compact)",
);
assert(
  dirtyFilterV1715Regression("Mariana Soares rrr6") === true,
  "v1.7.15 dirty BLOQUEAVA «Mariana Soares rrr6» (soaresrrr)",
);
assert(
  dirtyFilterV1715Regression("Mariana Soares cancela rrr6") === true,
  "v1.7.15 dirty BLOQUEAVA «Mariana Soares cancela rrr6» (soarescancela)",
);

// ——— B) content.js actual NÃO aplica dirty no isNoise / harvest ———
assert(
  !/function isDirtyCaptureText\s*\(/.test(contentSrc),
  "isDirtyCaptureText removido do content.js (restauração pipeline)",
);
assert(
  !/if\s*\(\s*isDirtyCaptureText\s*\(/.test(contentSrc),
  "nenhuma chamada isDirtyCaptureText no content.js",
);
assert(
  /NÃO filtrar aqui por «dirty OCR»|NÃO chamar filtros de display/.test(contentSrc),
  "comentário explícito: filtros dirty fora do pipeline",
);
assert(
  /Convidado.*comentario|comentario`/.test(contentSrc),
  "deep-scan fallback v1.7.14 restaurado (Name comentario)",
);

// Extrair isNoise actual via eval do fragmento
const noiseMatch = contentSrc.match(/function isNoise\(text\) \{[\s\S]*?\n\}/);
assert(!!noiseMatch, "isNoise presente");
const noiseFn = new Function(`${noiseMatch[0]}; return isNoise;`)();
for (const c of cases) {
  assert(
    noiseFn(c.line) === false,
    `isNoise actual PERMITE pipeline: ${c.line}`,
  );
}

// ——— C) Parser (caminho real) ———
let parserCode = readFileSync(join(__dirname, "parser.js"), "utf8");
parserCode = parserCode.replace(
  /\nexport\s*\{[\s\S]*$/m,
  "\nglobalThis.parseCommentLine = parseCommentLine;\n",
);
const tmp = join(__dirname, "_tmp_pipeline_parser.cjs");
writeFileSync(tmp, parserCode, "utf8");
const require = createRequire(import.meta.url);
require(tmp);
unlinkSync(tmp);
const parse = globalThis.parseCommentLine;

function classify(line) {
  const p = parse(line) || {};
  const intent = String(p.intent || "chat").toLowerCase();
  return {
    intent,
    ref: p.refSlug || p.ref_code || null,
    reserve: intent === "reserve",
    cancel: intent === "cancel",
    chatOnly: intent === "chat" || intent === "skip",
  };
}

const pipeline = [];
for (const c of cases) {
  const blockedByRegression = dirtyFilterV1715Regression(c.line);
  const passesNoise = !noiseFn(c.line);
  const cls = classify(c.line);
  const row = {
    line: c.line,
    A_dom: true,
    B_observer: true,
    C_transcript: passesNoise,
    D_normalized: true,
    E_chat_display: passesNoise,
    F_parser: passesNoise,
    G_class: cls.intent,
    H_ollama: "n/a_rules_first",
    I_commercial: passesNoise && (cls.reserve || cls.cancel),
    J_backend_would_call: passesNoise && (cls.reserve || cls.cancel),
    v1715_would_block: blockedByRegression,
  };
  pipeline.push(row);

  assert(passesNoise, `C/F: «${c.line}» entra no transcript+parser`);
  if (c.expectReserve) {
    assert(cls.reserve, `G: «${c.line}» → reserve (got ${cls.intent})`);
  } else if (c.expectCancel) {
    assert(cls.cancel, `G: «${c.line}» → cancel (got ${cls.intent})`);
  } else {
    assert(
      !cls.reserve,
      `G: «${c.line}» NÃO reserve (got ${cls.intent})`,
    );
  }
}

assert(
  pipeline.filter((r) => /quero rrr6/i.test(r.line) && r.I_commercial).length === 1,
  "Cenário quero rrr6: exactamente 1 acção comercial",
);

// ——— D) Display chat limpa sujos SEM bloquear limpos ———
const chatSrc = readFileSync(join(__dirname, "studio_chat_model.js"), "utf8");
const sandbox = { console, Date, Math, JSON, Number, String, Array, Object, Map, Set };
sandbox.globalThis = sandbox;
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(chatSrc, sandbox);
const Chat = sandbox.FleaberStudioChat;

const display = Chat.buildUnifiedChat({
  hubMessages: [],
  journal: [
    {
      t: new Date().toISOString(),
      ok: true,
      intent: "reserve",
      action: "created",
      buyer: "Mariana Soares",
      raw: "Mariana Soares quero rrr6",
      comment_uid: "3",
    },
  ],
  transcript: [
    { n: 1, t: Date.now(), buyer: "Mariana Soares", text: "Mariana Soares teste", uid: "1" },
    { n: 2, t: Date.now() + 1, buyer: "Comprador", text: "Comprador Mariana Soares comentario", uid: "2" },
    { n: 3, t: Date.now() + 2, buyer: "Mariana Soares", text: "Mariana Soares quero rrr6", uid: "3" },
  ],
  limit: 20,
});
assert(
  !display.some((m) => /teste/i.test(m.body)),
  "DISPLAY MVP: teste (social) fora",
);
assert(
  display.some((m) => /quero rrr6/i.test(m.body)),
  "DISPLAY MVP: quero rrr6 (reserva) aparece",
);
assert(
  !display.some((m) => /comentario/i.test(m.body)),
  "DISPLAY: «comentario» sujo filtrado (só display)",
);

// ——— E) Histórico isolado: archive não no content pipeline ———
assert(
  !/archiveAndClearOpsLive|historyViewLiveId/.test(contentSrc),
  "content.js sem lógica de Histórico (isolamento ACTIVE vs HISTORICAL)",
);

console.log("\n--- Pipeline trace (fixture) ---");
console.table(
  pipeline.map((r) => ({
    line: r.line.slice(0, 40),
    transcript: r.C_transcript,
    intent: r.G_class,
    commercial: r.I_commercial,
    v15_blocked: r.v1715_would_block,
  })),
);

if (content14) {
  assert(
    !content14.includes("isDirtyCaptureText"),
    "v1.7.14 baseline: sem isDirtyCaptureText",
  );
}

if (failed) {
  console.error(`\n${failed} FAIL`);
  process.exit(1);
}
console.log("\nAll pipeline fixture tests PASS");
