/**
 * Graph / Meta: strictRef + catálogo do directo (123, #123, T10).
 * Correr: node tool/fleaber_ps_extension/test_graph_catalog_strict.mjs
 *
 * Valida a cópia edge (`fleaber_ps_parser.js`) e a extensão (`parser.js`).
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..", "..");

function loadParse(relPath) {
  let code = readFileSync(join(repoRoot, relPath), "utf8");
  code = code.replace(
    /\nexport\s*\{[\s\S]*$/m,
    "\nglobalThis.parseCommentLine = parseCommentLine;\n" +
      "globalThis.applyStrictRef = applyStrictRef;\n" +
      "globalThis.findBareCatalogRefsInLine = findBareCatalogRefsInLine;\n" +
      "globalThis.catalogRefSet = catalogRefSet;\n",
  );
  const sandbox = { console, globalThis: {} };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox);
  return sandbox.parseCommentLine;
}

const parsers = [
  ["edge/_shared", loadParse("supabase/functions/_shared/fleaber_ps_parser.js")],
  ["extension", loadParse("tool/fleaber_ps_extension/parser.js")],
];

const catalogHash = [
  { ref_code: "#123", title: "Artigo 123" },
  { ref_code: "T10", title: "Tee 10" },
];
const catalogPlain = [
  { ref_code: "123", title: "Artigo 123" },
  { ref_code: "T10", title: "Tee 10" },
];

let failed = 0;
function assert(cond, msg) {
  if (!cond) {
    failed += 1;
    console.error(`FAIL: ${msg}`);
  } else {
    console.log(`PASS: ${msg}`);
  }
}

function expectReserve(parse, line, catalog, refNorm, label) {
  const p = parse(line, { strictRef: true, catalog });
  const got = String(p?.refSlug ?? "")
    .trim()
    .toUpperCase()
    .replace(/^#/, "");
  assert(
    !!p &&
      p.intent === "reserve" &&
      got === String(refNorm).toUpperCase() &&
      (p.reason === "strict_catalog_ref" ||
        p.reason === "strict_ref_word" ||
        !p.reason),
    `${label}: ${JSON.stringify(line)} → reserve ${refNorm} (got ${p?.intent}/${p?.refSlug}/${p?.reason})`,
  );
}

function expectChat(parse, line, catalog, label, reasonHint) {
  const p = parse(line, { strictRef: true, catalog });
  const reasonOk = !reasonHint || String(p?.reason || "").includes(reasonHint);
  assert(
    !!p && p.intent === "chat" && reasonOk,
    `${label}: ${JSON.stringify(line)} → chat${reasonHint ? ` (${reasonHint})` : ""} (got ${p?.intent}/${p?.refSlug}/${p?.reason})`,
  );
}

for (const [name, parse] of parsers) {
  console.log(`\n=== ${name} ===`);

  // Com catálogo #123: aceitar 123 e #123
  expectReserve(parse, "quero 123", catalogHash, "123", name);
  expectReserve(parse, "quero #123", catalogHash, "123", name);
  expectReserve(parse, "quero 2 123", catalogHash, "123", name);
  expectReserve(parse, "quero T10", catalogHash, "T10", name);
  expectReserve(parse, "quero 5 T10", catalogHash, "T10", name);
  expectReserve(parse, "quero REF T10", catalogHash, "T10", name);

  // Catálogo sem #: idem
  expectReserve(parse, "quero 123", catalogPlain, "123", name);
  expectReserve(parse, "quero #123", catalogPlain, "123", name);

  // Sem catálogo: bare numérico / T10 → chat (não inventar)
  expectChat(parse, "quero 123", [], name, "strict_no_ref");
  expectChat(parse, "quero #123", null, name, "strict_no_ref");
  expectChat(parse, "quero T10", [], name, "strict_no_ref");

  // Ref inexistente no catálogo → chat (não reservar)
  expectChat(parse, "quero 999", catalogHash, name, "strict_no_ref");
  expectChat(parse, "quero Z99", catalogHash, name, "strict_no_ref");
  expectChat(parse, "quero REF Z99", catalogHash, name, "strict_ref_not_in_catalog");

  // Sem verbo → não reserva (null ou chat; contrato Face)
  {
    const p = parse("123", { strictRef: true, catalog: catalogHash });
    assert(
      !p || p.intent === "chat",
      `${name}: "123" alone → not reserve (got ${p?.intent})`,
    );
  }
  expectChat(parse, "T10", catalogHash, name, null);

  // Qty
  const q = parse("quero 3 123", { strictRef: true, catalog: catalogHash });
  assert(
    q?.intent === "reserve" && Number(q.quantity) === 3,
    `${name}: quero 3 123 → qty 3 (got ${q?.quantity})`,
  );
}

// --- buildGraphIngestRpc contract (catalog remap #123) ---
console.log("\n=== buildGraphIngestRpc (logic mirror) ===");
{
  const parse = parsers[0][1];
  const message = "quero 123";
  const catalog = catalogHash;
  const parsed = parse(message, { strictRef: true, catalog });
  let pRefSlug = parsed?.refSlug ?? null;
  if (pRefSlug && catalog.length) {
    const want = String(pRefSlug).trim().toUpperCase().replace(/^#/, "");
    const hit = catalog.find((it) => {
      const raw = String(it?.ref_code ?? "").trim();
      const norm = raw.toUpperCase().replace(/^#/, "");
      return norm === want;
    });
    if (hit) {
      const canonical = String(hit.ref_code ?? "").trim();
      if (canonical) pRefSlug = canonical;
    }
  }
  assert(
    parsed?.intent === "reserve" && pRefSlug === "#123",
    `Graph remap: quero 123 + catalog #123 → p_ref_slug=#123 (got ${parsed?.intent}/${pRefSlug})`,
  );

  const noHit = parse("quero 999", { strictRef: true, catalog });
  assert(
    noHit?.intent === "chat",
    `Graph: quero 999 not in catalog → chat (got ${noHit?.intent})`,
  );
}

if (failed) {
  console.error(`\n${failed} failed`);
  process.exit(1);
}
console.log("\nAll graph catalog strict tests passed.");
