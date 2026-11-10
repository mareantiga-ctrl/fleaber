# FLEABER — RED TEAM CEGO AH
## Auditor independente · PÓS-FECHO AEAFAG · MARKETPLACE / CHECKOUT · v1

> Fechámos AEAFAG (20260901): **live ended não baixa preço**; saco reuse compara `bag_order_ids`; single checkout **expira** Session de saco; EUR-only + reuse moeda+montante (ABACAD); stock/holds; bundle qty=1; capturado não reabre. YZAA/VWX hostile 16/16 PASS.  
> **Poço:** provar que estes fechos **não** seguram dinheiro/stock/checkout — ou saturar.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — preencher ANTES de findings)
--------------------------------------------------

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N  (fora de âmbito salvo pedido)
```

**VEREDICTO** (derivado da CONTAGEM):
- P0 aberto → `FAIL_P0`
- P0 fechado + P1 aberto → `FAIL_P1`
- P0–P1 fechados + P2 aberto → `FAIL_P2`
- P0–P2 fechados + só P3 → `FAIL_P2` ou `PASS_CEGO_SATURADO` se saturado
- P0–P3 fechados → `PASS_CEGO_SATURADO`

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · 2.º seller · conluio.  
`service_role` **só** fixture / observação / cleanup — **nunca** actor do exploit.

Prefixo fixtures: `RTAH-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos AEAFAG marketplace, ainda consigo pagar menos, duplicar captura, inflar stock, ou deixar Sessions Stripe incoerentes?**

Prioridade: variantes **novas** — não repetir exactos AE/AB:
- stale `live_item` ended price exact AE1-STALE-LIVE-ITEM-PRICE
- bag same amount different lines exact AE2-BAG-SAME-AMOUNT
- bag→single orphan Session exact AE2-BAG-THEN-SINGLE
- `currency=jpy/usd` exact AB3 · USD→EUR reuse exact AB3
- seller qty 1→9 hold exact AB5 · bundle qty>1 exact Y2

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler: AUDITORIA/HARDENING/PRODUCTION_GATE · relatórios AE/AB/Y/Z/AA/V/W.

**Podes estudar:** código · SQL · RLS · Edge `create-payment-intent` / `refund-order`.

--------------------------------------------------
NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.  
Se ≥50% achados = lista exacta AE/AB acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AH (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AH1 | Preço autoritativo | Outro caminho para selar `contract_unit_cents` abaixo do catálogo? |
| AH2 | Session / saco | Reuse errado, expire falhou, 2 cs_ abertos, metadata drift |
| AH3 | Conjunto / bundle | Regressão qty=1 / buyer match / 2 bundle_id |
| AH4 | Capturado / FSM | 2.ª Session, hop pós-captura |
| AH5 | Stock / hold | Ghost hold, cross-pool, inflate qty |
| AH6 | Race | Future.wait checkout · hold∥checkout |
| AH7 | 2.º actor | B2/S2 saco, bundle, refund |
| AH8 | Caixa | Δwallet / Stripe net / stock (Stripe TEST pago se P0) |

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
Pasta: `tool/redteam_blind_ah_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo**, repetir **`## CONTAGEM`** com números finais.

```
AUDITOR: REDTEAM_BLIND_AH_MARKETPLACE_POS_AEAFAG_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AH1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CHECKLIST`** (28 linhas, responder SIM/NÃO/NÃO COMPROVADO):

1. P0 dinheiro irreversível encontrado — …
2. Quantos P0: …
3. P1 caminho explorável encontrado — …
4. Quantos P1: …
5. P2 hygiene encontrado — …
6. Quantos P2: …
7. P3 baixo risco encontrado — …
8. Quantos P3: …
9. Buyer manipula preço autoritativo — …
10. Buyer manipula qty autoritativa — …
11. Seller falsifica pagamento plataforma — …
12. JWT cria saldo/fundos — …
13. Refund excede captura — …
14. Release+refund cria dinheiro líquido — …
15. Payout duplica Transfer — …
16. Stock=1 duas vendas válidas — …
17. Stock=1 duas capturas líquidas permanentes — …
18. Bypass capacidade/reserva — …
19. Cross-user financeiro — …
20. Cross-user dados sensíveis — …
21. Buyer assume seller/admin — …
22. Seller assume buyer/admin — …
23. Reviews forjadas — …
24. RPC SECURITY DEFINER perigoso executável — …
25. RLS crítico quebrado — …
26. Edge confia total do cliente — …
27. Regressão funcional (happy path partido) — …
28. Saturação atingida — …

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
