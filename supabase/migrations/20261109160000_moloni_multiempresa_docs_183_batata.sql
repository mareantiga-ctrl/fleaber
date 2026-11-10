-- ZIP 183 — Moloni multiempresa + fila de documentos (SIMULAÇÃO / preparação).
-- NÃO emite faturas reais. Regime IVA = pending_accountant.

CREATE TABLE IF NOT EXISTS public.moloni_companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  company_key text NOT NULL UNIQUE,
  display_name text NOT NULL,
  seller_id uuid REFERENCES auth.users(id),
  moloni_company_id bigint,
  nif text,
  is_active boolean NOT NULL DEFAULT true,
  oauth_configured boolean NOT NULL DEFAULT false,
  fiscal_regime text NOT NULL DEFAULT 'pending_accountant'
    CHECK (fiscal_regime IN (
      'pending_accountant',
      'normal_iva',
      'margin_scheme',
      'exempt',
      'mixed'
    )),
  notes text,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE public.moloni_companies IS
  'ZIP183: credenciais/empresa Moloni por seller. Sem faturação real neste ZIP.';

INSERT INTO public.moloni_companies (company_key, display_name, seller_id, moloni_company_id, nif, oauth_configured, notes)
VALUES
  (
    'mare_antiga',
    'Mare Antiga',
    '08c9dca8-3707-4ee5-9f43-b33293085d6a',
    354250,
    '518775364',
    true,
    'Empresa actual — GO faturação real separado'
  ),
  (
    'nova_empresa',
    'Nova empresa (placeholder)',
    NULL,
    NULL,
    NULL,
    false,
    'Configurar quando existir conta Moloni + GO'
  )
ON CONFLICT (company_key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.moloni_document_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  company_key text NOT NULL REFERENCES public.moloni_companies(company_key),
  doc_type text NOT NULL
    CHECK (doc_type IN ('invoice', 'credit_note', 'credit_note_partial')),
  status text NOT NULL DEFAULT 'simulated'
    CHECK (status IN (
      'queued', 'simulated', 'failed', 'cancelled', 'emitted_real_blocked'
    )),
  mode text NOT NULL DEFAULT 'simulate'
    CHECK (mode IN ('simulate', 'live_blocked')),
  order_id uuid,
  payment_id text,
  idempotency_key text NOT NULL,
  buyer_user_id uuid,
  currency text NOT NULL DEFAULT 'EUR',
  lines jsonb NOT NULL DEFAULT '[]'::jsonb,
  shipping_eur numeric(12,2) NOT NULL DEFAULT 0,
  protection_fee_eur numeric(12,2) NOT NULL DEFAULT 0,
  protection_treatment text NOT NULL DEFAULT 'platform_own_document'
    CHECK (protection_treatment IN (
      'platform_own_document',
      'not_on_seller_invoice',
      'pending_accountant'
    )),
  total_eur numeric(12,2),
  related_invoice_job_id uuid REFERENCES public.moloni_document_jobs(id),
  error_text text,
  retry_count int NOT NULL DEFAULT 0,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (company_key, idempotency_key)
);

CREATE INDEX IF NOT EXISTS moloni_document_jobs_order_idx
  ON public.moloni_document_jobs (order_id);
CREATE INDEX IF NOT EXISTS moloni_document_jobs_status_idx
  ON public.moloni_document_jobs (status, created_at DESC);

COMMENT ON TABLE public.moloni_document_jobs IS
  'ZIP183: fila fatura/NC. Proteção Fleaber NÃO vai na fatura do vendedor. Emitir real = GO.';

COMMENT ON COLUMN public.moloni_document_jobs.protection_treatment IS
  'Taxa Proteção Fleaber: documento próprio da plataforma — validar com contabilista.';

ALTER TABLE public.moloni_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.moloni_document_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS moloni_companies_admin ON public.moloni_companies;
CREATE POLICY moloni_companies_admin ON public.moloni_companies
  FOR ALL TO authenticated
  USING (public.batata_is_amazon_importer_admin())
  WITH CHECK (public.batata_is_amazon_importer_admin());

