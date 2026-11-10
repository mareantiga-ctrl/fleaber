-- Fleaber BATATA: resolução admin de disputas + etiqueta de devolução.
-- Executar no SQL Editor do Supabase.

alter table if exists public.order_disputes
  add column if not exists return_label_deadline timestamptz,
  add column if not exists return_label_url text,
  add column if not exists admin_resolution text,
  add column if not exists admin_resolution_note text;

create or replace function public.batata_admin_resolve_dispute(
  p_dispute_id uuid,
  p_resolution text,
  p_note text default ''
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dispute public.order_disputes%rowtype;
  v_order public.orders%rowtype;
  v_note text := coalesce(nullif(trim(p_note), ''), 'Decisão da Administração Fleaber');
begin
  if not public.batata_is_admin() then
    raise exception 'Apenas administradores podem resolver disputas.';
  end if;

  select * into v_dispute
  from public.order_disputes
  where id = p_dispute_id;

  if not found then
    return false;
  end if;

  select * into v_order
  from public.orders
  where id = v_dispute.order_id;

  if not found then
    return false;
  end if;

  insert into public.order_dispute_replies (
    dispute_id,
    sender_id,
    message,
    proof_photos
  ) values (
    v_dispute.id,
    auth.uid(),
    v_note,
    '{}'
  );

  if p_resolution = 'favor_buyer_refund' then
    perform public.batata_refund_buyer_wallet_for_order(v_order.id);

    update public.orders
    set status = 'devolvida',
        returned_at = coalesce(returned_at, now())
    where id = v_order.id;

    update public.order_disputes
    set status = 'resolvida',
        current_turn = 'administracao',
        admin_resolution = 'favor_buyer_refund',
        admin_resolution_note = v_note,
        next_deadline = now()
    where id = v_dispute.id;

    return true;
  end if;

  if p_resolution = 'favor_seller' then
    update public.orders
    set status = 'concluido'
    where id = v_order.id;

    perform public.batata_release_seller_wallet_for_order(v_order.id);

    update public.order_disputes
    set status = 'resolvida',
        current_turn = 'administracao',
        admin_resolution = 'favor_seller',
        admin_resolution_note = v_note,
        next_deadline = now()
    where id = v_dispute.id;

    return true;
  end if;

  if p_resolution = 'approve_return' then
    update public.orders
    set status = 'em_devolucao'
    where id = v_order.id;

    update public.order_disputes
    set buyer_decision = 'accepted_return',
        status = 'respondida_comprador',
        current_turn = 'comprador',
        return_label_created_at = coalesce(return_label_created_at, now()),
        return_label_deadline = now() + interval '5 days',
        return_label_url = coalesce(
          return_label_url,
          'https://fleaber.app/return-label/' || v_order.id::text
        ),
        admin_resolution = 'approve_return',
        admin_resolution_note = v_note,
        next_deadline = now() + interval '5 days'
    where id = v_dispute.id;

    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.batata_admin_resolve_dispute(uuid, text, text) to authenticated;
