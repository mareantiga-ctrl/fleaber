/**
 * Probe parser (sem alterar regras) — tipografia cancelamento.
 * node tool/fleaber_ps_extension/probe_parser_cancel.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { createRequire } from "node:module";

const __dirname = dirname(fileURLToPath(import.meta.url));
let code = readFileSync(join(__dirname, "parser.js"), "utf8");
// Chrome content scripts don't use ESM; strip export for Node probe.
code = code.replace(/\nexport\s*\{[\s\S]*$/m, "\nglobalThis.parseCommentLine = parseCommentLine;\n");
const tmp = join(__dirname, "_probe_parser_tmp.cjs");
writeFileSync(tmp, code, "utf8");
const require = createRequire(import.meta.url);
require(tmp);

const parse = globalThis.parseCommentLine;
const lines = [
  "cacela rrr6",
  "cancela rrr6",
  "quero rrr6",
  "teste",
  "boa tarde",
];

for (const t of lines) {
  const r = typeof parse === "function" ? parse(t) : null;
  console.log(
    JSON.stringify({
      t,
      intent: r?.intent ?? null,
      ref: r?.refSlug ?? null,
      name: r?.displayName ?? null,
      reason: r?.reason ?? null,
    }),
  );
}

try {
  const { unlinkSync } = await import("node:fs");
  unlinkSync(tmp);
} catch (_) {}
