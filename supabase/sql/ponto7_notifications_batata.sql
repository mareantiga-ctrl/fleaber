-- Ponto 7 — Notificações (PROPOSTA — NÃO aplicar em produção sem autorização)
-- Inbox server-side + tokens FCM + ledger de entrega (push/e-mail).
-- RLS: sem INSERT authenticated em user_notifications (mantém-se).
-- Writers: SECURITY DEFINER com authz por kind + service_role.

-- ---------------------------------------------------------------------------
-- 1) Extensões de schema
-- ---------------------------------------------------------------------------

alter table public.user_notifications
  add column if not exists dedupe_key text;

create unique index if not exists user_notifications_dedupe_key_uidx
  on public.user_notifications (dedupe_key)
  where dedupe_key is not null;

comment on column public.user_notifications.dedupe_key is
  'Chave idempotente (ex. bundle:uuid:kind). UNIQUE parcial — anti-duplicados.';

create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null,
  platform text not null default 'android'
    check (platform in ('android', 'ios', 'web')),
  app_version text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint device_push_tokens_token_unique unique (token)
);

create index if not exists device_push_tokens_user_active_idx
  on public.device_push_tokens (user_id)
  where revoked_at is null;

alter table public.device_push_tokens enable row level security;

drop policy if exists "device_push_tokens_select_own" on public.device_push_tokens;
create policy "device_push_tokens_select_own"
  on public.device_push_tokens for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "device_push_tokens_insert_own" on public.device_push_tokens;
create policy "device_push_tokens_insert_own"
  on public.device_push_tokens for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "device_push_tokens_update_own" on public.device_push_tokens;
create policy "device_push_tokens_update_own"
  on public.device_push_tokens for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "device_push_tokens_delete_own" on public.device_push_tokens;
create policy "device_push_tokens_delete_own"
  on public.device_push_tokens for delete to authenticated
  using (user_id = auth.uid());

create table if not exists public.notification_delivery_log (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid references public.user_notifications (id) on delete set null,
  user_id uuid references auth.users (id) on delete set null,
  channel text not null check (channel in ('push', 'email', 'inbox')),
  kind text not null,
  dedupe_key text,
  status text not null check (status in ('queued', 'sent', 'skipped', 'failed')),
  provider_ref text,
  error_text text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists notification_delivery_log_dedupe_channel_idx
  on public.notification_delivery_log (dedupe_key, channel, status);

create unique index if not exists notification_delivery_log_success_uidx
  on public.notification_delivery_log (dedupe_key, channel)
  where status = 'sent' and dedupe_key is not null;

alter table public.notification_delivery_log enable row level security;
-- Sem policies authenticated: só service_role / definer escreve; users não leem.

-- ---------------------------------------------------------------------------
-- 2) Helpers
-- ---------------------------------------------------------------------------

create or replace function public.batata_notify_is_service_role()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role';
$$;

create or replace function public.batata_notify_chat_other_party(
  p_chat_id uuid,
  p_actor uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_a uuid;
  v_b uuid;
begin
  select user_a, user_b into v_a, v_b
  from public.chats
  where id = p_chat_id;
  if v_a is null then
    return null;
  end if;
  if p_actor = v_a then
    return v_b;
  end if;
  if p_actor = v_b then
    return v_a;
  end if;
  return null;
end;
$$;

revoke all on function public.batata_notify_chat_other_party(uuid, uuid) from public;

-- ---------------------------------------------------------------------------
-- 3) Emit inbox — trusted (triggers) + client RPC com authz
-- ---------------------------------------------------------------------------

