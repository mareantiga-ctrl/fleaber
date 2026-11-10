-- =============================================================================
-- BATATA — E0817 decisões produto (todas A) + tip em gravado
-- 1A: discovery perfis = hub_published OU directo REAL (não só is_live flag)
-- 2A: lives discovery ended só se hub_published; live activa OK
-- 3A: bundle rejeita unlist/sold
-- 4A: catalog_subtotal JWT só listed+not sold (sem preço de mortos)
-- 5A: invite email anti-oracle (sempre ok:true se email válido)
-- Extra A: gorjeta em live ended/gravado (seller coerente)
-- production_touched: false · fase4: false
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1A — perfis discovery
-- ---------------------------------------------------------------------------
create or replace view public.hub_profiles_discovery_public
with (security_barrier = true)
as
select
  p.id,
  public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
    as handle,
  p.full_name,
  p.photo_url,
  p.location,
  p.is_live,
  p.next_live,
  p.last_live,
  p.total_lives,
  coalesce(p.vacation_mode, false) as vacation_mode,
  (p.phone_verified_at is not null) as phone_verified,
  coalesce(p.external_payments_enabled, false) as external_payments_enabled,
  coalesce(vs.total_seguidores, 0)::int as follower_count,
  nullif(trim(p.hub_bio), '') as hub_bio,
  coalesce(p.hub_published, false) as hub_published
from public.profiles p
left join public.v_seguidores_stats vs on vs.profile_id = p.id
where length(
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
  ) >= 2
  and (
    coalesce(p.hub_published, false) = true
    or exists (
      select 1
      from public.lives l
      where coalesce(l.seller_id, l.vendedor_id) = p.id
        and (
          (
            lower(trim(coalesce(l.status, ''))) = 'live'
            and coalesce(l.is_active, false) = true
          )
          or (
            coalesce(l.is_active, false) = true
            and lower(trim(coalesce(l.status, ''))) in ('live', 'ao_vivo', 'active')
          )
        )
    )
  );

comment on view public.hub_profiles_discovery_public is
  'E0817-1A: hub_published OU directo real a decorrer (não is_live sozinho).';

grant select on public.hub_profiles_discovery_public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2A — lives discovery
-- ---------------------------------------------------------------------------
create or replace view public.hub_lives_discovery_public
with (security_barrier = true)
as
select
  l.id,
  coalesce(l.seller_id, l.vendedor_id) as seller_id,
  public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
    as seller_handle,
  nullif(trim(p.full_name), '') as seller_name,
  nullif(trim(p.photo_url), '') as seller_photo_url,
  l.title,
  l.status,
  coalesce(l.is_active, false) as is_active,
  l.mux_playback_id,
  l.mux_vod_playback_id,
  coalesce(l.viewer_count, 0) as viewer_count,
  l.went_live_at,
  l.created_at,
  l.publish_backend
from public.lives l
inner join public.profiles p
  on p.id = coalesce(l.seller_id, l.vendedor_id)
where length(
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
  ) >= 2
  and (
    -- Ao vivo / scheduled activo: sem exigir Hub publicado
    (
      lower(trim(coalesce(l.status, ''))) = 'live'
      and coalesce(l.is_active, false) = true
    )
    or (
      coalesce(l.is_active, false) = true
      and lower(trim(coalesce(l.status, ''))) in ('live', 'scheduled', 'ao_vivo', 'active')
    )
    -- Gravados: só loja publicada
    or (
      lower(trim(coalesce(l.status, ''))) = 'ended'
      and coalesce(p.hub_published, false) = true
    )
  );

comment on view public.hub_lives_discovery_public is
  'E0817-2A: live activa OK; ended só se hub_published.';

grant select on public.hub_lives_discovery_public to anon, authenticated;

create or replace view public.hub_live_items_discovery_public
with (security_barrier = true)
as
select
  li.id,
  li.live_id,
  hl.seller_id,
  hl.seller_handle,
  li.ref_code,
  li.title,
  li.photo_url,
  li.price,
  coalesce(li.is_active, false) as is_active,
  li.status,
  li.item_kind,
  li.clothing_size,
  li.gender,
  li.created_at
