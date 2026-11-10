-- ZIP 173.1 — sequência FLB###### (9 chars) aprovada; sem writes Moloni.

-- Permitir width=6 (dígitos); total FLB+6 = 9 caracteres.
ALTER TABLE public.moloni_reference_seq
  DROP CONSTRAINT IF EXISTS moloni_reference_seq_width_check;

ALTER TABLE public.moloni_reference_seq
  ADD CONSTRAINT moloni_reference_seq_width_check
  CHECK (width BETWEEN 3 AND 8);

UPDATE public.moloni_reference_seq
SET
  prefix = 'FLB',
  width = 6,
  next_n = 1,
  approved_at = now(),
  approved_by = 'user:sequencia_FLB_aprovada_zip173.1',
  updated_at = now(),
  zip = '173.1-C2'
WHERE id = 1;

COMMENT ON TABLE public.moloni_reference_seq IS
  'ZIP 173.1 — sequência FLB###### (FLB000001…). Formato aprovado; escrita Moloni só com GO.';

-- Alocação atómica para creates concorrentes (só usada em live+GO).
CREATE OR REPLACE FUNCTION public.allocate_moloni_reference_batch(p_count integer)
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
  v_n bigint;
  v_code text;
BEGIN
  IF p_count IS NULL OR p_count < 1 OR p_count > 500 THEN
    RAISE EXCEPTION 'invalid_count';
  END IF;

  SELECT s.prefix, s.width, s.next_n
    INTO v_prefix, v_width, v_start
  FROM public.moloni_reference_seq s
  WHERE s.id = 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'seq_missing';
  END IF;

  UPDATE public.moloni_reference_seq
  SET next_n = v_start + p_count, updated_at = now()
  WHERE id = 1;

  FOR v_i IN 0..(p_count - 1) LOOP
    v_n := v_start + v_i;
    v_code := upper(v_prefix) || lpad(v_n::text, v_width, '0');
    reference := v_code;
    seq_n := v_n;
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.allocate_moloni_reference_batch(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.allocate_moloni_reference_batch(integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.allocate_moloni_reference_batch(integer) TO service_role;
