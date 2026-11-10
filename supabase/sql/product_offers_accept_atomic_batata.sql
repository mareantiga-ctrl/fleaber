-- BATATA 2026-09-30: aceitação atómica de product_offers.
-- Problema: dois UPDATE concurrentes pending→accepted no mesmo product_id
--         passam os guards (auth/expire/sold) e criam duas reservas/encomendas.
-- Solução: serializar por product_id; rejeitar se já existe aceite activo;
--          supersede siblings pending no mesmo TX (autoridade BD, não só Flutter).

create or replace function public.batata_product_offers_accept_atomic()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_new_st text;
  v_old_st text;
  v_blocking int := 0;
begin
  if TG_OP is distinct from 'UPDATE' then
    return NEW;
  end if;

  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_old_st := lower(trim(coalesce(OLD.status, '')));

  if v_new_st is distinct from 'accepted' or v_old_st = 'accepted' then
    return NEW;
  end if;

  -- Serializa aceites no mesmo artigo (advisory lock por product_id).
  perform pg_advisory_xact_lock(
    hashtextextended(coalesce(NEW.product_id::text, ''), 0)
  );

  -- Lock da linha do produto (stock / is_sold).
  perform 1
  from public.products p
  where p.id = NEW.product_id
  for update;

  -- Artigo vendido / sem stock → não aceitar.
  if exists (
    select 1
    from public.products p
    where p.id = NEW.product_id
      and (
        coalesce(p.is_sold, false) = true
        or coalesce(p.quantity, 0) <= 0
      )
  ) then
    raise exception 'offer_product_not_available' using errcode = '23514';
  end if;

  -- Já existe encomenda bloqueante noutro/mesmo fluxo?
  select count(*)::int into v_blocking
  from public.orders o
  where o.product_id = NEW.product_id
    and lower(trim(coalesce(o.status, ''))) in (
      'pago', 'premio_rifa', 'enviado', 'reservado',
      'aguarda_confirmacao', 'pendente',
      'pedido_devolucao', 'em_devolucao',
      'entregue', 'concluido'
    );

  if v_blocking > 0 then
    raise exception 'offer_product_already_committed' using errcode = '23514';
  end if;

  -- Outra oferta já aceite sem encomenda cancelada ligada (corrida sem order ainda).
  if exists (
    select 1
    from public.product_offers po
    where po.product_id = NEW.product_id
      and po.id is distinct from NEW.id
      and lower(trim(coalesce(po.status, ''))) = 'accepted'
      and (
        exists (
          select 1
          from public.orders o
          where o.product_offer_id = po.id
            and lower(trim(coalesce(o.status, ''))) not in (
              'cancelado', 'cancelada', 'cancelled', 'canceled',
              'anulado', 'anulada', 'expirado', 'expired'
            )
        )
        or (
          po.responded_at is not null
          and po.responded_at > now() - interval '2 minutes'
          and not exists (
            select 1
            from public.orders o
            where o.product_offer_id = po.id
              and lower(trim(coalesce(o.status, ''))) in (
                'cancelado', 'cancelada', 'cancelled', 'canceled',
                'anulado', 'anulada', 'expirado', 'expired'
              )
          )
        )
      )
  ) then
    raise exception 'offer_sibling_already_accepted' using errcode = '23514';
  end if;

  NEW.responded_at := coalesce(NEW.responded_at, now());

  -- Supersede restantes pending do artigo (mesmo TX).
  update public.product_offers po
  set
    status = 'superseded',
    responded_at = now()
  where po.product_id = NEW.product_id
    and po.id is distinct from NEW.id
    and lower(trim(coalesce(po.status, ''))) = 'pending';

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_product_offers_accept_atomic on public.product_offers;
create trigger trg_batata_product_offers_accept_atomic
  before update on public.product_offers
  for each row
  execute function public.batata_product_offers_accept_atomic();

comment on function public.batata_product_offers_accept_atomic() is
  'C1-2026-09-30: um aceite vence por product_id; siblings pending → superseded; serializa com advisory lock.';