from public.live_items li
join public.hub_lives_discovery_public hl on hl.id = li.live_id;

grant select on public.hub_live_items_discovery_public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3A + 4A — bundle / catalog
-- ---------------------------------------------------------------------------
create or replace function public.batata_product_bundles_catalog_subtotal(p_product_ids uuid[])
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(auth.role(), '');
  v_sum numeric(12, 2);
begin
  if p_product_ids is null or coalesce(array_length(p_product_ids, 1), 0) < 1 then
    return 0;
  end if;

  -- service_role: tooling / Stripe paths podem precisar do total bruto
  if v_role = 'service_role' then
    select coalesce(sum(p.price), 0)::numeric(12, 2) into v_sum
    from public.products p
    where p.id = any (p_product_ids);
    return coalesce(v_sum, 0);
  end if;

  -- JWT / anon via grant: só montra viva — mortos somam 0 (sem oráculo de preço)
  select coalesce(sum(p.price), 0)::numeric(12, 2) into v_sum
  from public.products p
  where p.id = any (p_product_ids)
    and coalesce(p.list_on_marketplace, false) = true
    and coalesce(p.is_sold, false) = false;

  return coalesce(v_sum, 0);
end;
$$;

revoke all on function public.batata_product_bundles_catalog_subtotal(uuid[])
  from public, anon;
grant execute on function public.batata_product_bundles_catalog_subtotal(uuid[])
  to authenticated, service_role;

comment on function public.batata_product_bundles_catalog_subtotal(uuid[]) is
  'E0817-4A: JWT só soma listed+not sold; mortos → 0 (sem preço oracle).';

