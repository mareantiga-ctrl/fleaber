/**
 * P4.1 — Build schema baseline SQL via privileged `supabase db query`
 * (no Docker / no pg_dump LOCK). Staging linked project only.
 *
 * Usage: node tool/fase4_dump_schema_via_query.mjs
 */
import { spawnSync } from "child_process";
import {
  writeFileSync,
  mkdirSync,
  mkdtempSync,
  writeFileSync as wfs,
  rmSync,
} from "fs";
import { tmpdir } from "os";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = join(root, "tool", "reports", "fase4_execution_2026-09-13", "P4.1");
const outSql = join(root, "tool", "reports", "fase4_baseline_staging_schema.sql");
mkdirSync(outDir, { recursive: true });

import { mkdtempSync, writeFileSync as wfs, readFileSync, rmSync } from "fs";
import { tmpdir } from "os";

function query(sql) {
  const dir = mkdtempSync(join(tmpdir(), "fase4q-"));
  const file = join(dir, "q.sql");
  wfs(file, sql.endsWith(";") ? sql : sql + ";", "utf8");
  try {
    const r = spawnSync(
      "npx",
      ["supabase", "db", "query", "--linked", "-f", file],
      { cwd: root, encoding: "utf8", maxBuffer: 64 * 1024 * 1024, shell: true },
    );
    const text = `${r.stdout || ""}\n${r.stderr || ""}`;
    if (r.status !== 0 && !text.includes('"rows"')) {
      throw new Error(`db query failed (${r.status}): ${text.slice(0, 800)}`);
    }
    const start = text.indexOf("{");
    if (start < 0) throw new Error(`no JSON in query output: ${text.slice(0, 400)}`);
    // Parse first JSON object (may have trailing noise)
    let depth = 0;
    let end = -1;
    for (let i = start; i < text.length; i++) {
      const c = text[i];
      if (c === "{") depth++;
      else if (c === "}") {
        depth--;
        if (depth === 0) {
          end = i + 1;
          break;
        }
      }
    }
    if (end < 0) throw new Error("unclosed JSON");
    const json = JSON.parse(text.slice(start, end));
    if (json._tag === "Error" || json.error) {
      throw new Error(JSON.stringify(json.error || json));
    }
    return json.rows || [];
  } finally {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
  }
}

function writeSqlFile(chunks) {
  const header = [
    "-- =============================================================================",
    "-- Fleaber P4.1 baseline schema (staging fxdknzrqjenzqcvnwqqq)",
    `-- Generated: ${new Date().toISOString()}`,
    "-- Method: supabase db query (privileged) — NOT full pg_dump",
    "-- Limits: CREATE TABLE bodies are NOT emitted (need pg_dump/Docker or DB password).",
    "--         Includes: extensions list, views, functions, policies (best-effort).",
    "-- Prod apply: prefer a true pg_dump when available; this file is inventory+RPC/views.",
    "-- =============================================================================",
    "",
    "BEGIN;",
    "",
  ];
  writeFileSync(outSql, header.concat(chunks).concat(["", "COMMIT;", ""]).join("\n"), "utf8");
}

const chunks = [];

console.log("1) extensions...");
const exts = query(
  "select extname, extversion from pg_extension order by 1",
);
chunks.push("-- Extensions present on staging (informational)");
for (const e of exts) {
  chunks.push(`-- extension ${e.extname} ${e.extversion}`);
}
chunks.push("");

console.log("2) views...");
const views = query(
  "select table_name, view_definition from information_schema.views where table_schema = 'public' order by 1",
);
chunks.push("-- ---------------------------------------------------------------------------");
chunks.push("-- VIEWS");
chunks.push("-- ---------------------------------------------------------------------------");
for (const v of views) {
  const name = v.table_name;
  const def = (v.view_definition || "").trim().replace(/;+\s*$/, "");
  chunks.push(`DROP VIEW IF EXISTS public.${name} CASCADE;`);
  chunks.push(`CREATE OR REPLACE VIEW public.${name} AS`);
  chunks.push(`${def};`);
  chunks.push("");
}
writeFileSync(join(outDir, "views_count.txt"), String(views.length), "utf8");

