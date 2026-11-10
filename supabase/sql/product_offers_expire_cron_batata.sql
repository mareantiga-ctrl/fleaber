-- Expira propostas pendentes após expires_at (48h por defeito).
-- Executar no SQL Editor do Supabase (requer pg_cron).

create extension if not exists pg_cron with schema extensions;

create or replace function public.batata_expire_product_offers()
returns integer
language plpgsql
security definer
set search_path = public
as $batata_expire_product_offers$
declare
  r record;
  v_count integer := 0;
  v_amount text;
  v_payload text;
  v_preview text;
begin
  for r in
    select *
    from public.product_offers
    where status = 'pending'
      and expires_at < now()
    for update skip locked
  loop
    update public.product_offers
    set
      status = 'expired',
      responded_at = now()
    where id = r.id;

    v_count := v_count + 1;

    if r.chat_id is null then
      continue;
    end if;

    v_amount := to_char(r.amount, 'FM999999990.00') || ' €';
    v_preview := 'Proposta expirada (' || v_amount || ')';
    -- Prefixo obrigatório — sem isto o chat mostra JSON cru (BUG 2026-09-12).
    v_payload := 'FLEABER_JSON_V1:' || jsonb_build_object(
      'kind', 'price_offer_outcome',
      'offer_id', r.id,
      'product_id', r.product_id,
      'buyer_id', r.buyer_id,
      'seller_id', r.seller_id,
      'amount', r.amount,
      'outcome', 'expired',
      'offered_by', r.offered_by,
      'v', 1
    )::text;

    insert into public.chat_messages (
      sender_id,
      receiver_id,
      chat_id,
      text,
      is_read,
      is_reservation
    )
    values (
      r.seller_id,
      r.buyer_id,
      r.chat_id,
      v_payload,
      false,
      false
    );

    update public.chats
    set
      last_message = v_preview,
      last_message_time = now()
    where id = r.chat_id;
  end loop;

  return v_count;
end;
$batata_expire_product_offers$;

comment on function public.batata_expire_product_offers() is
  'Marca propostas pending expiradas e regista outcome no chat.';

do $cron_unschedule$
begin
  perform cron.unschedule('batata-product-offers-expire');
exception
  when others then
    null;
end;
$cron_unschedule$;

-- A cada 15 minutos (UTC).
select cron.schedule(
  'batata-product-offers-expire',
  '*/15 * * * *',
  $$ select public.batata_expire_product_offers(); $$
);

-- Teste manual:
-- select public.batata_expire_product_offers();