create or replace function public.batata_product_bundles_guard_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_bad int := 0;
  v_dead int := 0;
  v_new_st text;
  v_old_st text;
  v_sub numeric(12, 2);
  v_pct numeric(5, 2);
  v_disc numeric(12, 2);
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if NEW.seller_id is not null and NEW.seller_id = v_uid then
      NEW.seller_id := v_uid;
      if NEW.buyer_id is null or NEW.buyer_id = v_uid then
        raise exception 'bundle_invalid_buyer' using errcode = '23514';
      end if;
      NEW.status := coalesce(nullif(trim(NEW.status), ''), 'pending');
      if lower(trim(NEW.status)) is distinct from 'pending' then
        NEW.status := 'pending';
      end if;
    elsif NEW.buyer_id is null or NEW.buyer_id = v_uid then
      NEW.buyer_id := v_uid;
      if NEW.seller_id is null or NEW.seller_id = v_uid then
        raise exception 'bundle_invalid_seller' using errcode = '23514';
      end if;
      NEW.status := 'pending';
      NEW.discount_pct := 0;
    else
      raise exception 'bundle_party_mismatch' using errcode = '42501';
    end if;

    if NEW.buyer_id = NEW.seller_id then
      raise exception 'bundle_same_party' using errcode = '23514';
    end if;

    if NEW.product_ids is null or coalesce(array_length(NEW.product_ids, 1), 0) < 1 then
      raise exception 'bundle_products_required' using errcode = '23514';
    end if;

    select count(*)::int into v_bad
    from unnest(NEW.product_ids) as pid
    where not exists (
      select 1 from public.products p
      where p.id = pid and p.seller_id = NEW.seller_id
    );
    if v_bad > 0 then
      raise exception 'bundle_product_seller_mismatch' using errcode = '23514';
    end if;

    -- 3A: sem unlist / sold no conjunto
    select count(*)::int into v_dead
    from unnest(NEW.product_ids) as pid
    join public.products p on p.id = pid
    where coalesce(p.list_on_marketplace, false) = false
       or coalesce(p.is_sold, false) = true;
    if v_dead > 0 then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    end if;

    v_sub := public.batata_product_bundles_catalog_subtotal(NEW.product_ids);
    if coalesce(v_sub, 0) <= 0 then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    end if;
    v_pct := least(greatest(coalesce(NEW.discount_pct, 0), 0), 50);
    if v_uid is distinct from NEW.seller_id then
      v_pct := 0;
    end if;
    v_disc := round(v_sub * (v_pct / 100.0), 2);
    NEW.subtotal_eur := v_sub;
    NEW.discount_pct := v_pct;
    NEW.discount_eur := v_disc;
    NEW.total_eur := greatest(v_sub - v_disc, 0);
    return NEW;
  end if;

  NEW.buyer_id := OLD.buyer_id;
  NEW.seller_id := OLD.seller_id;
  NEW.product_ids := OLD.product_ids;

  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_old_st := lower(trim(coalesce(OLD.status, '')));

  if v_new_st is distinct from v_old_st then
    if v_new_st = 'accepted' and v_uid is distinct from OLD.seller_id then
      raise exception 'bundle_accept_seller_only' using errcode = '42501';
    end if;
    if v_new_st in ('rejected', 'cancelled', 'cancelado')
       and v_uid is distinct from OLD.seller_id
       and v_uid is distinct from OLD.buyer_id then
      raise exception 'bundle_status_not_authorized' using errcode = '42501';
    end if;
  end if;

  if v_uid is distinct from OLD.seller_id then
    NEW.total_eur := OLD.total_eur;
    NEW.subtotal_eur := OLD.subtotal_eur;
    NEW.discount_pct := OLD.discount_pct;
    NEW.discount_eur := OLD.discount_eur;
  else
    v_sub := public.batata_product_bundles_catalog_subtotal(OLD.product_ids);
    if coalesce(v_sub, 0) <= 0 then
      -- Produtos entretanto unlist/sold: mantém totais (não zera proposta)
      NEW.total_eur := OLD.total_eur;
      NEW.subtotal_eur := OLD.subtotal_eur;
      NEW.discount_pct := OLD.discount_pct;
      NEW.discount_eur := OLD.discount_eur;
    else
      v_pct := least(greatest(coalesce(NEW.discount_pct, OLD.discount_pct, 0), 0), 50);
      v_disc := round(v_sub * (v_pct / 100.0), 2);
      NEW.subtotal_eur := v_sub;
      NEW.discount_pct := v_pct;
      NEW.discount_eur := v_disc;
      NEW.total_eur := greatest(v_sub - v_disc, 0);
    end if;
  end if;

  if v_old_st in ('accepted', 'rejected', 'cancelled', 'cancelado', 'expired', 'purchased') then
    NEW.status := OLD.status;
    NEW.total_eur := OLD.total_eur;
    NEW.subtotal_eur := OLD.subtotal_eur;
    NEW.discount_pct := OLD.discount_pct;
    NEW.discount_eur := OLD.discount_eur;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_product_bundles_guard_write on public.product_bundles;
create trigger trg_batata_product_bundles_guard_write
  before insert or update on public.product_bundles
  for each row
  execute function public.batata_product_bundles_guard_write();

comment on function public.batata_product_bundles_guard_write() is
  'E0817-3A: INSERT rejeita unlist/sold; totais de catálogo; buyer sem desconto hostil.';

-- ---------------------------------------------------------------------------
-- 5A — invite anti-oracle (mudança uuid → jsonb: DROP obrigatório)
-- ---------------------------------------------------------------------------
drop function if exists public.batata_staff_invite_helper_by_email(text, text, jsonb);

