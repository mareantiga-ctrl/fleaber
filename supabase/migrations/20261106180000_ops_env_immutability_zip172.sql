-- ZIP 172-C1: imutabilidade ops_stripe_mode / ops_dpd_mode após finance ou expedição.
-- Não activa LIVE/COMERCIAL. Não altera defaults TEST+QA.

create or replace function public.batata_order_ops_env_locked(p_ord public.orders)
returns boolean
language sql
stable
as $$
  select
    coalesce(nullif(trim(p_ord.stripe_payment_intent_id), ''), null) is not null
    or coalesce(nullif(trim(p_ord.stripe_checkout_session_id), ''), null) is not null
    or coalesce(p_ord.amount_paid_cents, 0) > 0
    or lower(trim(coalesce(p_ord.status, ''))) in (
      'pago', 'enviado', 'entregue', 'concluido', 'paid', 'shipped', 'delivered'
    )
    or coalesce(nullif(trim(p_ord.dpd_expedition_id), ''), null) is not null
    or coalesce(nullif(trim(p_ord.dpd_tracking_code), ''), null) is not null
    or p_ord.dpd_created_at is not null;
$$;

comment on function public.batata_order_ops_env_locked(public.orders) is
  'ZIP172: true se a encomenda já entrou em ciclo financeiro ou de expedição DPD.';

create or replace function public.batata_orders_ops_env_immutable_trg()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  if coalesce(OLD.ops_stripe_mode, 'test') is distinct from coalesce(NEW.ops_stripe_mode, 'test')
     or coalesce(OLD.ops_dpd_mode, 'qa') is distinct from coalesce(NEW.ops_dpd_mode, 'qa')
     or OLD.ops_env_session_id is distinct from NEW.ops_env_session_id then
    if public.batata_order_ops_env_locked(OLD) then
      raise exception 'ops_env_immutable_after_finance_or_shipping'
        using errcode = 'P0001';
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_orders_ops_env_immutable on public.orders;
create trigger trg_orders_ops_env_immutable
  before update on public.orders
  for each row
  execute function public.batata_orders_ops_env_immutable_trg();

-- Bind: reforçar bloqueio se já há expedição DPD (além de PI/status).
create or replace function public.batata_admin_ops_env_bind_order(
  p_order_id uuid,
  p_session_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_sess public.ops_env_sessions%rowtype;
  v_ord public.orders%rowtype;
begin
  if v_uid is null or not public.batata_is_platform_admin(v_uid) then
    raise exception 'not_admin';
  end if;

  select * into v_ord from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'order_not_found';
  end if;
  if public.batata_order_ops_env_locked(v_ord) then
    raise exception 'order_already_in_payment_or_shipping_cycle';
  end if;

  if p_session_id is null then
    select * into v_sess from public.ops_env_sessions
    where is_active order by created_at desc limit 1;
  else
    select * into v_sess from public.ops_env_sessions where id = p_session_id;
  end if;
  if not found then
    raise exception 'session_not_found';
  end if;

  update public.orders
  set ops_stripe_mode = v_sess.stripe_mode,
      ops_dpd_mode = v_sess.dpd_mode,
      ops_env_session_id = v_sess.id
  where id = p_order_id;

  insert into public.ops_env_audit (
    actor_id, action, stripe_mode, dpd_mode, order_id, session_id, detail
  ) values (
    v_uid, 'order_bind', v_sess.stripe_mode, v_sess.dpd_mode, p_order_id, v_sess.id,
    jsonb_build_object('prev_stripe', v_ord.ops_stripe_mode, 'prev_dpd', v_ord.ops_dpd_mode)
  );

  return jsonb_build_object(
    'ok', true,
    'order_id', p_order_id,
    'stripe_mode', v_sess.stripe_mode,
    'dpd_mode', v_sess.dpd_mode,
    'execution_ready', (v_sess.stripe_mode = 'test' and v_sess.dpd_mode = 'qa')
  );
end;
$$;

revoke all on function public.batata_admin_ops_env_bind_order(uuid, uuid) from public, anon;
grant execute on function public.batata_admin_ops_env_bind_order(uuid, uuid)
  to authenticated, service_role;

-- Status admin: matriz ZIP 172 (bloqueios estruturais)
create or replace function public.batata_admin_ops_env_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_sess jsonb;
begin
  if v_uid is null or not public.batata_is_platform_admin(v_uid) then
    raise exception 'not_admin';
  end if;
  select to_jsonb(s) into v_sess
  from (
    select id, created_at, created_by, stripe_mode, dpd_mode, reason,
           confirm_real, is_active, note
    from public.ops_env_sessions
    where is_active
    order by created_at desc
    limit 1
  ) s;

  return jsonb_build_object(
    'ok', true,
    'default_for_new_orders', jsonb_build_object('stripe_mode','test','dpd_mode','qa'),
    'active_session', v_sess,
    'zip', '172',
    'matrix', jsonb_build_object(
      'test_qa', 'functional',
      'live_qa', 'blocked_until_go_stripe_live_key_and_webhook',
      'test_commercial', 'blocked_until_go_dpd_live_creds_and_create_flag',
      'live_commercial', 'blocked_until_go_both'
    ),
    'notes', jsonb_build_object(
      'panel_scope', 'authorized_test_ops_only',
      'no_global_flip', true,
      'immutable_after_finance_or_shipping', true
    )
  );
end;
$$;

revoke all on function public.batata_admin_ops_env_status() from public, anon;
grant execute on function public.batata_admin_ops_env_status() to authenticated, service_role;
