-- Pós-deploy #19b staging — verificação (staging fxdknzrqjenzqcvnwqqq)

select jsonb_build_object(
  'views_count', (select count(*)::int from pg_views where schemaname = 'public' and viewname like 'hub\_%' escape '\'),
  'view_names', (select jsonb_agg(viewname order by viewname) from pg_views where schemaname = 'public' and viewname like 'hub\_%' escape '\'),
  'fomo_rpc', exists(select 1 from pg_proc where proname = 'batata_hub_live_fomo_snapshot'),
  'resolve_handle_rpc', exists(select 1 from pg_proc where proname = 'batata_resolve_handle'),
  'profiles_select_anon_policy_gone', not exists(select 1 from pg_policy where polname = 'profiles_select_anon'),
  'lives_select_public_live_policy_gone', not exists(select 1 from pg_policy where polname = 'lives_select_public_live'),
  'anon_select_profiles', has_table_privilege('anon', 'public.profiles', 'SELECT'),
  'anon_select_lives', has_table_privilege('anon', 'public.lives', 'SELECT'),
  'anon_select_products', has_table_privilege('anon', 'public.products', 'SELECT'),
  'anon_select_hub_profiles', has_table_privilege('anon', 'public.hub_profiles_public', 'SELECT'),
  'anon_exec_fomo', has_function_privilege('anon', 'public.batata_hub_live_fomo_snapshot(uuid)', 'EXECUTE'),
  'anon_exec_resolve', has_function_privilege('anon', 'public.batata_resolve_handle(text)', 'EXECUTE'),
  'sensitive_cols_in_hub_views', (
    select count(*)::int
    from pg_views v
    join pg_class c on c.relname = v.viewname and c.relkind = 'v'
    join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    where v.schemaname = 'public'
      and v.viewname like 'hub\_%' escape '\'
      and (
        lower(a.attname) in (
          'phone', 'legal_full_name', 'iban', 'mb_way',
          'shipping_line1', 'shipping_line2', 'shipping_postal_code',
          'shipping_city', 'shipping_country', 'user_type', 'email',
          'mux_stream_key', 'stream_key', 'mux_live_id',
          'livekit_room_name', 'livekit_egress_id', 'mux_asset_id',
          'buyer_id', 'order_id', 'user_id', 'tip_id'
        )
        or (lower(a.attname) = 'seller_id' and v.viewname = 'hub_profiles_public')
      )
  ),
  'hub_profiles_rows', (select count(*)::int from public.hub_profiles_public),
  'hub_published_profiles', (select count(*)::int from public.profiles where hub_published = true),
  'claimed_handles', (select count(*)::int from public.profiles where handle is not null and trim(handle) <> ''),
  'resolve_handle_admin', public.batata_resolve_handle('admin'),
  'fomo_latest_live', public.batata_hub_live_fomo_snapshot(
    (select l.id from public.lives l order by l.created_at desc nulls last limit 1)
  )
) as verify_19b;

select relname as object,
  has_table_privilege('anon', format('public.%I', relname), 'SELECT') as anon_select
from (values
  ('profiles'),('lives'),('products'),('live_items'),('live_messages'),('reviews_gerais'),
  ('hub_profiles_public'),('hub_lives_public'),('hub_products_public'),
  ('hub_live_items_public'),('hub_live_messages_public'),('hub_reviews_public')
) t(relname)
order by relname;

select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and table_name like 'hub\_%' escape '\'
  and lower(column_name) in (
    'phone','iban','mb_way','legal_full_name','shipping_line1','shipping_city',
    'mux_stream_key','stream_key','buyer_id','order_id','user_id','tip_id'
  )
order by 1, 2;

do $$
declare
  v_err text;
begin
  set local role anon;
  begin
    perform 1 from public.profiles limit 1;
    raise exception 'NEG_FAIL: anon can SELECT profiles';
  exception when insufficient_privilege then
    raise notice 'NEG_OK: anon blocked SELECT profiles (PII table)';
  end;
  begin
    perform phone from public.profiles limit 1;
    raise exception 'NEG_FAIL: anon can SELECT profiles.phone';
  exception when insufficient_privilege then
    raise notice 'NEG_OK: anon blocked profiles.phone';
  end;
  begin
    perform mux_stream_key from public.lives limit 1;
    raise exception 'NEG_FAIL: anon can SELECT lives.mux_stream_key';
  exception when insufficient_privilege then
    raise notice 'NEG_OK: anon blocked lives.mux_stream_key';
  end;
  begin
    perform user_id from public.live_messages limit 1;
    raise exception 'NEG_FAIL: anon can SELECT live_messages.user_id';
  exception when insufficient_privilege then
    raise notice 'NEG_OK: anon blocked live_messages.user_id';
  end;
  begin
    perform buyer_id from public.live_reservation_requests limit 1;
    raise exception 'NEG_FAIL: anon can SELECT live_reservation_requests.buyer_id';
  exception when insufficient_privilege then
    raise notice 'NEG_OK: anon blocked live_reservation_requests.buyer_id';
  end;
  perform count(*) from public.hub_profiles_public;
  raise notice 'NEG_OK: anon can SELECT hub_profiles_public';
  reset role;
end;
$$;
