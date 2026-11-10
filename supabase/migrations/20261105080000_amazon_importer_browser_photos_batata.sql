-- ZIP 158: origem fotografias via navegador assistido (Playwright)
-- Direitos de publicação continuam pendentes (uso interno de stock).

alter table public.amazon_product_photos
  drop constraint if exists amazon_product_photos_source_check;

alter table public.amazon_product_photos
  add constraint amazon_product_photos_source_check
  check (source in (
    'upload',
    'camera',
    'amazon_ref_pending_rights',
    'amazon_cdn_pending_rights',
    'amazon_dp_html',
    'amazon_browser_pending_rights'
  ));

create or replace function public.batata_amazon_photos_write(
  p_asin text,
  p_photos jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_asin text := upper(trim(p_asin));
  v_primary text;
  v_photo jsonb;
  v_sort int := 0;
  v_source text;
begin
  if v_asin is null or v_asin !~ '^[A-Z0-9]{10}$' then
    raise exception 'invalid_asin';
  end if;

  if auth.uid() is not null
     and not public.batata_is_amazon_importer_admin() then
    raise exception 'forbidden';
  end if;

  select id into v_id
  from public.amazon_catalog_products
  where asin = v_asin;

  if v_id is null then
    insert into public.amazon_catalog_products as p (
      asin, photo_rights_status, catalog_status, updated_at, prep_notes
    ) values (
      v_asin,
      'internal_ref',
      'needs_review',
      timezone('utc', now()),
      'ZIP158 photos-only via batata_amazon_photos_write'
    )
    returning id into v_id;
  end if;

  select nullif(trim(p_photos->0->>'url'), '') into v_primary;

  -- Nunca apaga uploads próprios / câmara.
  delete from public.amazon_product_photos
  where product_id = v_id
    and source in (
      'amazon_cdn_pending_rights',
      'amazon_ref_pending_rights',
      'amazon_dp_html',
      'amazon_browser_pending_rights'
    );

  if p_photos is not null and jsonb_typeof(p_photos) = 'array' then
    for v_photo in select * from jsonb_array_elements(p_photos)
    loop
      if coalesce(v_photo->>'url', '') !~ '^https://' then
        continue;
      end if;
      v_source := coalesce(nullif(v_photo->>'source', ''), 'amazon_browser_pending_rights');
      if v_source not in (
        'upload', 'camera', 'amazon_ref_pending_rights',
        'amazon_cdn_pending_rights', 'amazon_dp_html',
        'amazon_browser_pending_rights'
      ) then
        v_source := 'amazon_browser_pending_rights';
      end if;
      insert into public.amazon_product_photos (
        product_id, storage_path, public_url, sort_order, is_primary, source
      ) values (
        v_id,
        v_photo->>'url',
        v_photo->>'url',
        v_sort,
        v_sort = 0,
        v_source
      );
      v_sort := v_sort + 1;
      exit when v_sort >= 8;
    end loop;
  end if;

  update public.amazon_catalog_products
  set primary_image_url = coalesce(v_primary, primary_image_url),
      photo_rights_status = case when v_primary is null then photo_rights_status else 'internal_ref' end,
      updated_at = timezone('utc', now()),
      prep_notes = coalesce(prep_notes, '') || ' | ZIP158 photos'
  where id = v_id;

  return v_id;
end;
$$;

revoke all on function public.batata_amazon_photos_write(text, jsonb) from public;
grant execute on function public.batata_amazon_photos_write(text, jsonb) to authenticated;
grant execute on function public.batata_amazon_photos_write(text, jsonb) to service_role;

-- Actualizar enrich_write para aceitar a nova origem (sem alterar LLM).
create or replace function public.batata_amazon_enrich_write(
  p_asin text,
  p_title text,
  p_description text,
  p_title_original text,
  p_llm_model text,
  p_copy_status text,
  p_suggested_sale_eur numeric,
  p_photos jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_asin text := upper(trim(p_asin));
  v_primary text;
  v_photo jsonb;
  v_sort int := 0;
  v_source text;
begin
  if v_asin is null or v_asin !~ '^[A-Z0-9]{10}$' then
    raise exception 'invalid_asin';
  end if;

  if auth.uid() is not null
     and not public.batata_is_amazon_importer_admin() then
    raise exception 'forbidden';
  end if;

  select nullif(trim(p_photos->0->>'url'), '') into v_primary;

  insert into public.amazon_catalog_products as p (
    asin, title, description, title_original, llm_model, llm_generated_at,
    copy_status, suggested_sale_eur, discount_pct, primary_image_url,
    photo_rights_status, catalog_status, updated_at, prep_notes
  ) values (
    v_asin,
    nullif(left(coalesce(p_title, ''), 200), ''),
    nullif(left(coalesce(p_description, ''), 4000), ''),
    nullif(left(coalesce(p_title_original, ''), 500), ''),
    nullif(left(coalesce(p_llm_model, ''), 80), ''),
    case when p_llm_model is null or btrim(p_llm_model) = '' then null else timezone('utc', now()) end,
    nullif(left(coalesce(p_copy_status, ''), 40), ''),
    p_suggested_sale_eur,
    50,
    v_primary,
    case when v_primary is null then 'missing' else 'internal_ref' end,
    case when p_copy_status = 'pass' then 'prepared' else 'needs_review' end,
    timezone('utc', now()),
    'ZIP158 enrich via batata_amazon_enrich_write'
  )
  on conflict (asin) do update set
    title = excluded.title,
    description = excluded.description,
    title_original = coalesce(p.title_original, excluded.title_original),
    llm_model = excluded.llm_model,
    llm_generated_at = excluded.llm_generated_at,
    copy_status = excluded.copy_status,
    suggested_sale_eur = coalesce(excluded.suggested_sale_eur, p.suggested_sale_eur),
    primary_image_url = coalesce(excluded.primary_image_url, p.primary_image_url),
    photo_rights_status = excluded.photo_rights_status,
    catalog_status = excluded.catalog_status,
    updated_at = timezone('utc', now()),
    prep_notes = excluded.prep_notes
  returning id into v_id;

  delete from public.amazon_product_photos
  where product_id = v_id
    and source in (
      'amazon_cdn_pending_rights',
      'amazon_ref_pending_rights',
      'amazon_dp_html',
      'amazon_browser_pending_rights'
    );

  if p_photos is not null and jsonb_typeof(p_photos) = 'array' then
    for v_photo in select * from jsonb_array_elements(p_photos)
    loop
      if coalesce(v_photo->>'url', '') !~ '^https://' then
        continue;
      end if;
      v_source := coalesce(nullif(v_photo->>'source', ''), 'amazon_dp_html');
      if v_source not in (
        'upload', 'camera', 'amazon_ref_pending_rights',
        'amazon_cdn_pending_rights', 'amazon_dp_html',
        'amazon_browser_pending_rights'
      ) then
        v_source := 'amazon_dp_html';
      end if;
      insert into public.amazon_product_photos (
        product_id, storage_path, public_url, sort_order, is_primary, source
      ) values (
        v_id,
        v_photo->>'url',
        v_photo->>'url',
        v_sort,
        v_sort = 0,
        v_source
      );
      v_sort := v_sort + 1;
      exit when v_sort >= 8;
    end loop;
  end if;

  return v_id;
end;
$$;
