-- =============================================================================
-- ZIP 166.1-C2 — Gate de aprovação no backend (não só na UI)
-- Impede catalog_status=approved / approved_at se faltarem dados obrigatórios.
-- =============================================================================

-- Cálculo canónico dos motivos (mesma regra da view / refresh)
create or replace function public.batata_amazon_compute_missing_reasons(
  p_approved_sale_eur numeric,
  p_suggested_sale_eur numeric,
  p_title text,
  p_description text,
  p_primary_image_url text,
  p_shipping_weight_kg numeric,
  p_manifest_weight_kg numeric
)
returns text[]
language plpgsql
immutable
as $$
declare
  reasons text[] := '{}';
begin
  if coalesce(p_approved_sale_eur, p_suggested_sale_eur) is null then
    reasons := array_append(reasons, 'missing_price');
  end if;
  if coalesce(nullif(trim(p_title), ''), null) is null then
    reasons := array_append(reasons, 'missing_title');
  end if;
  if coalesce(nullif(trim(p_description), ''), null) is null then
    reasons := array_append(reasons, 'missing_description');
  end if;
  if coalesce(nullif(trim(p_primary_image_url), ''), null) is null then
    reasons := array_append(reasons, 'missing_photo');
  end if;
  if p_shipping_weight_kg is null and p_manifest_weight_kg is null then
    reasons := array_append(reasons, 'missing_weight');
  end if;
  return reasons;
end;
$$;

create or replace function public.batata_amazon_refresh_missing_reasons(p_product_id uuid)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.amazon_catalog_products%rowtype;
  reasons text[];
begin
  if not public.batata_is_amazon_importer_admin() then
    raise exception 'not authorized';
  end if;
  select * into r from public.amazon_catalog_products where id = p_product_id;
  if not found then
    raise exception 'product not found';
  end if;
  reasons := public.batata_amazon_compute_missing_reasons(
    r.approved_sale_eur,
    r.suggested_sale_eur,
    r.title,
    r.description,
    r.primary_image_url,
    r.shipping_weight_kg,
    r.manifest_weight_kg
  );
  update public.amazon_catalog_products
    set missing_reasons = reasons,
        updated_at = timezone('utc', now())
    where id = p_product_id;
  return reasons;
end;
$$;

-- Trigger: bloquear aprovação inválida (incl. PATCH directo / scripts)
create or replace function public.batata_amazon_enforce_approve_gate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  reasons text[];
  becoming_approved boolean;
begin
  becoming_approved :=
    (NEW.catalog_status = 'approved' and coalesce(OLD.catalog_status, '') is distinct from 'approved')
    or (NEW.approved_at is not null and OLD.approved_at is null);

  if not becoming_approved then
    -- Sempre sincronizar missing_reasons com os campos reais
    NEW.missing_reasons := public.batata_amazon_compute_missing_reasons(
      NEW.approved_sale_eur,
      NEW.suggested_sale_eur,
      NEW.title,
      NEW.description,
      NEW.primary_image_url,
      NEW.shipping_weight_kg,
      NEW.manifest_weight_kg
    );
    return NEW;
  end if;

  reasons := public.batata_amazon_compute_missing_reasons(
    NEW.approved_sale_eur,
    NEW.suggested_sale_eur,
    NEW.title,
    NEW.description,
    NEW.primary_image_url,
    NEW.shipping_weight_kg,
    NEW.manifest_weight_kg
  );
  NEW.missing_reasons := reasons;

  if coalesce(array_length(reasons, 1), 0) > 0 then
    raise exception 'amazon_approve_blocked: %', array_to_string(reasons, ', ')
      using errcode = 'check_violation';
  end if;

  if NEW.approved_at is null then
    NEW.approved_at := timezone('utc', now());
  end if;
  NEW.catalog_status := 'approved';
  return NEW;
end;
$$;

drop trigger if exists trg_amazon_enforce_approve_gate on public.amazon_catalog_products;
create trigger trg_amazon_enforce_approve_gate
  before update on public.amazon_catalog_products
  for each row
  execute function public.batata_amazon_enforce_approve_gate();

