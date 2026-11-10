-- =============================================================================
-- BATATA 2026-09-13 — chat Hub vê «reservou»/cancel FB sem abrir OCR facebook
-- =============================================================================
-- Causa: announce/cancel FB usavam channel=facebook; RLS live_messages_select_scoped
--        só deixa compradores autenticados ler fleaber/hub (OCR FB fica seller-only).
-- Fix: anúncios sociais de sistema (reservou / cancelou) → channel=fleaber.
--      Comentários OCR espelhados continuam channel=facebook (hardening intacto).

create or replace function public.batata_live_announce_pending_reservation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_label text;
  v_body text;
  v_channel text := 'fleaber';
  v_user uuid;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;
  if lower(trim(coalesce(new.status, ''))) is distinct from 'pending' then
    return new;
  end if;
  if lower(trim(coalesce(new.ingest_status, ''))) = 'rejected' then
    return new;
  end if;
  if new.live_id is null or new.live_item_id is null then
    return new;
  end if;

  if new.buyer_id is not null then
    select coalesce(nullif(trim(full_name), ''), nullif(trim(handle), ''), 'Comprador')
    into v_name
    from public.profiles
    where id = new.buyer_id;
  end if;
  if v_name is null or trim(v_name) = '' then
    v_name := coalesce(nullif(trim(new.external_display_name), ''), 'Comprador');
  end if;

  v_label := public.batata_live_item_chat_label(new.live_item_id);
  v_body := '🛍️ ' || v_name || ' reservou ' || v_label;

  -- Sempre fleaber: mensagem social pública (Hub + app). Não usar facebook
  -- (esse canal é só OCR/comentários crus — seller/staff via RLS).
  v_channel := 'fleaber';
  v_user := coalesce(new.buyer_id, new.seller_id);

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = new.live_id
      and m.body = v_body
      and m.created_at > now() - interval '45 seconds'
  ) then
    return new;
  end if;

  begin
    insert into public.live_messages (
      live_id, user_id, kind, body, sender_label, channel
    ) values (
      new.live_id, v_user, 'system', v_body, 'Sistema', v_channel
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

comment on function public.batata_live_announce_pending_reservation() is
  'Pending → chat social «reservou» em channel=fleaber (visível Hub/app). OCR FB continua channel=facebook.';

notify pgrst, 'reload schema';
