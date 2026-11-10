/**
 * Regressão qty + contrato Face «quero» obrigatório.
 * node tool/fleaber_ps_extension/test_parser_qty_shorthand.mjs
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const __dirname = dirname(fileURLToPath(import.meta.url));
let code = readFileSync(join(__dirname, "parser.js"), "utf8");
code = code.replace(
  /\nexport\s*\{[\s\S]*$/m,
  "\nglobalThis.parseCommentLine = parseCommentLine;\nglobalThis.normalizeOcrLine = normalizeOcrLine;\n",
);
const sandbox = { console, globalThis: {} };
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(code, sandbox);
const parse = sandbox.parseCommentLine;

let failed = 0;
function assert(cond, msg) {
  if (!cond) {
    failed += 1;
    console.error(`FAIL: ${msg}`);
  } else {
    console.log(`PASS: ${msg}`);
  }
}

// Reserva: verbo obrigatório («quero T10» / «quero 5 T10»)
const reserveOk = [
  ["quero 5 ccc3", 5, "ccc3"],
  ["Mariana Soares quero 5 ccc3", 5, "ccc3"],
  ["quero ccc3", 1, "ccc3"],
  ["quero T10", 1, "T10"],
  ["quero 5 T10", 5, "T10"],
  ["Mariana Soares quero 2 T09", 2, "T09"],
];
for (const [line, qty, ref] of reserveOk) {
  const p = parse(line);
  assert(
    !!p &&
      p.intent === "reserve" &&
      p.quantity === qty &&
      String(p.refSlug || "").toLowerCase() === ref.toLowerCase(),
    `RESERVE ${JSON.stringify(line)} → qty=${qty} ref=${ref} (got ${p?.intent}/${p?.quantity}/${p?.refSlug})`,
  );
}

// Sem «quero» → chat (não reserva)
const mustChat = [
  "5 ccc3",
  "ccc3",
  "t10",
  "2 t09",
  "Mariana Soares t10",
  "Mariana Soares 2 t09",
  "pa so ehhjr najder enjkad t07",
  "3 3ccc",
  "3ccc",
];
for (const line of mustChat) {
  const p = parse(line);
  const ok =
    !p ||
    p.intent === "chat" ||
    (p.intent === "reserve" && p.reason === "reserve_requires_verb");
  // parseCommentLine devolve intent chat
  assert(
    p && p.intent === "chat",
    `CHAT ${JSON.stringify(line)} → chat (got ${p?.intent}/${p?.refSlug}/qty=${p?.quantity})`,
  );
}

// Cancela REF → cancel (todas as unidades no ingest)
const cancelOk = [
  ["cancela T10", "T10"],
  ["Mariana Soares cancela T10", "T10"],
  ["cancela ccc3", "ccc3"],
];
for (const [line, ref] of cancelOk) {
  const p = parse(line);
  assert(
    !!p &&
      p.intent === "cancel" &&
      String(p.refSlug || "").toLowerCase() === ref.toLowerCase(),
    `CANCEL ${JSON.stringify(line)} → ${ref} (got ${p?.intent}/${p?.refSlug})`,
  );
}

// Nome glue regressão
const nameCases = [
  ["Mariana Soarespa eu quero o ccc1, guarda para mim", "Mariana Soares", "ccc1"],
  ["Mariana Soares pa eu quero o ccc1", "Mariana Soares", "ccc1"],
];
for (const [line, name, ref] of nameCases) {
  const p = parse(line);
  assert(
    !!p &&
      p.intent === "reserve" &&
      (p.displayName || null) === name &&
      String(p.refSlug || "").toLowerCase() === ref.toLowerCase(),
    `name ${JSON.stringify(line)} → ${JSON.stringify(name)}/${ref} (got ${JSON.stringify(p?.displayName)}/${p?.refSlug})`,
  );
}

// Lixo «so … t07» NÃO pode virar qty=7
{
  const p = parse("pa so ehhjr najder enjkad t07");
  assert(
    p && p.intent === "chat",
    `so+t07 → chat não qty7 (got ${p?.intent} qty=${p?.quantity})`,
  );
}

if (failed) {
  console.error(`\n${failed} FAIL`);
  process.exit(1);
}
console.log("\nAll qty/quero-contract tests PASS");
