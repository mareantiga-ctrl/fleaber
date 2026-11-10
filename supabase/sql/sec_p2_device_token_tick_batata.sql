-- P2 lote 5: RTB-B-P2-01 seller_device_token + RTB-B-P2-02 tick raffle
-- BUG: qualquer JWT criava token OCR; buyer podia tick (fechar rifa expirada).
-- Preserva: seller/staff cria token; seller da rifa (ou service) faz tick.
-- production_touched: false · fase4: false

create or replace function public.batata_create_seller_device_token(
  p_device_id text,
  p_label text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_device text := trim(coalesce(p_device_id, ''));
  v_token text;
  v_hash text;
  v_is_seller boolean := false;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if length(v_device) < 3 then
    return jsonb_build_object('ok', false, 'error', 'invalid_device_id');
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and lower(trim(coalesce(p.user_type, ''))) in ('vendedor', 'seller')
  )
  into v_is_seller;

  if not v_is_seller then
    return jsonb_build_object('ok', false, 'error', 'not_seller');
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  insert into public.seller_device_tokens (seller_id, device_id, token_hash, label)
  values (v_uid, v_device, v_hash, nullif(trim(coalesce(p_label, '')), ''))
  on conflict (seller_id, device_id) do update
  set
    token_hash = excluded.token_hash,
    label = excluded.label,
    revoked_at = null,
    created_at = now();

  return jsonb_build_object(
    'ok', true,
    'device_id', v_device,
    'token', v_token,
    'label', nullif(trim(coalesce(p_label, '')), '')
  );
end;
$$;

revoke all on function public.batata_create_seller_device_token(text, text)
  from public, anon;
grant execute on function public.batata_create_seller_device_token(text, text)
  to authenticated, service_role;

comment on function public.batata_create_seller_device_token(text, text) is
  'P2-01: só seller (user_type/products/lives) cria device token OCR.';

create or replace function public.batata_tick_live_raffle(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_row public.live_raffles%rowtype;
  v_ok boolean := false;
begin
  select * into v_row from public.live_raffles where id = p_raffle_id;
  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'raffle_not_found');
  end if;

  if v_role is distinct from 'authenticated' or v_uid is null then
    -- service_role / jobs
    v_ok := true;
  else
    select exists (
      select 1
      from public.lives l
      where l.id = v_row.live_id
        and (
          coalesce(l.seller_id, l.vendedor_id) = v_uid
          or v_row.seller_id = v_uid
          or public.batata_staff_has_permission(
            coalesce(l.seller_id, l.vendedor_id),
            'can_manage_raffles'
          )
        )
    ) into v_ok;
  end if;

  if not v_ok then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  if v_row.status = 'active'
     and v_row.ends_at is not null
     and v_row.ends_at <= now() then
    update public.live_raffles set status = 'closed' where id = p_raffle_id
    returning * into v_row;
    perform public.batata_live_raffle_audit(v_row.id, 'auto_closed', '{}'::jsonb);
  end if;

  return jsonb_build_object('ok', true, 'status', v_row.status);
end;
$$;

revoke all on function public.batata_tick_live_raffle(uuid) from public, anon;
grant execute on function public.batata_tick_live_raffle(uuid)
  to authenticated, service_role;

comment on function public.batata_tick_live_raffle(uuid) is
  'P2-02: tick/fecho só seller da live (ou service_role).';

notify pgrst, 'reload schema';
