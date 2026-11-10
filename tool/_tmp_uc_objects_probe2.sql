select jsonb_build_object(
  'uc_tables', (
    select coalesce(jsonb_agg(tablename order by tablename), '[]'::jsonb)
    from pg_tables
    where schemaname='public'
      and (
        tablename like 'commerce_%'
        or tablename like 'batata_%'
        or tablename like '%reservation%'
        or tablename like '%checkout_attempt%'
        or tablename like 'hub_reviews%'
      )
  ),
  'uc_key_fns', (
    select coalesce(jsonb_agg(proname order by proname), '[]'::jsonb)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and (
      proname like 'batata_%reserve%'
      or proname like 'batata_%checkout%'
      or proname like 'batata_%guest%'
      or proname like 'batata_%supersede%'
      or proname like 'batata_%meta%'
      or proname like 'batata_hub_reviews%'
      or proname like 'batata_%dm%'
      or proname like 'batata_%ingest%'
    )
  ),
  'schema_migrations_has_202610', (
    select count(*)::int from supabase_migrations.schema_migrations
    where version like '202610%'
  ),
  'hub_reviews_public_exists', exists(
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='hub_reviews_public'
  )
) as probe;
