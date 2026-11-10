-- Hotfix PS pairing — lives não tem coluna `nome` (só `title`).
-- Erro runtime: record "v_live" has no field "nome" → Studio ficava sem código.

create or replace function public.batata_ps_create_pairing(
  p_live_id uuid,
  p_device_id_hint text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_seller_id uuid;
  v_live public.lives%rowtype;
  v_code text;
  v_token text;
  v_hash text;
  v_device text := coalesce(nullif(trim(p_device_id_hint), ''), 'ps-reader-pc');
  v_attempt int := 0;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  v_seller_id := coalesce(v_live.seller_id, v_live.vendedor_id);

  if v_seller_id is distinct from v_uid
     and not public.batata_staff_has_permission(v_seller_id, 'can_manage_reservations') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (
      select 1 from public.ps_pairing_sessions s
      where s.code = v_code and s.claimed_at is null
    );
    exit when v_attempt > 20;
  end loop;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  insert into public.seller_device_tokens (seller_id, device_id, token_hash, label)
  values (
    v_seller_id,
    v_device,
    v_hash,
    'PS Reader ' || to_char(now(), 'YYYY-MM-DD HH24:MI')
  )
  on conflict (seller_id, device_id) do update
  set
    token_hash = excluded.token_hash,
    label = excluded.label,
    revoked_at = null,
    created_at = now();

  insert into public.ps_pairing_sessions (
    seller_id, live_id, code, device_token_plain, device_id_hint, expires_at
  ) values (
    v_seller_id,
    p_live_id,
    v_code,
    v_token,
    v_device,
    now() + interval '10 minutes'
  );

  return jsonb_build_object(
    'ok', true,
    'code', v_code,
    'expires_at', (now() + interval '10 minutes'),
    'live_id', p_live_id,
    'live_title', coalesce(v_live.title, 'Live'),
    'device_id', v_device
  );
end;
$$;

create or replace function public.batata_ps_live_context(p_live_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_live public.lives%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_active uuid;
  v_row record;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_id');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  select li.id into v_active
  from public.live_items li
  where li.live_id = p_live_id and li.is_active = true
  order by li.updated_at desc nulls last
  limit 1;

  for v_row in
    select
      li.id,
      li.ref_code,
      li.title,
      li.is_active,
      li.public_slot,
      li.quantity,
      li.status,
      li.clothing_size,
      li.photo_url,
      public.batata_normalize_ref(li.ref_code) as ref_norm,
      row_number() over (order by li.created_at asc)::int as catalog_ord
    from public.live_items li
    where li.live_id = p_live_id
      and coalesce(li.status, '') <> 'sold'
    order by li.created_at asc
  loop
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'live_item_id', v_row.id,
      'ref_code', v_row.ref_code,
      'ref_norm', v_row.ref_norm,
      'title', v_row.title,
      'is_active', coalesce(v_row.is_active, false),
      'public_slot', coalesce(v_row.public_slot, v_row.catalog_ord),
      'catalog_ordinal', v_row.catalog_ord,
      'quantity', coalesce(v_row.quantity, 1),
      'status', coalesce(v_row.status, 'available'),
      'variant', nullif(trim(coalesce(v_row.clothing_size, '')), '')
    ));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'live_id', v_live.id,
    'live_title', coalesce(v_live.title, 'Live'),
    'live_status', v_live.status,
    'seller_id', coalesce(v_live.seller_id, v_live.vendedor_id),
    'active_item_id', v_active,
    'items', v_items
  );
end;
$$;

notify pgrst, 'reload schema';
