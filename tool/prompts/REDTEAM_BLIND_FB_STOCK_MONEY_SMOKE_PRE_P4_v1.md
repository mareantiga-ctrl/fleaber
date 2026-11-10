# FLEABER — RED TEAM CEGO FB · SMOKE PRÉ-P4
## Stock / Hub / dinheiro curto — **quota ≥10**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR**.  
> Lente **diferente** de FA: oversell, Hub, wallet. Sem re-martelar bag∥avulso.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTFB-<timestamp>-` · pasta `tool/redteam_blind_fb_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**10**.
2. **≥1** 2 buyers qty=1 → 2.º insert/stock fail (sem oversell).
3. **≥1** pago 4242 + Hub leftover coerente (qty / n).
4. **≥1** underpay / amount forge → servidor manda.
5. **≥1** wallet Δ seller após pago (ou documentar 0 se tip/outro).
6. Oversell / double credit = **P0**.
7. **≥3 classe_nova**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Stock e Hub batem com o que o Stripe liquidou.  
> Dois compradores no mesmo artigo qty=1 não vendem 2.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
buyer refund 403 residual · settle unpaid 402 (≤1 cada)

--------------------------------------------------
## MATRIZ (≥10)
--------------------------------------------------

### FB-A Stock (≥4)
A1 2 buyers mesmo SKU qty=1 → 2.º 400 stock  
A2 reserve∥reserve 0 ms (se aplicável)  
A3 após pago A: qty↓ · is_sold · Hub n  
A4 2.º buyer tenta CPI na mesma unit → bloqueado

### FB-B Hub / composição (≥3)
B1 Hub público vs order após pago (oráculo ≥2 sítios)  
B2 leftover qty 2→1 visível Hub  
B3 bag pago 3–5 lines: todas `pago` ou nenhuma (sem meia liquidação)

### FB-C Dinheiro curto (≥3)
C1 underpay / total_eur=0 → amount catálogo  
C2 seller wallet antes/depois 1 pago (Δ esperado)  
C3 2× settle mesma session → 1 efeito

**Total ≥10.**

--------------------------------------------------
## GATE
--------------------------------------------------
P0–P2=0 → `PASS_CEGO_SATURADO`. Oversell → `FAIL_P0`.

```
AUDITOR: REDTEAM_BLIND_FB_STOCK_MONEY_SMOKE_PRE_P4_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
