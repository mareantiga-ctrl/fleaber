-- =============================================================================
-- LOTE FINAL P1 pós-2 auditores (staging only). NÃO Fase 4.
-- B: reviews buyer/comprador canónicos
-- C: payment_method allowlist exacta (sem LIKE solto)
-- F: dispute current_turn=administracao só em estado terminal
-- =============================================================================

-- ---------------------------------------------------------------------------
-- C) Off-platform: só strings canónicas do produto (fail-closed)
-- ---------------------------------------------------------------------------
create or replace function public.batata_is_off_platform_payment(p_method text)
returns boolean
language sql
immutable
as $$
  -- Valores reais Flutter: «MB WAY», «Pagamento Direto ao Vendedor (MB WAY/Transf)»,
  -- aliases curtos. SEM like '%mb way%' solto (evita «Pagamento na App (MB WAY/Transf)»).
  select public.batata_normalize_payment_method(p_method) in (
    'mb way',
    'mb_way',
    'mb-way',
    'mbway',
    'transferencia',
    'transferência',
    'transfer',
    'transf',
    'pagamento directo',
    'pagamento direto',
    'pagamento_directo',
    'pagamento_direto',
    'directo',
    'direto',
    'entrega em mao',
    'entrega em mão',
    'em mao',
    'em mão',
    'levantamento',
    'combinado',
    'combinada',
    'pagamento direto ao vendedor (mb way/transf)',
    'pagamento directo ao vendedor (mb way/transf)'
  );
$$;

comment on function public.batata_is_off_platform_payment(text) is
  'LOTE FINAL: allowlist exacta off-platform; sem substring livre.';

revoke all on function public.batata_is_off_platform_payment(text) from public, anon;
grant execute on function public.batata_is_off_platform_payment(text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- B) Reviews: canonicalizar author_role + unique canónica
-- ---------------------------------------------------------------------------
create or replace function public.batata_review_author_role_canonical(p_role text)
returns text
language sql
immutable
as $$
  select case lower(trim(coalesce(p_role, '')))
    when 'buyer' then 'comprador'
    when 'comprador' then 'comprador'
    when 'seller' then 'vendedor'
    when 'vendedor' then 'vendedor'
    when '' then 'comprador'
    else lower(trim(p_role))
  end;
$$;

revoke all on function public.batata_review_author_role_canonical(text) from public, anon;
grant execute on function public.batata_review_author_role_canonical(text)
  to authenticated, service_role;

-- Normalizar rows históricas + dedupe aliases (staging-safe: mantém a mais antiga)
update public.reviews
set author_role = public.batata_review_author_role_canonical(author_role)
where author_role is distinct from public.batata_review_author_role_canonical(author_role);

with ranked as (
  select
    id,
    row_number() over (
      partition by
        order_id,
        buyer_id,
        public.batata_review_author_role_canonical(author_role)
      order by created_at nulls last, id
    ) as rn
  from public.reviews
  where order_id is not null
)
delete from public.reviews r
using ranked x
where r.id = x.id
  and x.rn > 1;

create or replace function public.batata_reviews_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_order public.orders%rowtype;
  v_canon text;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    -- service_role / auto-feedback: ainda assim canónico
    NEW.author_role := public.batata_review_author_role_canonical(NEW.author_role);
    return NEW;
  end if;

  NEW.buyer_id := v_uid;
  NEW.is_automatic := false;
  -- JWT buyer da order: só comprador (não forja vendedor)
  NEW.author_role := 'comprador';
  v_canon := 'comprador';

  if NEW.order_id is null then
    raise exception 'review_order_required' using errcode = '23514';
  end if;

  select * into v_order from public.orders where id = NEW.order_id;
  if not found or v_order.buyer_id is distinct from v_uid then
    raise exception 'review_order_not_yours' using errcode = '42501';
  end if;

  if lower(coalesce(v_order.status, '')) not in ('concluido', 'entregue') then
    raise exception 'review_order_invalid_status' using errcode = '23514';
  end if;

  if not public.batata_order_payment_confirmed(
       v_order.payment_method,
       v_order.status,
       v_order.amount_paid_cents,
       v_order.stripe_payment_intent_id
     ) then
    raise exception 'review_order_unpaid' using errcode = '23514';
  end if;

  if public.batata_is_off_platform_payment(v_order.payment_method)
     and coalesce(v_order.stock_units_applied, 0) <= 0
     and coalesce(v_order.amount_paid_cents, 0) <= 0 then
    raise exception 'review_order_unpaid' using errcode = '23514';
  end if;

  NEW.target_id := v_order.seller_id;

  -- Duplicado por alias (buyer/comprador)
  if v_canon = 'comprador' and exists (
    select 1 from public.reviews r
    where r.order_id = NEW.order_id
      and r.buyer_id = v_uid
      and public.batata_review_author_role_canonical(r.author_role) = 'comprador'
  ) then
    raise exception 'review_duplicate' using errcode = '23505';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_reviews_guard_insert on public.reviews;
