-- ZIP 170-C2 — Moloni OAuth tokens + product link map (read-only phase)
-- Tokens: service_role only. Never expose via anon/authenticated.

CREATE TABLE IF NOT EXISTS public.moloni_oauth_tokens (
  id smallint PRIMARY KEY CHECK (id = 1),
  company_id text,
  access_token text NOT NULL,
  refresh_token text,
  expires_in integer,
  updated_at timestamptz NOT NULL DEFAULT now(),
  zip text
);

ALTER TABLE public.moloni_oauth_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS moloni_oauth_tokens_deny_all ON public.moloni_oauth_tokens;
CREATE POLICY moloni_oauth_tokens_deny_all
  ON public.moloni_oauth_tokens
  FOR ALL
  TO anon, authenticated
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON public.moloni_oauth_tokens FROM anon, authenticated;
GRANT ALL ON public.moloni_oauth_tokens TO service_role;

CREATE TABLE IF NOT EXISTS public.moloni_product_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fleaber_product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  moloni_product_id text NOT NULL,
  moloni_reference text,
  match_key text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (fleaber_product_id),
  UNIQUE (moloni_product_id)
);

CREATE INDEX IF NOT EXISTS moloni_product_links_ref_idx
  ON public.moloni_product_links (moloni_reference);

ALTER TABLE public.moloni_product_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS moloni_product_links_seller_select ON public.moloni_product_links;
CREATE POLICY moloni_product_links_seller_select
  ON public.moloni_product_links
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = fleaber_product_id
        AND p.seller_id = auth.uid()
    )
  );

-- Mutations only via service_role / edge (no insert/update/delete for clients)
REVOKE INSERT, UPDATE, DELETE ON public.moloni_product_links FROM anon, authenticated;
GRANT SELECT ON public.moloni_product_links TO authenticated;
GRANT ALL ON public.moloni_product_links TO service_role;

COMMENT ON TABLE public.moloni_oauth_tokens IS
  'ZIP 170 — tokens OAuth Moloni (service_role only). Escrita desactivada na app.';
COMMENT ON TABLE public.moloni_product_links IS
  'ZIP 170 — mapa persistente Fleaber product ↔ Moloni product_id.';
