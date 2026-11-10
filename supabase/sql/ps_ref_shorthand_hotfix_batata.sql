-- Hotfix: resolver Q1 → REF Q1, A15 → REF A15 (shorthand vs ref_code Fleaber)

create or replace function public.batata_ref_norm_core(p_raw text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    public.batata_normalize_ref(p_raw),
    '^REF',
    ''
  );
$$;

create or replace function public.batata_resolve_live_item_ref_v2(
  p_live_id uuid,
  p_ref_slug text default null,
  p_public_slot int default null,
  p_ref_number int default null,
  p_title_hint text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_norm text;
  v_item_id uuid;
  v_title_norm text;
  v_count int;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_id');
  end if;

  if nullif(trim(coalesce(p_ref_slug, '')), '') is not null then
    v_norm := public.batata_normalize_ref(p_ref_slug);

    if v_norm <> '' then
      -- 1a) Normalizado exacto
      select li.id into v_item_id
      from public.live_items li
      where li.live_id = p_live_id
        and public.batata_normalize_ref(li.ref_code) = v_norm
        and coalesce(li.status, '') <> 'sold'
      order by li.is_active desc, li.created_at asc
      limit 1;

      if v_item_id is not null then
        return jsonb_build_object(
          'ok', true, 'live_item_id', v_item_id,
          'match_type', 'ref_exact', 'confidence', 0.98,
          'resolved_ref_slug', v_norm
        );
      end if;

      -- 1b) Shorthand Q1 → REF Q1 (core sem prefixo REF)
      select count(*)::int, min(li.id)
      into v_count, v_item_id
      from public.live_items li
      where li.live_id = p_live_id
        and coalesce(li.status, '') <> 'sold'
        and public.batata_ref_norm_core(li.ref_code) = v_norm;

      if v_count = 1 and v_item_id is not null then
        return jsonb_build_object(
          'ok', true, 'live_item_id', v_item_id,
          'match_type', 'ref_shorthand', 'confidence', 0.94,
          'resolved_ref_slug', v_norm
        );
      end if;

      if v_count > 1 then
        return jsonb_build_object(
          'ok', false, 'error', 'ambiguous_ref_shorthand',
          'match_count', v_count
        );
      end if;

      -- 1c) Display exact (#Q1, REF Q1)
      select li.id into v_item_id
      from public.live_items li
      where li.live_id = p_live_id
        and lower(trim(coalesce(li.ref_code, ''))) = lower(trim(p_ref_slug))
        and coalesce(li.status, '') <> 'sold'
      order by li.is_active desc, li.created_at asc
      limit 1;

      if v_item_id is not null then
        return jsonb_build_object(
          'ok', true, 'live_item_id', v_item_id,
          'match_type', 'ref_display', 'confidence', 0.96,
          'resolved_ref_slug', v_norm
        );
      end if;

      -- 1d) Display contém token (único)
      select count(*)::int, min(li.id)
      into v_count, v_item_id
      from public.live_items li
      where li.live_id = p_live_id
        and coalesce(li.status, '') <> 'sold'
        and lower(trim(coalesce(li.ref_code, ''))) like '%' || lower(trim(p_ref_slug)) || '%';

      if v_count = 1 and v_item_id is not null then
        return jsonb_build_object(
          'ok', true, 'live_item_id', v_item_id,
          'match_type', 'ref_contains', 'confidence', 0.82,
          'resolved_ref_slug', v_norm
        );
      end if;

      if v_count > 1 then
        return jsonb_build_object(
          'ok', false, 'error', 'ambiguous_ref_contains',
          'match_count', v_count
        );
      end if;
    end if;
  end if;

  -- 2) Slot público / ordinal
  if coalesce(p_public_slot, p_ref_number) is not null
     and coalesce(p_public_slot, p_ref_number) >= 1 then
    select li.id into v_item_id
    from public.live_items li
    where li.live_id = p_live_id
      and li.public_slot = coalesce(p_public_slot, p_ref_number)
      and coalesce(li.status, '') <> 'sold'
    order by li.is_active desc, li.created_at asc
    limit 1;

    if v_item_id is not null then
      return jsonb_build_object(
        'ok', true, 'live_item_id', v_item_id,
        'match_type', 'public_slot', 'confidence', 0.94,
        'resolved_ref_slug', coalesce(p_public_slot, p_ref_number)::text
      );
    end if;

    select x.id into v_item_id
    from (
      select li.id, row_number() over (order by li.created_at asc)::int as ord
      from public.live_items li
      where li.live_id = p_live_id and coalesce(li.status, '') <> 'sold'
    ) x
    where x.ord = coalesce(p_public_slot, p_ref_number)
    limit 1;

    if v_item_id is not null then
      return jsonb_build_object(
        'ok', true, 'live_item_id', v_item_id,
        'match_type', 'catalog_ordinal', 'confidence', 0.88,
        'resolved_ref_slug', coalesce(p_public_slot, p_ref_number)::text
      );
    end if;
  end if;

  -- 3) Título único
  if nullif(trim(coalesce(p_title_hint, '')), '') is not null then
    v_title_norm := lower(regexp_replace(trim(p_title_hint), '\s+', ' ', 'g'));
    select count(*)::int, min(li.id)
    into v_count, v_item_id
    from public.live_items li
    where li.live_id = p_live_id
      and coalesce(li.status, '') <> 'sold'
      and lower(trim(coalesce(li.title, ''))) like '%' || v_title_norm || '%';

    if v_count = 1 and v_item_id is not null then
      return jsonb_build_object(
        'ok', true, 'live_item_id', v_item_id,
        'match_type', 'title_unique', 'confidence', 0.75,
        'resolved_ref_slug', v_title_norm
      );
    end if;
    if v_count > 1 then
      return jsonb_build_object(
        'ok', false, 'error', 'ambiguous_title', 'match_count', v_count
      );
    end if;
  end if;

  return jsonb_build_object('ok', false, 'error', 'item_not_found');
end;
$$;

notify pgrst, 'reload schema';