create trigger trg_batata_reviews_guard_insert
  before insert on public.reviews
  for each row
  execute function public.batata_reviews_guard_insert();

-- Índice único canónico (substitui o que só cobria 'comprador')
drop index if exists public.reviews_buyer_order_comprador_uidx;

create unique index if not exists reviews_buyer_order_role_canon_uidx
  on public.reviews (
    order_id,
    buyer_id,
    (public.batata_review_author_role_canonical(author_role))
  )
  where order_id is not null;

-- ---------------------------------------------------------------------------
-- F) Disputas: current_turn=administracao só com status terminal
--     (evita DoS: PATCH só current_turn bloqueia UI sem resolver)
--     Parties PODEM resolver (produto: cancel/close/accept) → força turn admin.
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_disputes_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_st text;
  v_new_st text;
  v_new_turn text;
  v_terminal boolean;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  v_old_st := lower(trim(coalesce(OLD.status, '')));
  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_new_turn := lower(trim(coalesce(NEW.current_turn, '')));
  v_terminal := v_new_st in (
    'resolvida', 'fechada', 'closed', 'resolved', 'recusada',
    'cancelada', 'concluida', 'concluída', 'arquivada'
  );

  -- Já terminal: congelar (SAT)
  if v_old_st in (
    'resolvida', 'fechada', 'closed', 'resolved', 'recusada',
    'cancelada', 'concluida', 'concluída', 'arquivada'
  ) then
    NEW.seller_refund_percent := OLD.seller_refund_percent;
    NEW.seller_offer_type := OLD.seller_offer_type;
    NEW.seller_pays_return_shipping := OLD.seller_pays_return_shipping;
    NEW.seller_offer_set_by := OLD.seller_offer_set_by;
    NEW.seller_offer_set_at := OLD.seller_offer_set_at;
    NEW.buyer_decision := OLD.buyer_decision;
    NEW.admin_resolution := OLD.admin_resolution;
    NEW.admin_resolution_note := OLD.admin_resolution_note;
    NEW.status := OLD.status;
    NEW.current_turn := OLD.current_turn;
    return NEW;
  end if;

  -- Não permitir current_turn=administracao sem fechar a disputa
  if v_new_turn = 'administracao' and not v_terminal then
    NEW.current_turn := OLD.current_turn;
  end if;

  -- Ao resolver legitimamente, turn fica administracao (estacionamento, não privilégio)
  if v_terminal then
    NEW.current_turn := 'administracao';
  end if;

  -- JWT não escreve campos admin
  if NEW.admin_resolution is distinct from OLD.admin_resolution then
    NEW.admin_resolution := OLD.admin_resolution;
  end if;
  if NEW.admin_resolution_note is distinct from OLD.admin_resolution_note then
    NEW.admin_resolution_note := OLD.admin_resolution_note;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_guard_authority on public.order_disputes;
create trigger trg_batata_order_disputes_guard_authority
  before update on public.order_disputes
  for each row
  execute function public.batata_order_disputes_guard_authority();

-- Manter terminal guard em cadeia (se existir, authority cobre o essencial)
drop trigger if exists trg_batata_order_disputes_guard_terminal on public.order_disputes;

notify pgrst, 'reload schema';
