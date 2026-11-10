# FLEABER — RED TEAM CEGO BL
## Auditor independente · PÓS-FECHO BFBK · MARKETPLACE / CHECKOUT · v1

> Fechámos BFBK: bag overlap AB∥AC expira Session; hífen∥compact dedupe no `seenBag`; NFC/NFD payout (outro poço). Hostile BFBK + ATBE PASS.  
> **Poço:** ainda pagar menos, Sessions gémeas, stock fantasma — variantes **novas**.  
> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir**.

## CONTAGEM (obrigatório — ANTES de findings)
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`. Sem números = relatório INVÁLIDO.

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
**Sem TOTAL → INVÁLIDO.** O fecho começa sempre por colar esta CONTAGEM no chat.  
VEREDICTO: P0→`FAIL_P0` · P1→`FAIL_P1` · P2→`FAIL_P2` · só P3→`FAIL_P3`/`PASS_CEGO_SATURADO` · TOTAL 0→`PASS_CEGO_SATURADO`.

## AMBIENTE
Actors: anon · buyer · seller · B2 · S2. `service_role` só fixture.  
Prefixo `RTBL-<timestamp>-` · `tool/redteam_blind_bl_<timestamp>/`.

## MISSÃO
> Depois do fecho BFBK no saco, ainda consigo total abaixo do contrato ou 2 Sessions?

**Exactos BFBK/BF (não contar):** AB∥AC dual Session · hífen+compact mesma linha · detach offer.  
**Novas:** 3 sacos A∩B∩C · bag com order já `pago` · claim token race · metadata product_ids drift · settle orphan · currency NBSP/ZWJ · bundle PATCH · offer Unicode.

## LENTES BL (8/8)
BL1 preço · BL2 Session/saco · BL3 bundle/oferta · BL4 FSM · BL5 stock · BL6 race · BL7 2.º actor · BL8 caixa.

Não ler BF/AT/AZ/ANAS. Código/Edge OK. ≥50% exactos → `ATROFIA_ABORT`.

```
AUDITOR: REDTEAM_BLIND_BL_MARKETPLACE_POS_BFBK_v1
production_touched: false · fase4: false · corrections_applied: false
```
Checklist 28. **NÃO CORRIGIR.** `FROZEN_REPORT.md` com CONTAGEM + TOTAL no topo.