-- RPC única de aprovação (massa / individual) — devolve JSON
-- Idempotente: já aprovados não geram novo evento nem duplicam estado.
create or replace function public.batata_amazon_approve_products(
  p_product_ids uuid[],
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid;
  reasons text[];
  approved_ids uuid[] := '{}';
  skipped_ids uuid[] := '{}';
  rejected jsonb := '[]'::jsonb;
  before_state jsonb;
  row_status text;
  row_approved_at timestamptz;
  n_ok int := 0;
  n_block int := 0;
  n_skip int := 0;
begin
  if not public.batata_is_amazon_importer_admin() then
    raise exception 'not authorized';
  end if;
  if p_product_ids is null or array_length(p_product_ids, 1) is null then
    return jsonb_build_object(
      'approved', 0,
      'blocked', 0,
      'skipped_already_approved', 0,
      'approved_ids', '[]'::jsonb,
      'skipped_ids', '[]'::jsonb,
      'rejected', '[]'::jsonb,
      'published', false
    );
  end if;

  foreach pid in array p_product_ids loop
    select catalog_status, approved_at
      into row_status, row_approved_at
    from public.amazon_catalog_products
    where id = pid;

    if not found then
      n_block := n_block + 1;
      rejected := rejected || jsonb_build_array(
        jsonb_build_object(
          'product_id', pid,
          'reasons', jsonb_build_array('not_found')
        )
      );
      continue;
    end if;

    -- Já aprovado (ou draft Fleaber pós-aprovação): sem duplicar eventos
    if row_approved_at is not null
       or row_status in ('approved', 'draft_fleaber', 'published') then
      skipped_ids := array_append(skipped_ids, pid);
      n_skip := n_skip + 1;
      continue;
    end if;

    reasons := public.batata_amazon_refresh_missing_reasons(pid);
    if coalesce(array_length(reasons, 1), 0) > 0 then
      n_block := n_block + 1;
      rejected := rejected || jsonb_build_array(
        jsonb_build_object(
          'product_id', pid,
          'asin', (select asin from public.amazon_catalog_products where id = pid),
          'reasons', to_jsonb(reasons)
        )
      );
      continue;
    end if;

    select to_jsonb(p) into before_state
    from public.amazon_catalog_products p where p.id = pid;

    update public.amazon_catalog_products
      set catalog_status = 'approved',
          approved_at = timezone('utc', now()),
          approved_by = auth.uid(),
          last_approved_note = p_note,
          updated_at = timezone('utc', now())
      where id = pid;

    insert into public.amazon_approval_events (
      actor_id, product_id, action, before_state, after_state, note
    ) values (
      auth.uid(),
      pid,
      'bulk_approve',
      coalesce(before_state, '{}'::jsonb),
      jsonb_build_object('catalog_status', 'approved', 'note', p_note),
      p_note
    );

    approved_ids := array_append(approved_ids, pid);
    n_ok := n_ok + 1;
  end loop;

  return jsonb_build_object(
    'approved', n_ok,
    'blocked', n_block,
    'skipped_already_approved', n_skip,
    'approved_ids', to_jsonb(approved_ids),
    'skipped_ids', to_jsonb(skipped_ids),
    'rejected', rejected,
    'published', false
  );
end;
$$;

revoke all on function public.batata_amazon_approve_products(uuid[], text) from public;
grant execute on function public.batata_amazon_approve_products(uuid[], text)
  to authenticated, service_role;

revoke all on function public.batata_amazon_refresh_missing_reasons(uuid) from public;
grant execute on function public.batata_amazon_refresh_missing_reasons(uuid)
  to authenticated, service_role;

revoke all on function public.batata_amazon_compute_missing_reasons(
  numeric, numeric, text, text, text, numeric, numeric
) from public;
grant execute on function public.batata_amazon_compute_missing_reasons(
  numeric, numeric, text, text, text, numeric, numeric
) to authenticated, service_role;
