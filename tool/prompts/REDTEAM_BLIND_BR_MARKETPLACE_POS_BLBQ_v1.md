# FLEABER — RED TEAM CEGO BR
## Auditor independente · PÓS-FECHO BLBQ · MARKETPLACE / CHECKOUT · v1

> Fechámos BLBQ (20260902): chat/live/Hub/payout/disputa P0–P3. **Marketplace BL não chegou ao disco** nesta ronda — trata este poço como **ainda quente**. Hostile BLBQ + BFBK PASS.  
> **Poço:** ainda pagar menos, Sessions gémeas, stock fantasma — variantes **novas**.  
> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — ANTES de findings)
--------------------------------------------------
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`. Sem números = INVÁLIDO.

```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N

1. P0? SIM|NÃO   2. Quantos P0: N
3. P1? SIM|NÃO   4. Quantos P1: N
5. P2? SIM|NÃO   6. Quantos P2: N
7. P3? SIM|NÃO   8. Quantos P3: N
```
**Sem TOTAL → INVÁLIDO.** VEREDICTO: P0→`FAIL_P0` · P1→`FAIL_P1` · P2→`FAIL_P2` · só P3→`FAIL_P3` · TOTAL 0→`PASS_CEGO_SATURADO`.

--------------------------------------------------
AMBIENTE
--------------------------------------------------
Actors: anon · buyer · seller · B2 · S2. `service_role` só fixture.  
Prefixo `RTBR-<timestamp>-` · `tool/redteam_blind_br_<timestamp>/`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> Depois dos fechos BFBK/BLBQ no saco, ainda consigo total abaixo do contrato ou 2 Sessions?

**Exactos BFBK/BF (não contar):** AB∥AC dual Session · hífen+compact mesma linha · detach offer.  
**Novas:** 3 sacos A∩B∩C · bag com order já `pago` · claim token race · metadata `product_ids` reordenados · settle orphan · currency NBSP/ZWJ/`EUR ` · bundle PATCH total · offer Unicode qty · `unit_amount` string · Session reopen pós-expire.

--------------------------------------------------
CEGUEIRA
--------------------------------------------------
Não ler: reports BL–BQ · BF–BK · AT–BE. Código/Edge `create-payment-intent` OK.  
≥50% achados = lista exacta → `ATROFIA_ABORT`.

--------------------------------------------------
LENTES BR (8/8)
--------------------------------------------------
BR1 preço / contract_unit · BR2 Session / saco / claim · BR3 bundle / oferta · BR4 FSM pós-captura · BR5 stock / hold · BR6 race · BR7 2.º actor · BR8 caixa (Δwallet / Stripe se P0).

```
AUDITOR: REDTEAM_BLIND_BR_MARKETPLACE_POS_BLBQ_v1
production_touched: false · fase4: false · corrections_applied: false
```
Checklist 28. **NÃO CORRIGIR.** `FROZEN_REPORT.md` com CONTAGEM + TOTAL no topo.
