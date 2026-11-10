-- DH–DM BATATA (staging only) — 2026-09-06
-- P1-2: off-platform ASCII wrap (contains mbway/transferencia; App OK)
-- P2-1: hub_products_public esconde SKU sem stock efectivo (live hold aceite)
-- NÃO produção / Fase 4.

-- ===========================================================================
-- DH P1-2 — off-platform: wrap ASCII (mb way x, xxmbway, via mb way, …)
-- ===========================================================================
create or replace function public.batata_is_off_platform_payment(p_method text)
returns boolean
language plpgsql
immutable
as $$
declare
  v_raw text := coalesce(p_method, '');
  v_norm text;
  v_compact text;
begin
  -- Plataforma (nunca off por substring)
  v_norm := public.batata_normalize_payment_method(v_raw);
  v_compact := regexp_replace(v_norm, '[^a-z0-9]', '', 'g');
  if v_compact in (
    'card', 'stripe', 'applepay', 'googlepay', 'paypal',
    'pagamentonaapp', 'naapp', 'inapp', 'fleaber'
  ) then
    return false;
  end if;

  -- Qualquer non-ASCII residual → off fail-closed (após fold)
  if v_raw ~ '[^\u0000-\u007f]' then
    if v_compact in (
      'mbway', 'transferencia', 'transfer', 'transf',
      'pagamentodirecto', 'pagamentodireto', 'directo', 'direto',
      'entregaemmao', 'emmao', 'levantamento', 'combinado', 'combinada',
      'pagamentodiretoaovendedormbwaytransf',
      'pagamentodirectoaovendedormbwaytransf'
    ) then
      return true;
    end if;
    if v_compact not in (
      'card', 'stripe', 'applepay', 'googlepay', 'paypal',
      'pagamentonaapp', 'naapp', 'inapp', 'fleaber'
    ) then
      return true;
    end if;
  end if;

  if v_norm in (
    'mb way', 'mb_way', 'mb-way', 'mbway',
    'transferencia', 'transferência', 'transfer', 'transf',
    'pagamento directo', 'pagamento direto',
    'pagamento_directo', 'pagamento_direto',
    'directo', 'direto',
    'entrega em mao', 'entrega em mão', 'em mao', 'em mão',
    'levantamento', 'combinado', 'combinada',
    'pagamento direto ao vendedor (mb way/transf)',
    'pagamento directo ao vendedor (mb way/transf)'
  ) then
    return true;
  end if;

  if v_compact in (
    'mbway', 'transferencia', 'transfer', 'transf',
    'pagamentodirecto', 'pagamentodireto', 'directo', 'direto',
    'entregaemmao', 'emmao', 'levantamento', 'combinado', 'combinada',
    'pagamentodiretoaovendedormbwaytransf',
    'pagamentodirectoaovendedormbwaytransf'
  ) then
    return true;
  end if;

  -- Wrap ASCII: "mb way x", "xxmbway", "via mb way", "transferencia extra"
  if position('mbway' in v_compact) > 0 then
    return true;
  end if;
  if position('transferencia' in v_compact) > 0
     or position('transfer' in v_compact) > 0 then
    return true;
  end if;

  return false;
end;
$$;

comment on function public.batata_is_off_platform_payment(text) is
  'DH-P1-2: exact + contains mbway/transferencia; Pagamento na App never off.';

-- ===========================================================================
-- DM P2-1 — Hub: não listar SKU sem unidades efectivas (orders + live accepted)
-- ===========================================================================
create or replace function public.batata_product_hub_sellable(p_product_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_stock int;
  v_held int;
begin
  if p_product_id is null then
    return false;
  end if;
  select coalesce(p.quantity, 0)
    into v_stock
  from public.products p
  where p.id = p_product_id;
  if v_stock is null then
    return false;
  end if;
  v_held := coalesce(public.batata_product_held_qty(p_product_id, null, null), 0);
  return greatest(v_stock - v_held, 0) > 0;
end;
$$;

revoke all on function public.batata_product_hub_sellable(uuid) from public;
grant execute on function public.batata_product_hub_sellable(uuid)
  to anon, authenticated, service_role;

comment on function public.batata_product_hub_sellable(uuid) is
  'DM-P2-1: stock efectivo > 0 (inclui live accepted no hold).';

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
  and public.batata_product_hub_sellable(pr.id) = true;

comment on view public.hub_products_public is
  'Marketplace público: listado, não vendido, com stock efectivo (holds).';

grant select on public.hub_products_public to anon, authenticated;

notify pgrst, 'reload schema';
