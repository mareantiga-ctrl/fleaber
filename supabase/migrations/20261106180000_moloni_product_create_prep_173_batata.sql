-- ZIP 173-C2 — prep criação artigos Moloni (sem writes Moloni nesta fase)
-- Extende mapa Fleaber↔Moloni + sequência de códigos F#####.

-- Sequência de referências (aprovação humana pendente; default F10001)
CREATE TABLE IF NOT EXISTS public.moloni_reference_seq (
  id smallint PRIMARY KEY CHECK (id = 1),
  prefix text NOT NULL DEFAULT 'F',
  width integer NOT NULL DEFAULT 5 CHECK (width BETWEEN 3 AND 8),
  next_n bigint NOT NULL DEFAULT 10001,
  approved_at timestamptz,
  approved_by text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  zip text DEFAULT '173-C2'
);

INSERT INTO public.moloni_reference_seq (id, prefix, width, next_n, zip)
VALUES (1, 'F', 5, 10001, '173-C2')
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.moloni_reference_seq ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS moloni_reference_seq_deny_all ON public.moloni_reference_seq;
CREATE POLICY moloni_reference_seq_deny_all
  ON public.moloni_reference_seq
  FOR ALL
  TO anon, authenticated
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON public.moloni_reference_seq FROM anon, authenticated;
GRANT ALL ON public.moloni_reference_seq TO service_role;

-- Extensão do mapa de links (asin/lpn + estado reserved|linked)
ALTER TABLE public.moloni_product_links
  ADD COLUMN IF NOT EXISTS asin text,
  ADD COLUMN IF NOT EXISTS lpn text,
  ADD COLUMN IF NOT EXISTS fleaber_ref_code text,
  ADD COLUMN IF NOT EXISTS seller_id uuid,
  ADD COLUMN IF NOT EXISTS link_status text NOT NULL DEFAULT 'linked',
  ADD COLUMN IF NOT EXISTS zip text;

-- Permitir reserved antes de haver product_id Moloni
ALTER TABLE public.moloni_product_links
  ALTER COLUMN moloni_product_id DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'moloni_product_links_status_chk'
  ) THEN
    ALTER TABLE public.moloni_product_links
      ADD CONSTRAINT moloni_product_links_status_chk
      CHECK (link_status IN ('reserved', 'linked', 'failed'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS moloni_product_links_reference_uidx
  ON public.moloni_product_links (moloni_reference)
  WHERE moloni_reference IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS moloni_product_links_moloni_id_uidx
  ON public.moloni_product_links (moloni_product_id)
  WHERE moloni_product_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS moloni_product_links_asin_idx
  ON public.moloni_product_links (asin);

CREATE INDEX IF NOT EXISTS moloni_product_links_lpn_idx
  ON public.moloni_product_links (lpn);

COMMENT ON TABLE public.moloni_reference_seq IS
  'ZIP 173 — sequência códigos Moloni F##### (service_role). Aguarda aprovação.';
COMMENT ON COLUMN public.moloni_product_links.link_status IS
  'reserved = código atribuído pré-insert; linked = ficha Moloni criada; failed = erro.';
