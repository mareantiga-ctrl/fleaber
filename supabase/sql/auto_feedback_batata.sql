
-- Fleaber BATATA: feedback automático após conclusão.
--
-- Produção: gera feedback automático 48 horas após `orders.status = 'concluido'`.
--
-- Executar no SQL Editor do Supabase.

-- Compatibilidade: a app usa valores PT para `author_role`.
-- Se a tua constraint antiga só permitir outros valores, recria-a de forma segura.
alter table if exists public.reviews
  drop constraint if exists reviews_author_role_check;

alter table if exists public.reviews
  add constraint reviews_author_role_check
  check (
    author_role is null
    or author_role in ('comprador', 'vendedor', 'buyer', 'seller')
  );

alter table if exists public.orders
  add column if not exists completed_at timestamptz,
  add column if not exists auto_feedback_processed_at timestamptz;

-- Backfill para encomendas já concluídas antes deste trigger existir.
-- Mantém histórico antigo sem acelerar feedback novo.
update public.orders
set completed_at = now()
where status = 'concluido'
  and completed_at is null;

-- Se o script antigo já marcou processamento mas ainda não havia card no chat,
-- reabre o processamento para criar o aviso visível.
update public.orders o
set auto_feedback_processed_at = null
where o.status = 'concluido'
  and o.auto_feedback_processed_at is not null
  and not exists (
    select 1
    from public.chat_messages cm
    join public.chats c on c.id = cm.chat_id
    where c.product_id = o.product_id
      and (
        (c.user_a = o.buyer_id and c.user_b = o.seller_id)
        or (c.user_a = o.seller_id and c.user_b = o.buyer_id)
      )
      and cm.text like 'FLEABER_JSON_V1:%auto_feedback_generated%'
  );

create or replace function public.batata_set_order_completed_at()
returns trigger
language plpgsql
as $batata_completed$
begin
  if new.status = 'concluido'
     and (old.status is distinct from new.status)
     and new.completed_at is null then
    new.completed_at := now();
  end if;

  if old.status = 'concluido' and new.status is distinct from 'concluido' then
    new.completed_at := null;
    new.auto_feedback_processed_at := null;
  end if;

  return new;
end;
$batata_completed$;

drop trigger if exists batata_set_order_completed_at_trg on public.orders;
create trigger batata_set_order_completed_at_trg
before update on public.orders
for each row
execute function public.batata_set_order_completed_at();

create or replace function public.batata_generate_auto_feedback(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $batata_auto_feedback$
declare
  v_order record;
  v_chat record;
  v_inserted integer := 0;
  v_changed boolean;
begin
  for v_order in
    select o.id, o.buyer_id, o.seller_id, o.product_id
    from public.orders o
    where o.status = 'concluido'
      and o.completed_at is not null
      and o.completed_at <= p_now - interval '48 hours'
      and o.auto_feedback_processed_at is null
      and not exists (
        select 1
        from public.order_disputes od
        where od.order_id = o.id
          and od.status in (
            'aberta',
            'respondida_vendedor',
            'respondida_comprador',
            'escalada_fleaber'
          )
      )
  loop
    v_changed := false;

    if v_order.seller_id is not null
       and not exists (
         select 1
         from public.reviews r
         where r.order_id = v_order.id
           and r.author_role in ('buyer', 'comprador')
       ) then
      insert into public.reviews (
        target_id,
        buyer_id,
        stars,
        comment,
        is_automatic,
        target_type,
        author_role,
        order_id
      ) values (
        v_order.seller_id,
        v_order.buyer_id,
        5,
        'Avaliação automática: venda concluída sem feedback no prazo.',
        true,
        'seller',
        'comprador',
        v_order.id
      );
      v_inserted := v_inserted + 1;
      v_changed := true;
    end if;

    if v_order.buyer_id is not null
       and not exists (
         select 1
         from public.reviews r
         where r.order_id = v_order.id
           and r.author_role in ('seller', 'vendedor')
       ) then
      insert into public.reviews (
        target_id,
        buyer_id,
        stars,
        comment,
        is_automatic,
        target_type,
        author_role,
        order_id
      ) values (
        v_order.buyer_id,
        v_order.seller_id,
        5,
        'Avaliação automática: encomenda concluída sem feedback no prazo.',
        true,
        'buyer',
        'vendedor',
        v_order.id
      );
      v_inserted := v_inserted + 1;
      v_changed := true;
    end if;

    select c.id, c.user_a, c.user_b
    into v_chat
    from public.chats c
    where c.product_id = v_order.product_id
      and (
        (c.user_a = v_order.buyer_id and c.user_b = v_order.seller_id)
        or (c.user_a = v_order.seller_id and c.user_b = v_order.buyer_id)
      )
    order by c.created_at desc
    limit 1;

    if v_chat.id is not null
       and not exists (
         select 1
         from public.chat_messages cm
         where cm.chat_id = v_chat.id
           and cm.text like 'FLEABER_JSON_V1:%auto_feedback_generated%'
           and cm.text like '%' || v_order.id::text || '%'
       ) then
      insert into public.chat_messages (
        sender_id,
        receiver_id,
        is_read,
        text,
        chat_id,
        is_reservation
      ) values (
        v_order.seller_id,
        v_order.buyer_id,
        false,
        'FLEABER_JSON_V1:' || jsonb_build_object(
          'kind', 'auto_feedback_generated',
          'order_id', v_order.id,
          'message', 'O sistema gerou automaticamente avaliações de 5 estrelas para comprador e vendedor porque passou o prazo sem avaliação manual.',
          'v', 1
        )::text,
        v_chat.id,
        true
      );

      update public.chats
      set last_message = 'Feedback automático: 5 estrelas geradas',
          last_message_time = p_now
      where id = v_chat.id;

      v_changed := true;
    end if;

    begin
      perform public.batata_release_seller_wallet_for_order(v_order.id);
    exception
      when undefined_function then
        null;
    end;

    update public.orders
    set auto_feedback_processed_at = p_now
    where id = v_order.id;
  end loop;

  return v_inserted;
end;
$batata_auto_feedback$;

-- pg_cron corre no servidor, por isso não depende de abrir a app/chat.
create extension if not exists pg_cron with schema extensions;

do $cron_unschedule_5min$
begin
  perform cron.unschedule('batata-auto-feedback-5min');
exception
  when others then
    null;
end;
$cron_unschedule_5min$;

do $cron_unschedule_48h$
begin
  perform cron.unschedule('batata-auto-feedback-48h');
exception
  when others then
    null;
end;
$cron_unschedule_48h$;

select cron.schedule('batata-auto-feedback-48h', '* * * * *', 'select public.batata_generate_auto_feedback();');
