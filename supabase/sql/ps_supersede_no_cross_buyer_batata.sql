-- BATATA 2026-07-21 — supersede NÃO rouba reserva de outro comprador
--
-- Problema: «quero 1 REF AM1» (Lara) + depois «reservo 2 ref am1» (Marta)
--   → fallback «só 1 pending neste artigo» reescrevia a linha da Lara para Marta.
--   UI/BD: Lara ficava só com AM2; Marta «herdava» AM1.
--
-- Fix: fallback single-item só se NÃO houver nome fiável (OCR anónimo).
--   Com nome «Marta» → INSERT novo; Lara mantém AM1.
--
-- Aplicar na staging (SQL Editor) ANTES de re-correr SRW lote 1.
-- Também actualiza: supabase/sql/ps_identity_match_batata.sql (fonte).

create or replace function public.batata_ps_find_open_reservation(
  p_live_id uuid,
  p_live_item_id uuid,
  p_buyer_ref text,
  p_display_name text,
  p_allow_single_fallback boolean default true
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_cnt int;
  v_norm text := public.batata_ps_normalize_display_name(p_display_name);
  v_ref text := nullif(trim(coalesce(p_buyer_ref, '')), '');
begin
  if v_ref is not null then
    select r.id into v_id
    from public.live_reservation_requests r
    where r.live_id = p_live_id
      and (p_live_item_id is null or r.live_item_id = p_live_item_id)
      and r.external_buyer_ref = v_ref
      and r.status = 'pending'
    order by r.detected_at desc nulls last, r.created_at desc
    limit 1;
    if v_id is not null then
      return v_id;
    end if;
  end if;

  if v_norm is not null
     and length(v_norm) >= 4
     and v_norm not in (
       'facebook', 'cliente', 'comprador', 'teste', 'afinal', 'so', 'só',
       'ja', 'já', 'nao', 'não', 'quero', 'py', 'ocr', 'ref', 'saco'
     ) then
    select r.id into v_id
    from public.live_reservation_requests r
    where r.live_id = p_live_id
      and (p_live_item_id is null or r.live_item_id = p_live_item_id)
      and public.batata_ps_normalize_display_name(r.external_display_name) = v_norm
      and r.status = 'pending'
    order by r.detected_at desc nulls last, r.created_at desc
    limit 1;
    if v_id is not null then
      return v_id;
    end if;
  end if;

  if p_allow_single_fallback and p_live_item_id is not null then
    -- Só sem identidade fiável — nunca cross-buyer com nome distinto.
    if v_norm is null or length(v_norm) < 4 then
      select count(*)::int into v_cnt
      from public.live_reservation_requests r
      where r.live_id = p_live_id
        and r.live_item_id = p_live_item_id
        and r.source = 'facebook_manual'
        and r.status = 'pending'
        and r.created_at > now() - interval '45 minutes';

      if v_cnt = 1 then
        select r.id into v_id
        from public.live_reservation_requests r
        where r.live_id = p_live_id
          and r.live_item_id = p_live_item_id
          and r.source = 'facebook_manual'
          and r.status = 'pending'
          and r.created_at > now() - interval '45 minutes'
        order by r.detected_at desc nulls last, r.created_at desc
        limit 1;
        return v_id;
      end if;
    end if;
  end if;

  return null;
end;
$$;

revoke all on function public.batata_ps_find_open_reservation(uuid, uuid, text, text, boolean) from public;
grant execute on function public.batata_ps_find_open_reservation(uuid, uuid, text, text, boolean) to service_role;

-- Smoke (opcional): com 2 nomes distintos no mesmo item, find_open com nome B
-- não deve devolver a linha de A. Correr manualmente após seed de teste.
