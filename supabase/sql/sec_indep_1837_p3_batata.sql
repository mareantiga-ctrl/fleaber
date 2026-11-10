-- =============================================================================
-- BATATA — Indep 1837 P3 (staging)
-- P0/P1: zero. Fechar higiene tip session_id.
-- production_touched: false · fase4: false
-- =============================================================================

-- RT1837-P3-01: JWT não escolhe stripe_session_id (só Edge/service grava cs_ real)
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

  v_fee := public.batata_live_tip_processing_fee(v_amount);
  v_seller_amount := public.batata_live_tip_seller_amount(v_amount);
  v_note := nullif(trim(coalesce(p_message, '')), '');

  -- RT1837-P3-01: ignorar p_stripe_session_id do cliente (lixo / spoof).
  -- Edge create-live-tip-checkout cria pending sem session e depois UPDATE com service_role.
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

comment on function public.batata_create_live_tip_pending(uuid, uuid, numeric, text, text) is
  'RT1837-P3-01: stripe_session_id sempre null no create JWT; Edge faz bind depois.';

-- RT1837-P3-02: email→UUID — CLOSED_BY_DESIGN (convites staff); rate 2/h + seller c/ produtos.
-- Sem alteração de comportamento; só carimbo.
comment on function public.batata_find_user_id_by_email(text) is
  'RT1837-P3-02 CLOSED_BY_DESIGN: seller com produtos + rate 2/h (convites helper).';

notify pgrst, 'reload schema';
