# FLEABER — RED TEAM CEGO BF
## Auditor independente · PÓS-FECHO ATBE · MARKETPLACE / CHECKOUT · v1

> Fechámos ATBE (20260902): bag `bag_order_ids` **normaliza** hífen∥compact; expire hidrata UUID; `product_offer_id` **imutável** (JWT); dual Session race fechado no compare. Hostile ATBE PASS.  
> **Poço:** ainda pagar menos, 2 Sessions, stock fantasma, metadata drift — com variantes **novas**.  
> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — ANTES de findings)
--------------------------------------------------
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

```
## CONTAGEM
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N
TOTAL P0–P3 abertos: N
```

**Sem `TOTAL P0–P3` → relatório INVÁLIDO.**  
VEREDICTO: P0→`FAIL_P0` · P1→`FAIL_P1` · P2→`FAIL_P2` · só P3→`FAIL_P3` ou `PASS_CEGO_SATURADO` (8/8) · TOTAL 0→`PASS_CEGO_SATURADO`.

--------------------------------------------------
AMBIENTE
--------------------------------------------------
Staging · Stripe **TEST** · produção **PROIBIDO** · Fase 4 **NÃO**.  
Actors: anon · buyer · seller · B2 · S2. `service_role` só fixture.  
Prefixo: `RTBF-<timestamp>-`. Pasta: `tool/redteam_blind_bf_<timestamp>/`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> Depois do fecho ATBE no saco/oferta, ainda consigo total abaixo do contrato, Sessions gémeas, ou stock incoerente?

**Exactos ATBE/AT/AZ (NÃO contar se iguais):** compact∥hífen dual Session · detach `product_offer_id` · metadata 500 compact.  
**Variantes novas:** Unicode/ZWJ em bag ids · Session reopen pós-expire · settle com product_ids reordenados · offer qty>1 · bundle PATCH total · 2 bags partilham 1 order · currency casing extremo · hold∥checkout com offer selada.

--------------------------------------------------
CEGUEIRA
--------------------------------------------------
Não ler: reports AT–BE · ANAS · AHAM · HARDENING. Podes estudar código/SQL/Edge `create-payment-intent`.

--------------------------------------------------
LENTES BF (8/8)
--------------------------------------------------
| # | Lente |
|---|--------|
| BF1 | Preço / contract_unit |
| BF2 | Session / saco / claim |
| BF3 | Bundle / oferta / tier |
| BF4 | FSM pós-captura |
| BF5 | Stock / hold |
| BF6 | Race |
| BF7 | 2.º actor |
| BF8 | Caixa (Δwallet / Stripe se P0) |

Anti-atrofia: ≥50% achados = lista exacta ATBE → `ATROFIA_ABORT`.

```
AUDITOR: REDTEAM_BLIND_BF_MARKETPLACE_POS_ATBE_v1
production_touched: false · fase4: false · corrections_applied: false
```

Checklist 28. **NÃO CORRIGIR.** Congelar `FROZEN_REPORT.md` com CONTAGEM + TOTAL no topo.
