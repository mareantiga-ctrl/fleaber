-- T/U P2+P3 2026-09-01 — restantes após sec_tu P0/P1
-- P2 Hub: vitrine sem qty=0
-- P2 conjunto: unlist/sold bloqueado com bundle pending/accepted
-- P2 OCR: token só se loja (produto) ou directo existente
-- production_touched: false · fase4: false
-- Preserva: vendedor com anúncios/lives continua a mintar token;
--           Facebook/helper convert sem Stripe (já em sec_tu);
--           parcial em `pago` (antes de enviar) continua carteira.

-- ---------------------------------------------------------------------------
-- P2 — Hub não mostra anúncios sem stock
-- ---------------------------------------------------------------------------
create or replace view public.hub_products_public
with (security_barrier = true)
as
select
  pr.id,
  pr.seller_id,
  hp.handle as seller_handle,
  pr.title,
  pr.price,
  pr.image_urls,
  pr.category,
  pr.state,
  pr.description,
  pr.ref_code,
  pr.clothing_size,
  pr.gender,
  pr.created_at,
  coalesce(pr.is_sold, false) as is_sold
from public.products pr
join public.hub_profiles_public hp on hp.id = pr.seller_id
where coalesce(pr.list_on_marketplace, false) = true
  and coalesce(pr.is_sold, false) = false
  and coalesce(pr.quantity, 0) > 0;

comment on view public.hub_products_public is
  'Marketplace público: listado, não vendido, quantity>0. Sem stock interno na coluna.';

grant select on public.hub_products_public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- P2 — não deslistar / marcar vendido com conjunto pending ou aceite
-- ---------------------------------------------------------------------------
create or replace function public.batata_products_guard_active_bundle()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_hit boolean := false;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  if not (
    (coalesce(OLD.list_on_marketplace, false) = true
     and coalesce(NEW.list_on_marketplace, false) = false)
    or (coalesce(OLD.is_sold, false) = false
        and coalesce(NEW.is_sold, false) = true)
  ) then
    return NEW;
  end if;

  select exists (
    select 1
    from public.product_bundles b
    where NEW.id = any (b.product_ids)
      and lower(trim(coalesce(b.status, ''))) in ('pending', 'accepted')
  ) into v_hit;

  if coalesce(v_hit, false) then
    raise exception 'product_in_active_bundle' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_products_guard_active_bundle on public.products;
create trigger trg_batata_products_guard_active_bundle
  before update of list_on_marketplace, is_sold on public.products
  for each row
  execute function public.batata_products_guard_active_bundle();

comment on function public.batata_products_guard_active_bundle() is
  'U-P2: unlist/sold JWT bloqueado se o SKU está num conjunto pending/accepted.';

-- ---------------------------------------------------------------------------
-- P2 — OCR device token: vendedor com loja ou directo (não só user_type)
-- ---------------------------------------------------------------------------
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
  and (
    exists (select 1 from public.products pr where pr.seller_id = v_uid limit 1)
    or exists (
      select 1 from public.lives l
      where coalesce(l.seller_id, l.vendedor_id) = v_uid
      limit 1
    )
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
  'S-P2: só vendedor com produto ou live cria device token OCR; ingest cruzado continua not_allowed.';

notify pgrst, 'reload schema';