DROP POLICY IF EXISTS moloni_document_jobs_admin ON public.moloni_document_jobs;
CREATE POLICY moloni_document_jobs_admin ON public.moloni_document_jobs
  FOR ALL TO authenticated
  USING (public.batata_is_amazon_importer_admin())
  WITH CHECK (public.batata_is_amazon_importer_admin());

GRANT SELECT, INSERT, UPDATE ON public.moloni_companies TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.moloni_document_jobs TO authenticated;
GRANT ALL ON public.moloni_companies TO service_role;
GRANT ALL ON public.moloni_document_jobs TO service_role;

-- RPC simulação idempotente (sem HTTP Moloni).
CREATE OR REPLACE FUNCTION public.batata_moloni_simulate_document(
  p_company_key text,
  p_doc_type text,
  p_idempotency_key text,
  p_order_id uuid DEFAULT NULL,
  p_payment_id text DEFAULT NULL,
  p_lines jsonb DEFAULT '[]'::jsonb,
  p_shipping_eur numeric DEFAULT 0,
  p_protection_fee_eur numeric DEFAULT 0,
  p_related_invoice_job_id uuid DEFAULT NULL,
  p_buyer_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.moloni_document_jobs%ROWTYPE;
  v_id uuid;
  v_total numeric(12,2);
BEGIN
  IF auth.uid() IS NOT NULL
     AND NOT public.batata_is_amazon_importer_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF p_company_key IS NULL OR btrim(p_company_key) = '' THEN
    RAISE EXCEPTION 'company_key_required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.moloni_companies c
    WHERE c.company_key = p_company_key AND c.is_active
  ) THEN
    RAISE EXCEPTION 'unknown_or_inactive_company';
  END IF;

  SELECT * INTO v_existing
  FROM public.moloni_document_jobs
  WHERE company_key = p_company_key
    AND idempotency_key = p_idempotency_key;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'deduped', true,
      'job_id', v_existing.id,
      'status', v_existing.status,
      'mode', v_existing.mode,
      'company_key', v_existing.company_key,
      'doc_type', v_existing.doc_type
    );
  END IF;

  -- Total vendedor = linhas + portes; Proteção Fleaber fora da fatura seller.
  v_total := COALESCE(p_shipping_eur, 0) + COALESCE((
    SELECT COALESCE(SUM((x->>'qty')::numeric * (x->>'unit_price')::numeric), 0)
    FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) AS x
  ), 0);

  INSERT INTO public.moloni_document_jobs (
    company_key, doc_type, status, mode, order_id, payment_id,
    idempotency_key, buyer_user_id, lines, shipping_eur,
    protection_fee_eur, protection_treatment, total_eur,
    related_invoice_job_id, meta
  ) VALUES (
    p_company_key,
    p_doc_type,
    'simulated',
    'simulate',
    p_order_id,
    p_payment_id,
    p_idempotency_key,
    p_buyer_user_id,
    COALESCE(p_lines, '[]'::jsonb),
    COALESCE(p_shipping_eur, 0),
    COALESCE(p_protection_fee_eur, 0),
    'platform_own_document',
    v_total,
    p_related_invoice_job_id,
    jsonb_build_object(
      'zip', '183-C2',
      'real_emit_blocked', true,
      'iva_regime', 'pending_accountant'
    )
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'ok', true,
    'deduped', false,
    'job_id', v_id,
    'status', 'simulated',
    'mode', 'simulate',
    'company_key', p_company_key,
    'doc_type', p_doc_type,
    'total_eur', v_total,
    'protection_fee_excluded_from_seller_invoice', true,
    'real_emit', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.batata_moloni_simulate_document(
  text, text, text, uuid, text, jsonb, numeric, numeric, uuid, uuid
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.batata_moloni_simulate_document(
  text, text, text, uuid, text, jsonb, numeric, numeric, uuid, uuid
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.batata_moloni_simulate_document(
  text, text, text, uuid, text, jsonb, numeric, numeric, uuid, uuid
) TO service_role;