create or replace function public.batata_emit_user_notification_trusted(
  p_recipient_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_chat_id uuid default null,
  p_product_id uuid default null,
  p_offer_id uuid default null,
  p_actor_id uuid default null,
  p_dedupe_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_title text := left(trim(coalesce(p_title, '')), 120);
  v_body text := left(trim(coalesce(p_body, '')), 240);
  v_dedupe text := nullif(trim(coalesce(p_dedupe_key, '')), '');
  v_id uuid;
begin
  if p_recipient_id is null or v_kind = '' or v_title = '' then
    return null;
  end if;

  if v_dedupe is not null then
    select id into v_id
    from public.user_notifications
    where dedupe_key = v_dedupe
    limit 1;
    if v_id is not null then
      return v_id;
    end if;
  end if;

  begin
    insert into public.user_notifications (
      user_id, kind, title, body, chat_id, product_id, offer_id, actor_id, dedupe_key, is_read
    ) values (
      p_recipient_id,
      v_kind,
      v_title,
      coalesce(nullif(v_body, ''), v_title),
      p_chat_id,
      p_product_id,
      p_offer_id,
      p_actor_id,
      v_dedupe,
      false
    )
    returning id into v_id;
  exception
    when unique_violation then
      select id into v_id
      from public.user_notifications
      where dedupe_key = v_dedupe
      limit 1;
  end;

  return v_id;
end;
$$;

revoke all on function public.batata_emit_user_notification_trusted(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text
) from public;
-- Só service_role (Edge) + funções DEFINER no mesmo owner.
grant execute on function public.batata_emit_user_notification_trusted(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text
) to service_role;

create or replace function public.batata_emit_user_notification(
  p_recipient_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_chat_id uuid default null,
  p_product_id uuid default null,
  p_offer_id uuid default null,
  p_actor_id uuid default null,
  p_dedupe_key text default null,
  p_order_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_service boolean := public.batata_notify_is_service_role();
  v_actor uuid := coalesce(p_actor_id, v_uid);
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_other uuid;
  v_buyer uuid;
  v_seller uuid;
begin
  if v_service then
    return public.batata_emit_user_notification_trusted(
      p_recipient_id, p_kind, p_title, p_body,
      p_chat_id, p_product_id, p_offer_id, v_actor, p_dedupe_key
    );
  end if;

  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_recipient_id is null or v_kind = '' then
    raise exception 'invalid_args';
  end if;
  if p_recipient_id = v_uid then
    raise exception 'not_allowed: cannot notify self';
  end if;

  if v_kind in (
    'bundle_proposal',
    'bundle_proposal_counter',
    'bundle_purchase_request',
    'chat_message',
    'price_offer_outcome'
  ) then
    if p_chat_id is null then
      raise exception 'chat_id_required';
    end if;
    v_other := public.batata_notify_chat_other_party(p_chat_id, v_uid);
    if v_other is null or v_other <> p_recipient_id then
      raise exception 'not_allowed: chat party';
    end if;
  elsif v_kind in ('seguro_fleaber_paid', 'order_paid_seller', 'order_paid_buyer') then
    if p_order_id is not null then
      select buyer_id, seller_id into v_buyer, v_seller
      from public.orders where id = p_order_id;
      if v_buyer is null then
        raise exception 'order_not_found';
      end if;
      if v_uid <> v_buyer and v_uid <> v_seller then
        raise exception 'not_allowed: order party';
      end if;
      if p_recipient_id <> v_buyer and p_recipient_id <> v_seller then
        raise exception 'not_allowed: recipient not on order';
      end if;
    elsif p_chat_id is not null then
      v_other := public.batata_notify_chat_other_party(p_chat_id, v_uid);
      if v_other is null or v_other <> p_recipient_id then
        raise exception 'not_allowed: chat party';
      end if;
    else
      raise exception 'order_or_chat_required';
    end if;
  elsif v_kind = 'reservation_order_shipped' then
    if p_order_id is null then
      raise exception 'order_id_required';
    end if;
    select buyer_id, seller_id into v_buyer, v_seller
    from public.orders where id = p_order_id;
    if v_buyer is null or v_uid <> v_seller then
      raise exception 'not_allowed: only seller ships';
    end if;
    if p_recipient_id <> v_buyer then
      raise exception 'not_allowed: ship notify buyer only';
    end if;
  elsif v_kind in ('price_offer', 'price_offer_counter') then
    if p_offer_id is null then
      raise exception 'offer_id_required';
    end if;
    select buyer_id, seller_id into v_buyer, v_seller
    from public.product_offers where id = p_offer_id;
    if v_buyer is null then
      raise exception 'offer_not_found';
    end if;
    if v_uid <> v_buyer and v_uid <> v_seller then
      raise exception 'not_allowed: offer party';
    end if;
    if p_recipient_id <> v_buyer and p_recipient_id <> v_seller then
      raise exception 'not_allowed: recipient';
    end if;
  else
    raise exception 'kind_not_allowed_for_client: %', v_kind;
  end if;

  return public.batata_emit_user_notification_trusted(
    p_recipient_id, p_kind, p_title, p_body,
    p_chat_id, p_product_id, p_offer_id, v_actor, p_dedupe_key
  );
end;
$$;

revoke all on function public.batata_emit_user_notification(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text, uuid
) from public;
grant execute on function public.batata_emit_user_notification(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text, uuid
) to authenticated;
grant execute on function public.batata_emit_user_notification(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text, uuid
) to service_role;

-- ---------------------------------------------------------------------------
-- 4) Tokens FCM
-- ---------------------------------------------------------------------------

create or replace function public.batata_register_push_token(
  p_token text,
  p_platform text default 'android',
  p_app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_plat text := lower(trim(coalesce(p_platform, 'android')));
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if nullif(trim(coalesce(p_token, '')), '') is null then
    raise exception 'token_required';
  end if;
  if v_plat not in ('android', 'ios', 'web') then
    v_plat := 'android';
  end if;

  insert into public.device_push_tokens (user_id, token, platform, app_version, last_seen_at, revoked_at)
  values (v_uid, trim(p_token), v_plat, p_app_version, now(), null)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        app_version = excluded.app_version,
        last_seen_at = now(),
        revoked_at = null
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.batata_register_push_token(text, text, text) from public;
grant execute on function public.batata_register_push_token(text, text, text) to authenticated;

create or replace function public.batata_revoke_push_token(p_token text default null)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  n int := 0;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if nullif(trim(coalesce(p_token, '')), '') is null then
    update public.device_push_tokens
    set revoked_at = now()
    where user_id = v_uid and revoked_at is null;
  else
    update public.device_push_tokens
    set revoked_at = now()
    where user_id = v_uid and token = trim(p_token) and revoked_at is null;
  end if;
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.batata_revoke_push_token(text) from public;
grant execute on function public.batata_revoke_push_token(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Trigger: mensagem de chat humana → inbox (+ dedupe por message id)
--     Push/e-mail: Edge notify-dispatch (webhook / invoke pós-insert).
-- ---------------------------------------------------------------------------

create or replace function public.batata_notify_on_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_other uuid;
  v_title text := 'Nova mensagem';
  v_body text := 'Tens uma nova mensagem na Fleaber.';
  v_text text;
begin
  -- Ignorar sistema / reservas / cards JSON
  if coalesce(new.is_reservation, false) then
    return new;
  end if;
  v_text := coalesce(new.text, '');
  if left(trim(v_text), 1) = '{' then
    return new; -- card JSON
  end if;
  if length(trim(v_text)) < 1 then
    return new;
  end if;

  v_other := public.batata_notify_chat_other_party(new.chat_id, new.sender_id);
  if v_other is null then
    return new;
  end if;

  perform public.batata_emit_user_notification_trusted(
    v_other,
    'chat_message',
    v_title,
    v_body,
    new.chat_id,
    null,
    null,
    new.sender_id,
    'chat_msg:' || new.id::text
  );
  return new;
exception
  when others then
    -- Nunca bloquear envio de mensagem
    return new;
end;
$$;

drop trigger if exists batata_chat_messages_notify_tg on public.chat_messages;
create trigger batata_chat_messages_notify_tg
  after insert on public.chat_messages
  for each row
  execute function public.batata_notify_on_chat_message();

-- ---------------------------------------------------------------------------
-- 6) Trigger: outcome de proposta → inbox para a outra parte
-- ---------------------------------------------------------------------------

create or replace function public.batata_notify_price_offer_outcome()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient uuid;
  v_title text;
  v_body text;
  v_product text;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;
  if old.status is not distinct from new.status then
    return new;
  end if;
  if new.status not in ('accepted', 'rejected', 'declined', 'expired') then
    return new;
  end if;

  -- Quem actua (responded) notifica a outra parte
  if new.status = 'accepted' then
    v_title := 'Proposta aceite';
  elsif new.status = 'expired' then
    v_title := 'Proposta expirada';
  else
    v_title := 'Proposta recusada';
  end if;

  select coalesce(nullif(trim(title), ''), 'Artigo') into v_product
  from public.products where id = new.product_id;

  v_body := to_char(new.amount, 'FM999999990.00') || ' € · ' || v_product;

  -- Destinatário = a outra parte relativamente a quem respondeu
  if new.offered_by = 'buyer' then
    -- seller aceita/recusa → avisar buyer; se buyer cancelasse raro
    if new.status = 'expired' then
      v_recipient := new.buyer_id; -- avisar quem ofereceu
    else
      v_recipient := case
        when auth.uid() = new.seller_id then new.buyer_id
        when auth.uid() = new.buyer_id then new.seller_id
        else new.buyer_id
      end;
    end if;
  else
    if new.status = 'expired' then
      v_recipient := new.seller_id;
    else
      v_recipient := case
        when auth.uid() = new.buyer_id then new.seller_id
        when auth.uid() = new.seller_id then new.buyer_id
        else new.seller_id
      end;
    end if;
  end if;

  if v_recipient is null then
    return new;
  end if;

  perform public.batata_emit_user_notification_trusted(
    v_recipient,
    'price_offer_outcome',
    v_title,
    v_body,
    new.chat_id,
    new.product_id,
    new.id,
    auth.uid(),
    'offer_outcome:' || new.id::text || ':' || new.status
  );
  return new;
exception
  when others then
    return new;
end;
$$;

drop trigger if exists batata_product_offers_outcome_notify_tg on public.product_offers;
create trigger batata_product_offers_outcome_notify_tg
  after update of status on public.product_offers
  for each row
  execute function public.batata_notify_price_offer_outcome();

-- Fim proposta ponto 7 schema. Deploy Edge notify-dispatch + secrets FCM/SMTP
-- e Database Webhook user_notifications INSERT → notify-dispatch (ver relatório).
