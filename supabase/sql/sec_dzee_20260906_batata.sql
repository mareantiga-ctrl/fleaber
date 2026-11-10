-- DZ–EE BATATA (staging only) — 2026-09-06
-- P2: off-platform multibanco / ifthenpay / contra-reembolso
-- P1 bag: helper list sibling cs_ for buyer (Edge reaper)
-- NÃO produção / Fase 4.

-- ===========================================================================
-- DZ P2-1 — denylist off-platform alargada
-- ===========================================================================
create or replace function public.batata_is_off_platform_payment(p_method text)
returns boolean
language plpgsql
immutable
as $$
declare
  v_raw text := coalesce(p_method, '');
  v_norm text;
  v_compact text;
begin
  v_norm := public.batata_normalize_payment_method(v_raw);
  v_compact := regexp_replace(v_norm, '[^a-z0-9]', '', 'g');

  if v_compact in (
    'card', 'stripe', 'applepay', 'googlepay', 'paypal',
    'pagamentonaapp', 'naapp', 'inapp', 'fleaber'
  ) then
    return false;
  end if;

  if v_raw ~ '[^\u0000-\u007f]' then
    if v_compact in (
      'mbway', 'transferencia', 'transfer', 'transf',
      'pagamentodirecto', 'pagamentodireto', 'directo', 'direto',
      'entregaemmao', 'emmao', 'levantamento', 'combinado', 'combinada',
      'pagamentodiretoaovendedormbwaytransf',
      'pagamentodirectoaovendedormbwaytransf',
      'multibanco', 'ifthenpay', 'sibs', 'contrareembolso', 'cod'
    ) then
      return true;
    end if;
    if v_compact not in (
      'card', 'stripe', 'applepay', 'googlepay', 'paypal',
      'pagamentonaapp', 'naapp', 'inapp', 'fleaber'
    ) then
      return true;
    end if;
  end if;

  if v_norm in (
    'mb way', 'mb_way', 'mb-way', 'mbway',
    'transferencia', 'transferência', 'transfer', 'transf',
    'pagamento directo', 'pagamento direto',
    'pagamento_directo', 'pagamento_direto',
    'directo', 'direto',
    'entrega em mao', 'entrega em mão', 'em mao', 'em mão',
    'levantamento', 'combinado', 'combinada',
    'pagamento direto ao vendedor (mb way/transf)',
    'pagamento directo ao vendedor (mb way/transf)',
    'multibanco', 'multi banco', 'mb', 'referencia multibanco',
    'ifthenpay', 'if then pay', 'sibs',
    'contra reembolso', 'contra-reembolso', 'contrareembolso',
    'cash on delivery', 'cod', 'pagamento a cobranca', 'pagamento à cobrança'
  ) then
    return true;
  end if;

  if v_compact in (
    'mbway', 'transferencia', 'transfer', 'transf',
    'pagamentodirecto', 'pagamentodireto', 'directo', 'direto',
    'entregaemmao', 'emmao', 'levantamento', 'combinado', 'combinada',
    'pagamentodiretoaovendedormbwaytransf',
    'pagamentodirectoaovendedormbwaytransf',
    'multibanco', 'multibanco', 'ifthenpay', 'sibs',
    'contrareembolso', 'cashondelivery', 'cod',
    'pagamentoacobranca', 'referenciamultibanco'
  ) then
    return true;
  end if;

  if position('mbway' in v_compact) > 0 then
    return true;
  end if;
  if position('transferencia' in v_compact) > 0
     or position('transfer' in v_compact) > 0 then
    return true;
  end if;
  -- DZ P2: Multibanco / Ifthenpay / COD / SIBS
  if position('multibanco' in v_compact) > 0 then
    return true;
  end if;
  if position('ifthenpay' in v_compact) > 0
     or position('ifthen' in v_compact) > 0 then
    return true;
  end if;
  if position('contrareembolso' in v_compact) > 0
     or position('cashondelivery' in v_compact) > 0 then
    return true;
  end if;
  if position('sibs' in v_compact) > 0 then
    return true;
  end if;

  return false;
end;
$$;

comment on function public.batata_is_off_platform_payment(text) is
  'DZ-P2: mbway/transf + multibanco/ifthenpay/COD/sibs; Pagamento na App never off.';

notify pgrst, 'reload schema';