create function public.batata_staff_invite_helper_by_email(
  p_email text,
  p_display_name text,
  p_permissions jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(p_email, '')));
  v_name text := trim(coalesce(p_display_name, ''));
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_helper uuid;
  v_ok boolean := false;
  v_existing public.seller_helpers%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_email = '' or position('@' in v_email) = 0 or char_length(v_email) > 320 then
    raise exception 'invalid_email' using errcode = '22023';
  end if;

  if char_length(v_name) < 1 or char_length(v_name) > 120 then
    raise exception 'invalid_display_name' using errcode = '22023';
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and lower(trim(coalesce(p.user_type, ''))) in ('vendedor', 'seller')
  )
  and exists (
    select 1 from public.products pr where pr.seller_id = v_uid limit 1
  )
  into v_ok;

  if not coalesce(v_ok, false) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_staff_invite_helper_by_email', v_window, 1)
  on conflict (uid, rpc, window_start)
  do update set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 10 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  select u.id into v_helper
  from auth.users u
  where lower(trim(u.email)) = v_email
  limit 1;

  -- Anti-oracle: inexistente → mesma forma de sucesso (sem criar).
  if v_helper is null then
    return jsonb_build_object('ok', true);
  end if;

  if v_helper = v_uid then
    raise exception 'cannot_invite_self' using errcode = '23514';
  end if;

  select * into v_existing
  from public.seller_helpers h
  where h.seller_id = v_uid
    and h.helper_user_id = v_helper
  limit 1;

  if found then
    if coalesce(v_existing.invitation_status, '') = 'accepted' then
      raise exception 'already_member' using errcode = '23505';
    end if;
    if coalesce(v_existing.invitation_status, '') = 'pending' then
      raise exception 'invite_pending' using errcode = '23505';
    end if;
    update public.seller_helpers
    set invitation_status = 'pending',
        display_name = v_name,
        invited_email = v_email,
        permissions = coalesce(p_permissions, '{}'::jsonb),
        invited_by = v_uid,
        updated_at = now(),
        responded_at = null,
        active = false
    where id = v_existing.id;
    return jsonb_build_object('ok', true);
  end if;

  insert into public.seller_helpers (
    seller_id,
    helper_user_id,
    invited_email,
    display_name,
    active,
    invitation_status,
    permissions,
    invited_by,
    updated_at
  ) values (
    v_uid,
    v_helper,
    v_email,
    v_name,
    false,
    'pending',
    coalesce(p_permissions, '{}'::jsonb),
    v_uid,
    now()
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_staff_invite_helper_by_email(text, text, jsonb)
  from public, anon;
grant execute on function public.batata_staff_invite_helper_by_email(text, text, jsonb)
  to authenticated, service_role;

comment on function public.batata_staff_invite_helper_by_email(text, text, jsonb) is
  'E0817-5A: anti-oracle — ok:true com ou sem conta; cria convite se existir.';

-- ---------------------------------------------------------------------------
-- Extra A — tip em gravado / ended (seller + live existem)
-- ---------------------------------------------------------------------------
create or replace function public.batata_create_live_tip_pending(
  p_live_id uuid,
  p_seller_id uuid,
  p_amount numeric,
  p_message text default null,
  p_stripe_session_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_id uuid := auth.uid();
  v_tip_id uuid;
  v_fee numeric;
  v_seller_amount numeric;
  v_live_seller uuid;
  v_note text;
  v_amount numeric;
begin
  if v_buyer_id is null then
    raise exception 'Tem de iniciar sessão para enviar gorjeta.';
  end if;

  if p_seller_id is null or p_seller_id = v_buyer_id then
    raise exception 'Vendedor inválido para gorjeta.';
  end if;

  if p_live_id is null then
    raise exception 'Direto obrigatório para gorjeta.';
  end if;

  v_amount := round(coalesce(p_amount, 0), 2);
  if v_amount < 1 then
    raise exception 'Valor mínimo de gorjeta: 1 €.';
  end if;
  if v_amount > 500 then
    raise exception 'Valor máximo de gorjeta: 500 €.';
  end if;

  select coalesce(seller_id, vendedor_id) into v_live_seller
  from public.lives
  where id = p_live_id;

  if v_live_seller is null then
    raise exception 'Direto não encontrado.';
  end if;

  if v_live_seller <> p_seller_id then
    raise exception 'O vendedor não corresponde a este direto.';
  end if;

  -- Extra A: sem live_not_active_for_tip — ended/gravado OK

  v_fee := public.batata_live_tip_processing_fee(v_amount);
  v_seller_amount := public.batata_live_tip_seller_amount(v_amount);
  v_note := nullif(trim(coalesce(p_message, '')), '');

  insert into public.live_tips (
    live_id,
    buyer_id,
    seller_id,
    amount,
    processing_fee,
    seller_amount,
    message,
    payment_source,
    status,
    stripe_session_id
  ) values (
    p_live_id,
    v_buyer_id,
    p_seller_id,
    v_amount,
    v_fee,
    v_seller_amount,
    v_note,
    'stripe',
    'pending',
    null
  )
  returning id into v_tip_id;

  return v_tip_id;
end;
$$;

revoke all on function public.batata_create_live_tip_pending(uuid, uuid, numeric, text, text)
  from public, anon;
grant execute on function public.batata_create_live_tip_pending(uuid, uuid, numeric, text, text)
  to authenticated, service_role;

create or replace function public.batata_send_live_tip_from_wallet(
  p_live_id uuid,
  p_seller_id uuid,
  p_amount numeric,
  p_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_id uuid := auth.uid();
  v_tip_id uuid;
  v_fee numeric;
  v_seller_amount numeric;
  v_balance numeric;
  v_live_seller uuid;
  v_note text;
begin
  if v_buyer_id is null then
    raise exception 'Tem de iniciar sessão para enviar gorjeta.';
  end if;

  if p_seller_id is null or p_seller_id = v_buyer_id then
    raise exception 'Vendedor inválido para gorjeta.';
  end if;

  if coalesce(p_amount, 0) < 1 then
    raise exception 'Valor mínimo de gorjeta: 1 €.';
  end if;

  if p_live_id is null then
    raise exception 'Direto obrigatório para gorjeta.';
  end if;

  select coalesce(seller_id, vendedor_id) into v_live_seller
  from public.lives
  where id = p_live_id;

  if v_live_seller is null then
    raise exception 'Direto não encontrado.';
  end if;

  if v_live_seller <> p_seller_id then
    raise exception 'O vendedor não corresponde a este directo.';
  end if;

  v_fee := public.batata_live_tip_processing_fee(p_amount);
  v_seller_amount := public.batata_live_tip_seller_amount(p_amount);
  v_note := nullif(trim(coalesce(p_message, '')), '');

  perform public.batata_ensure_wallet(v_buyer_id);
  perform public.batata_ensure_wallet(p_seller_id);

  select balance into v_balance
  from public.wallets
  where id = v_buyer_id
  for update;

  if coalesce(v_balance, 0) < round(p_amount, 2) then
    raise exception 'insufficient_wallet_balance';
  end if;

  insert into public.live_tips (
    live_id,
    buyer_id,
    seller_id,
    amount,
    processing_fee,
    seller_amount,
    message,
    payment_source,
    status,
    completed_at
  ) values (
    p_live_id,
    v_buyer_id,
    p_seller_id,
    round(p_amount, 2),
    v_fee,
    v_seller_amount,
    v_note,
    'wallet',
    'completed',
    now()
  )
  returning id into v_tip_id;

  if not public.batata_wallet_apply_tip_once(
    v_buyer_id,
    v_tip_id,
    -round(p_amount, 2),
    'gorjeta_enviada',
    coalesce(v_note, 'Gorjeta em direto')
  ) then
    raise exception 'Não foi possível debitar a carteira.';
  end if;

  if not public.batata_wallet_apply_tip_once(
    p_seller_id,
    v_tip_id,
    v_seller_amount,
    'gorjeta_recebida',
    coalesce(v_note, 'Gorjeta recebida em direto')
  ) then
    raise exception 'Não foi possível creditar o vendedor.';
  end if;

  return v_tip_id;
end;
$$;

revoke all on function public.batata_send_live_tip_from_wallet(uuid, uuid, numeric, text)
  from public, anon;
grant execute on function public.batata_send_live_tip_from_wallet(uuid, uuid, numeric, text)
  to authenticated, service_role;

notify pgrst, 'reload schema';
