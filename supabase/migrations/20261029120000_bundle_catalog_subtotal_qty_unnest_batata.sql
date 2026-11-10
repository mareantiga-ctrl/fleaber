-- 32.9.2 — catalog_subtotal conta unidades (unnest), não só SKUs distintos.
-- Paridade com product_quantities no cliente: product_ids pode repetir o mesmo
-- uuid N vezes para qty N. Não enfraquece chat_system_card_bundle_total_mismatch.

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

  if v_role = 'service_role' then
    select coalesce(sum(p.price), 0)::numeric(12, 2) into v_sum
    from unnest(p_product_ids) as pid
    join public.products p on p.id = pid;
    return coalesce(v_sum, 0);
  end if;

  select coalesce(sum(p.price), 0)::numeric(12, 2) into v_sum
  from unnest(p_product_ids) as pid
  join public.products p on p.id = pid
  where coalesce(p.list_on_marketplace, false) = true
    and coalesce(p.is_sold, false) = false;

  return coalesce(v_sum, 0);
end;
$$;

comment on function public.batata_product_bundles_catalog_subtotal(uuid[]) is
  'Subtotal catálogo do conjunto: soma preço por ocorrência em product_ids (qty via repetição).';
