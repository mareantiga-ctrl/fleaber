-- Notificações in-app (propostas de preço, etc.) + trigger para proposta nova.
-- Push no telemóvel: a app subscreve Realtime e mostra alerta (FCM opcional depois).

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null,
  chat_id uuid references public.chats(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  offer_id uuid references public.product_offers(id) on delete set null,
  actor_id uuid references auth.users(id) on delete set null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists user_notifications_user_created_idx
  on public.user_notifications (user_id, created_at desc);

create index if not exists user_notifications_user_unread_idx
  on public.user_notifications (user_id)
  where is_read = false;

alter table public.user_notifications enable row level security;

drop policy if exists "user_notifications_select_own" on public.user_notifications;
create policy "user_notifications_select_own"
  on public.user_notifications
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "user_notifications_update_own" on public.user_notifications;
create policy "user_notifications_update_own"
  on public.user_notifications
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create or replace function public.batata_notify_price_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $batata_notify_price_offer$
declare
  v_recipient uuid;
  v_actor uuid;
  v_product_title text;
  v_amount text;
  v_title text;
  v_body text;
begin
  if new.status <> 'pending' then
    return new;
  end if;

  if new.offered_by = 'buyer' then
    v_recipient := new.seller_id;
    v_actor := new.buyer_id;
    v_title := 'Nova proposta de preço';
  else
    v_recipient := new.buyer_id;
    v_actor := new.seller_id;
    v_title := 'Nova contra-proposta';
  end if;

  select coalesce(nullif(trim(title), ''), 'Artigo')
  into v_product_title
  from public.products
  where id = new.product_id;

  v_amount := to_char(new.amount, 'FM999999990.00') || ' €';
  v_body := v_amount || ' · ' || v_product_title;

  insert into public.user_notifications (
    user_id,
    kind,
    title,
    body,
    chat_id,
    product_id,
    offer_id,
    actor_id
  )
  values (
    v_recipient,
    case when new.offered_by = 'buyer' then 'price_offer' else 'price_offer_counter' end,
    v_title,
    v_body,
    new.chat_id,
    new.product_id,
    new.id,
    v_actor
  );

  return new;
end;
$batata_notify_price_offer$;

drop trigger if exists batata_product_offers_notify on public.product_offers;
create trigger batata_product_offers_notify
  after insert on public.product_offers
  for each row
  execute function public.batata_notify_price_offer();

-- Realtime (Dashboard → Database → Replication, ou):
-- alter publication supabase_realtime add table public.user_notifications;
