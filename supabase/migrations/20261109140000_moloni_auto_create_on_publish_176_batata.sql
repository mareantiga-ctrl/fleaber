-- ZIP 176-C2 — criação automática Moloni ao publicar Fleaber (AMZ-*).
-- Escritas Moloni reais: só com MOLONI_AUTO_CREATE_MODE=live + GO (edge).
-- Esta migration: fila, fiscal prep, compras documentadas (stub), trigger enqueue.

-- Regime fiscal previsto (validação contabilista — sem faturação neste ZIP)
ALTER TABLE public.moloni_product_links
  ADD COLUMN IF NOT EXISTS fiscal_regime text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'moloni_product_links_fiscal_regime_chk'
  ) THEN
    ALTER TABLE public.moloni_product_links
      ADD CONSTRAINT moloni_product_links_fiscal_regime_chk
      CHECK (
        fiscal_regime IS NULL
        OR fiscal_regime IN (
          'pending_accountant',
          'normal_vat',
          'margin_second_hand'
        )
      );
  END IF;
END $$;

COMMENT ON COLUMN public.moloni_product_links.fiscal_regime IS
  'ZIP 176 — pending_accountant|normal_vat|margin_second_hand. Sem cálculo IVA margem neste ZIP.';

-- Fila de sync (retry sem perder anúncio Fleaber)
CREATE TABLE IF NOT EXISTS public.moloni_sync_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fleaber_product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  asin text,
  lpn text,
  fleaber_ref_code text,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN (
      'pending', 'processing', 'linked', 'simulated', 'failed', 'skipped'
    )),
  attempt_count integer NOT NULL DEFAULT 0,
  last_error text,
  planned_moloni_reference text,
  moloni_product_id text,
  moloni_reference text,
  result_action text,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  zip text DEFAULT '176-C2'
);

CREATE UNIQUE INDEX IF NOT EXISTS moloni_sync_jobs_one_open_per_product_uidx
  ON public.moloni_sync_jobs (fleaber_product_id)
  WHERE status IN ('pending', 'processing');

CREATE INDEX IF NOT EXISTS moloni_sync_jobs_status_idx
  ON public.moloni_sync_jobs (status, created_at);

ALTER TABLE public.moloni_sync_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS moloni_sync_jobs_deny_all ON public.moloni_sync_jobs;
CREATE POLICY moloni_sync_jobs_deny_all
  ON public.moloni_sync_jobs
  FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

-- Admin Amazon pode ler estados (sem escrever)
DROP POLICY IF EXISTS moloni_sync_jobs_admin_select ON public.moloni_sync_jobs;
CREATE POLICY moloni_sync_jobs_admin_select
  ON public.moloni_sync_jobs
  FOR SELECT TO authenticated
  USING (public.batata_is_amazon_importer_admin());

REVOKE INSERT, UPDATE, DELETE ON public.moloni_sync_jobs FROM anon, authenticated;
GRANT SELECT ON public.moloni_sync_jobs TO authenticated;
GRANT ALL ON public.moloni_sync_jobs TO service_role;

-- Stub fase posterior: declarações documentadas de compras a particulares
CREATE TABLE IF NOT EXISTS public.moloni_purchase_declarations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fleaber_product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  moloni_product_id text,
  moloni_reference text,
  qty numeric(12,3) NOT NULL CHECK (qty > 0),
  unit_cost_eur numeric(12,4),
  seller_private_party_note text,
  document_status text NOT NULL DEFAULT 'planned'
    CHECK (document_status IN ('planned', 'draft', 'posted', 'cancelled')),
  moloni_document_id text,
  declared_at timestamptz,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  zip text DEFAULT '176-C2'
);

ALTER TABLE public.moloni_purchase_declarations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS moloni_purchase_declarations_deny_all
  ON public.moloni_purchase_declarations;
CREATE POLICY moloni_purchase_declarations_deny_all
  ON public.moloni_purchase_declarations
  FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

REVOKE ALL ON public.moloni_purchase_declarations FROM anon, authenticated;
GRANT ALL ON public.moloni_purchase_declarations TO service_role;

COMMENT ON TABLE public.moloni_purchase_declarations IS
  'ZIP 176 stub — stock via compras documentadas a particulares (fase futura; sem docs agora).';

