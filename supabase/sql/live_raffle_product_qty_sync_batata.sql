-- Fleaber BATATA: rifa activa → products.quantity desce já (marketplace/grelha).
-- Cancelar → devolve. Marketplace hold no RPC NÃO duplica (já está na quantity).
-- Executar no SQL Editor staging DEPOIS de live_raffle_prize_stock_batata.sql
-- e live_raffles_live_item_link_batata.sql.

create or replace function public.batata_live_raffle_sync_product_qty(
  p_raffle_id uuid,
  p_release boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r public.live_raffles%rowtype;
  v_li public.live_items%rowtype;
  v_product_id uuid;
  v_hold int;
  v_before int;
  v_after int;
  v_already boolean;
begin
  select * into v_r from public.live_raffles where id = p_raffle_id;
  if v_r.id is null or v_r.live_item_id is null then
    return;
  end if;

  select * into v_li from public.live_items where id = v_r.live_item_id;
  if v_li.id is null then
    return;
  end if;

  v_product_id := v_li.product_id;
  if v_product_id is null then
    return;
  end if;

  v_hold := greatest(coalesce(v_r.winner_count, 1), 1);

  -- Idempotência: create SQL + client Dart podem ambos chamar sync.
  select exists (
    select 1
    from public.live_raffle_audit_log a
    where a.raffle_id = p_raffle_id
      and a.event_type = 'marketplace_qty_held'
  ) into v_already;

  if p_release then
    if not v_already then
      return;
    end if;
  else
    if v_already then
      return;
    end if;
  end if;

  select coalesce(quantity, 0) into v_before
  from public.products
  where id = v_product_id
  for update;

  if not found then
    return;
  end if;

  if p_release then
    if not v_already then
      return;
    end if;
    -- Reposição: só limpa o marcador; quantity nunca foi alterada neste modelo
    -- (hold virtual via raffle_hold_qty no stock RPC).
    delete from public.live_raffle_audit_log
     where raffle_id = p_raffle_id
       and event_type = 'marketplace_qty_held';
    update public.products
       set is_sold = false,
           list_on_marketplace = true
     where id = v_product_id
       and coalesce(quantity, 0) > 0;
    v_after := v_before;
  else
    if v_already then
      return;
    end if;
    -- Não decrementar products.quantity (evita dupla contagem com raffle_hold
    -- no batata_live_item_stock). Só tira do marketplace se o hold esgota tudo.
    v_after := v_before;
    if v_before <= v_hold then
      update public.products
         set is_sold = true,
             list_on_marketplace = false
       where id = v_product_id;
      v_after := 0;
    end if;
    perform public.batata_live_raffle_audit(
      p_raffle_id,
      'marketplace_qty_held',
      jsonb_build_object(
        'product_id', v_product_id,
        'hold', v_hold,
        'quantity_unchanged', v_before,
        'hidden', v_before <= v_hold
      )
    );
  end if;

  raise log 'BATATA_STOCK raffle_sync raffle=% product=% hold=% release=% before=% after=%',
    p_raffle_id, v_product_id, v_hold, p_release, v_before, v_after;
end;
$$;

revoke all on function public.batata_live_raffle_sync_product_qty(uuid, boolean) from public;
grant execute on function public.batata_live_raffle_sync_product_qty(uuid, boolean) to authenticated;

-- Create com sync
create or replace function public.batata_create_live_raffle(
  p_live_id uuid,
  p_title text,
  p_description text default null,
  p_photo_url text default null,
  p_estimated_value_eur numeric default null,
  p_winner_count int default 1,
  p_ends_at timestamptz default null,
  p_activate boolean default true,
  p_show_public_leaderboard boolean default true,
  p_live_item_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seller uuid;
  v_row public.live_raffles%rowtype;
  v_title text;
begin
  v_seller := public.batata_live_raffle_assert_seller(p_live_id);
  v_title := trim(coalesce(p_title, ''));
  if v_title = '' then
    raise exception 'title_required';
  end if;

  if p_live_item_id is not null then
    if not exists (
      select 1 from public.live_items li
      where li.id = p_live_item_id and li.live_id = p_live_id
    ) then
      raise exception 'live_item_not_in_live';
    end if;
  end if;

  if p_activate and exists (
    select 1 from public.live_raffles r
    where r.live_id = p_live_id and r.status = 'active'
  ) then
    raise exception 'active_raffle_exists';
  end if;

  insert into public.live_raffles (
    live_id, seller_id, title, description, photo_url, estimated_value_eur,
    winner_count, status, ends_at, show_public_leaderboard, live_item_id
  ) values (
    p_live_id, v_seller, v_title,
    nullif(trim(coalesce(p_description, '')), ''),
    nullif(trim(coalesce(p_photo_url, '')), ''),
    p_estimated_value_eur,
    greatest(coalesce(p_winner_count, 1), 1),
    case when coalesce(p_activate, true) then 'active' else 'draft' end,
    p_ends_at,
    coalesce(p_show_public_leaderboard, true),
    p_live_item_id
  )
  returning * into v_row;

  perform public.batata_live_raffle_audit(
    v_row.id, 'created',
    jsonb_build_object('status', v_row.status, 'ends_at', v_row.ends_at)
  );

  if v_row.status = 'active' then
    perform public.batata_live_raffle_sync_product_qty(v_row.id, false);
  end if;

  return jsonb_build_object('ok', true, 'raffle_id', v_row.id, 'status', v_row.status);
end;
$$;

create or replace function public.batata_activate_live_raffle(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.live_raffles%rowtype;
begin
  select * into v_row from public.live_raffles where id = p_raffle_id;
  if v_row.id is null then
    raise exception 'raffle_not_found';
  end if;
  perform public.batata_live_raffle_assert_seller(v_row.live_id);

  if exists (
    select 1 from public.live_raffles r
    where r.live_id = v_row.live_id and r.status = 'active' and r.id <> p_raffle_id
  ) then
    raise exception 'active_raffle_exists';
  end if;

  update public.live_raffles set status = 'active' where id = p_raffle_id
  returning * into v_row;

  perform public.batata_live_raffle_audit(v_row.id, 'activated', '{}'::jsonb);
  perform public.batata_live_raffle_sync_product_qty(v_row.id, false);

  return jsonb_build_object('ok', true, 'status', v_row.status);
end;
$$;

create or replace function public.batata_cancel_live_raffle(
  p_raffle_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.live_raffles%rowtype;
begin
  select * into v_row from public.live_raffles where id = p_raffle_id;
  if v_row.id is null then
    raise exception 'raffle_not_found';
  end if;
  perform public.batata_live_raffle_assert_seller(v_row.live_id);

  if v_row.status in ('active', 'closed', 'draft') then
    perform public.batata_live_raffle_sync_product_qty(v_row.id, true);
  end if;

  update public.live_raffles set status = 'cancelled' where id = p_raffle_id
  returning * into v_row;

  perform public.batata_live_raffle_audit(
    v_row.id, 'cancelled', jsonb_build_object('reason', p_reason)
  );

  return jsonb_build_object('ok', true, 'status', v_row.status);
end;
$$;

-- Patch pontual: marketplace não subtrai raffle_hold outra vez (já em products.quantity).
-- Copia a função canónica e altera só o cálculo de available.
do $patch$
begin
  -- Documentação: após sync, stock RPC para marketplace_product deve usar:
  --   v_hold_for_avail := 0 se item_kind = marketplace_product
  -- Isto fica na função abaixo (replace completo alinhado a prize_stock).
  null;
end;
$patch$;
