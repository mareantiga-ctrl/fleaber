-- Read-only: presence of Unified Commerce key objects (no secrets)
select jsonb_build_object(
  'phase2_reservation_fn', exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and proname like 'batata%reserv%'
  ),
  'phase8_meta_tables', (
    select coalesce(jsonb_agg(tablename order by tablename), '[]'::jsonb)
    from pg_tables
    where schemaname='public'
      and tablename ~* '(meta_|facebook_|ps_face|unified)'
  ),
  'phase8_fns', (
    select coalesce(jsonb_agg(proname order by proname), '[]'::jsonb)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and (
        proname like '%meta%'
        or proname like '%facebook%'
        or proname like 'batata_hub_reviews%'
        or proname like 'batata%phase%'
      )
  ),
  'schema_migrations_tail', (
    select coalesce(jsonb_agg(version order by version desc), '[]'::jsonb)
    from (
      select version from supabase_migrations.schema_migrations
      order by version desc
      limit 25
    ) t
  ),
  'uc_migration_versions_present', (
    select coalesce(jsonb_agg(version order by version), '[]'::jsonb)
    from supabase_migrations.schema_migrations
    where version >= '20261005120000' and version <= '20261009150000'
  )
) as probe;
