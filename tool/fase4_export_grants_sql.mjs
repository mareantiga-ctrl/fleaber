/**
 * Gera SQL de grants (anon/authenticated/service_role) a partir do staging
 * para aplicar no Prod após dump --no-privileges.
 *
 * Uso: node tool/fase4_export_grants_sql.mjs
 * Saída: tool/reports/fase4_execution_2026-09-13/P4.5/prod_restore_grants.sql
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const outDir = path.join(
  root,
  'tool/reports/fase4_execution_2026-09-13/P4.5',
);
const outFile = path.join(outDir, 'prod_restore_grants.sql');

function dbQuery(sql) {
  const tmp = path.join(outDir, `_tmp_query_${Date.now()}.sql`);
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(tmp, sql, 'utf8');
  try {
    const r = spawnSync(
      'npx',
      ['supabase', 'db', 'query', '--linked', '-o', 'json', '-f', tmp],
      { cwd: root, encoding: 'utf8', shell: true, maxBuffer: 64 * 1024 * 1024 },
    );
    if (r.status !== 0) {
      throw new Error(`db query failed: ${r.stderr || r.stdout}`);
    }
    const text = (r.stdout || '').trim();
    const start = text.indexOf('{');
    const parsed = JSON.parse(start >= 0 ? text.slice(start) : text);
    if (parsed.rows) return parsed.rows;
    if (Array.isArray(parsed)) return parsed;
    throw new Error(`unexpected query result shape: ${text.slice(0, 200)}`);
  } finally {
    try {
      fs.unlinkSync(tmp);
    } catch {
      /* ignore */
    }
  }
}

fs.mkdirSync(outDir, { recursive: true });

const tableRows = dbQuery(`
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated', 'service_role')
order by table_name, grantee, privilege_type
`);

const seqRows = dbQuery(`
select grantee, object_name as sequence_name, privilege_type
from information_schema.usage_privileges
where object_schema = 'public'
  and object_type = 'SEQUENCE'
  and grantee in ('anon', 'authenticated', 'service_role')
order by object_name, grantee, privilege_type
`);

const routineRows = dbQuery(`
select r.rolname as grantee, p.oid::regprocedure::text as sig
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join pg_roles r
where n.nspname = 'public'
  and r.rolname in ('anon', 'authenticated', 'service_role')
  and has_function_privilege(r.oid, p.oid, 'EXECUTE')
order by 2, 1
`);

const colRows = dbQuery(`
select grantee, table_name, column_name, privilege_type
from information_schema.column_privileges
where table_schema = 'public'
  and grantee in ('anon', 'authenticated')
order by table_name, column_name, grantee, privilege_type
`);

const schemaRows = dbQuery(`
select grantee, privilege_type
from information_schema.usage_privileges
where object_schema = 'public'
  and object_type = 'SCHEMA'
  and object_name = 'public'
  and grantee in ('anon', 'authenticated', 'service_role')
`);

const lines = [];
lines.push('-- P4.5 — restore API grants on Prod (mirror staging)');
lines.push('-- Source: staging fxdknzrqjenzqcvnwqqq via information_schema');
lines.push('-- Safe: RLS policies remain; wallet RPCs re-locked at end.');
lines.push('begin;');
lines.push('');
lines.push('grant usage on schema public to anon, authenticated, service_role;');
lines.push('');

// Table grants: group by table+grantee
const tableMap = new Map();
for (const r of tableRows) {
  const k = `${r.table_name}::${r.grantee}`;
  if (!tableMap.has(k)) tableMap.set(k, new Set());
  tableMap.get(k).add(r.privilege_type);
}
for (const [k, privs] of [...tableMap.entries()].sort()) {
  const [table, grantee] = k.split('::');
  const list = [...privs].sort().join(', ');
  lines.push(`grant ${list} on table public.${quoteIdent(table)} to ${grantee};`);
}

lines.push('');
for (const r of seqRows) {
  lines.push(
    `grant ${r.privilege_type} on sequence public.${quoteIdent(r.sequence_name)} to ${r.grantee};`,
  );
}

lines.push('');
lines.push('-- Function EXECUTE (mirror staging has_function_privilege)');
for (const r of routineRows) {
  // sig already includes schema/args from regprocedure::text
  lines.push(`grant execute on function ${r.sig} to ${r.grantee};`);
}

lines.push('');
lines.push('-- Column-level privileges (anon/authenticated) — after table grants');
for (const r of colRows) {
  lines.push(
    `grant ${r.privilege_type} (${quoteIdent(r.column_name)}) on table public.${quoteIdent(r.table_name)} to ${r.grantee};`,
  );
}

lines.push('');
lines.push('-- Re-lock wallet / destructive RPCs (same as P4.4 fix_wallet_grants.sql)');
lines.push(`do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as rp
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'batata_credit_wallet_once',
        'batata_debit_wallet_once',
        'batata_clawback_seller_wallet_for_order',
        'batata_ensure_wallet',
        'batata_refund_buyer_wallet_for_order',
        'batata_release_seller_wallet_for_order',
        'batata_create_raffle_prize_order',
        'batata_award_live_raffle_tickets',
        'batata_live_raffle_social_broadcast',
        'batata_anon_rate_check'
      )
  loop
    execute format('revoke execute on function %s from public', r.rp);
    execute format('revoke execute on function %s from anon', r.rp);
    execute format('revoke execute on function %s from authenticated', r.rp);
    execute format('grant execute on function %s to service_role', r.rp);
  end loop;
end
$$;
`);

lines.push('');
lines.push(`-- Assert wallet lockdown if function exists
do $$
begin
  if to_regprocedure('public.batata_assert_wallet_rpc_grants()') is not null then
    perform public.batata_assert_wallet_rpc_grants();
  end if;
end
$$;
`);

lines.push('commit;');
lines.push('');
lines.push('-- Spot-check (run separately if needed):');
lines.push(`-- select relname, has_table_privilege('authenticated', oid, 'SELECT') as auth_sel
-- from pg_class c join pg_namespace n on n.oid=c.relnamespace
-- where n.nspname='public' and relname in ('chat_messages','products','profiles');`);

fs.writeFileSync(outFile, lines.join('\n'), 'utf8');
console.log(`Wrote ${outFile}`);
console.log(`table grant groups: ${tableMap.size}`);
console.log(`column grants: ${colRows.length}`);
console.log(`schema rows: ${schemaRows.length}`);
console.log(`routines listed (info only): ${routineRows.length}`);

function quoteIdent(name) {
  if (!/^[a-z_][a-z0-9_]*$/i.test(name)) {
    return `"${String(name).replace(/"/g, '""')}"`;
  }
  return name;
}