console.log("3) functions (batched)...");
const fnNames = query(
  `select p.proname::text as proname,
          pg_get_function_identity_arguments(p.oid) as args
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f','p')
   order by 1, 2`,
);
chunks.push("-- ---------------------------------------------------------------------------");
chunks.push("-- FUNCTIONS / PROCEDURES");
chunks.push("-- ---------------------------------------------------------------------------");
let ok = 0;
let fail = 0;
const batchSize = 15;
for (let i = 0; i < fnNames.length; i += batchSize) {
  const batch = fnNames.slice(i, i + batchSize);
  const list = batch
    .map((f) => `'${String(f.proname).replace(/'/g, "''")}'`)
    .join(",");
  try {
    const defs = query(
      `select p.proname::text as proname,
              pg_get_function_identity_arguments(p.oid) as args,
              pg_get_functiondef(p.oid) as def
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.prokind in ('f','p')
         and p.proname::text in (${list})
       order by 1, 2`,
    );
    for (const d of defs) {
      if (d.def) {
        chunks.push(`-- ${d.proname}(${d.args || ""})`);
        chunks.push(String(d.def).trim().replace(/;+\s*$/, "") + ";");
        chunks.push("");
        ok++;
      }
    }
  } catch (e) {
    fail += batch.length;
    chunks.push(`-- ERROR batch starting ${batch[0]?.proname}: ${e.message}`);
  }
  process.stdout.write(`   ${Math.min(i + batchSize, fnNames.length)}/${fnNames.length}\r`);
}
console.log(`\n   functions ok=${ok} fail_batches_est=${fail}`);

console.log("4) policies...");
const pols = query(
  `select schemaname, tablename, policyname, permissive, roles::text as roles,
          cmd, qual, with_check
   from pg_policies
   where schemaname = 'public'
   order by tablename, policyname`,
);
chunks.push("-- ---------------------------------------------------------------------------");
chunks.push("-- RLS POLICIES (drop+create best-effort; tables must already exist)");
chunks.push("-- ---------------------------------------------------------------------------");
for (const p of pols) {
  const table = `public.${p.tablename}`;
  const pname = p.policyname;
  chunks.push(`DROP POLICY IF EXISTS "${pname}" ON ${table};`);
  const roles =
    !p.roles || p.roles === "{}"
      ? "PUBLIC"
      : String(p.roles)
          .replace(/[{}]/g, "")
          .split(",")
          .map((r) => r.trim())
          .filter(Boolean)
          .join(", ");
  const perm = p.permissive === "PERMISSIVE" || p.permissive === "t" || p.permissive === true
    ? ""
    : " AS RESTRICTIVE";
  const cmd = p.cmd || "ALL";
  let sql = `CREATE POLICY "${pname}" ON ${table}${perm} FOR ${cmd}`;
  if (roles) sql += ` TO ${roles}`;
  if (p.qual) sql += ` USING (${p.qual})`;
  if (p.with_check) sql += ` WITH CHECK (${p.with_check})`;
  chunks.push(sql + ";");
  chunks.push("");
}

chunks.push("-- END baseline (tables/indexes/triggers require full pg_dump)");
writeSqlFile(chunks);

const meta = {
  generated_at: new Date().toISOString(),
  method: "supabase_db_query_privileged",
  views: views.length,
  functions_listed: fnNames.length,
  functions_dumped: ok,
  policies: pols.length,
  out_sql: outSql,
  note: "CREATE TABLE not included — need Docker pg_dump or database password",
};
writeFileSync(join(outDir, "baseline_via_query_meta.json"), JSON.stringify(meta, null, 2));
console.log("Wrote", outSql);
console.log(meta);