-- Peek próximo código sem avançar (simulação / UI)
CREATE OR REPLACE FUNCTION public.peek_moloni_next_references(p_count integer DEFAULT 1)
RETURNS TABLE (reference text, seq_n bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefix text;
  v_width integer;
  v_start bigint;
  v_i integer;
BEGIN
  IF p_count IS NULL OR p_count < 1 OR p_count > 100 THEN
    RAISE EXCEPTION 'invalid_count';
  END IF;
  SELECT s.prefix, s.width, s.next_n
    INTO v_prefix, v_width, v_start
  FROM public.moloni_reference_seq s WHERE s.id = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'seq_missing';
  END IF;
  FOR v_i IN 0..(p_count - 1) LOOP
    reference := upper(v_prefix) || lpad((v_start + v_i)::text, v_width, '0');
    seq_n := v_start + v_i;
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.peek_moloni_next_references(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.peek_moloni_next_references(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.peek_moloni_next_references(integer) TO authenticated;

-- Enqueue idempotente
CREATE OR REPLACE FUNCTION public.batata_moloni_enqueue_fleaber_product(p_product_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ref text;
  v_asin text;
  v_lpn text;
  v_job_id uuid;
  v_existing_link text;
  v_open uuid;
BEGIN
  SELECT p.ref_code INTO v_ref
  FROM public.products p WHERE p.id = p_product_id;
  IF v_ref IS NULL OR v_ref NOT LIKE 'AMZ-%' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_amazon_import_product');
  END IF;

  v_asin := upper(replace(v_ref, 'AMZ-', ''));

  SELECT l.moloni_product_id INTO v_existing_link
  FROM public.moloni_product_links l
  WHERE l.fleaber_product_id = p_product_id
    AND l.link_status = 'linked'
  LIMIT 1;
  IF v_existing_link IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'already_linked',
      'moloni_product_id', v_existing_link
    );
  END IF;

  SELECT j.id INTO v_open
  FROM public.moloni_sync_jobs j
  WHERE j.fleaber_product_id = p_product_id
    AND j.status IN ('pending', 'processing')
  LIMIT 1;
  IF v_open IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true, 'reason', 'job_open', 'job_id', v_open);
  END IF;

  SELECT u.lpn INTO v_lpn
  FROM public.amazon_catalog_units u
  WHERE u.asin = v_asin
  ORDER BY u.created_at NULLS LAST
  LIMIT 1;

  INSERT INTO public.moloni_sync_jobs (
    fleaber_product_id, asin, lpn, fleaber_ref_code, status, zip, meta
  ) VALUES (
    p_product_id, v_asin, v_lpn, v_ref, 'pending', '176-C2',
    jsonb_build_object('source', 'enqueue_rpc')
  )
  RETURNING id INTO v_job_id;

  RETURN jsonb_build_object('ok', true, 'job_id', v_job_id, 'asin', v_asin);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true, 'reason', 'job_open_race');
END;
$$;

REVOKE ALL ON FUNCTION public.batata_moloni_enqueue_fleaber_product(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.batata_moloni_enqueue_fleaber_product(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.batata_moloni_enqueue_fleaber_product(uuid)
  TO authenticated;

-- Trigger: ao publicar no marketplace um AMZ-* → enqueue (nunca chama Moloni)
CREATE OR REPLACE FUNCTION public.batata_moloni_on_fleaber_publish()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  becoming_published boolean;
BEGIN
  IF NEW.ref_code IS NULL OR NEW.ref_code NOT LIKE 'AMZ-%' THEN
    RETURN NEW;
  END IF;

  becoming_published :=
    (NEW.list_on_marketplace IS TRUE AND coalesce(NEW.is_draft, false) IS FALSE)
    AND (
      TG_OP = 'INSERT'
      OR OLD.list_on_marketplace IS DISTINCT FROM NEW.list_on_marketplace
      OR OLD.is_draft IS DISTINCT FROM NEW.is_draft
      OR OLD.ref_code IS DISTINCT FROM NEW.ref_code
    );

  IF becoming_published THEN
    PERFORM public.batata_moloni_enqueue_fleaber_product(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_moloni_on_fleaber_publish ON public.products;
CREATE TRIGGER trg_moloni_on_fleaber_publish
  AFTER INSERT OR UPDATE OF list_on_marketplace, is_draft, ref_code
  ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.batata_moloni_on_fleaber_publish();

COMMENT ON TABLE public.moloni_sync_jobs IS
  'ZIP 176 — fila sync Moloni pós-publish Fleaber. Retry seguro; edge processa em simulate|live.';
