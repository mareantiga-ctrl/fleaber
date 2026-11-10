# FLEABER — RED TEAM CEGO AT
## Auditor independente · PÓS-FECHO ANAS · MARKETPLACE / CHECKOUT · v1

> Fechámos ANAS (20260902): saco metadata **UUID compacto** (≤500 chars Stripe); desconto **tier** no saco só bloqueado por **oferta negociada** (`product_offer_id`), não selo catálogo; INSERT bundle `accepted`/total forjado → **403** (`bundle_status_pending_only`). Hostile ANAS + AHAM PASS.  
> **Poço:** provar que estes fechos **não** seguram dinheiro/stock/checkout — ou saturar com variantes **novas**.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — preencher ANTES de findings)
--------------------------------------------------

Ver também `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: N
```

**VEREDICTO** (derivado da CONTAGEM):
- P0 aberto → `FAIL_P0`
- P0 fechado + P1 aberto → `FAIL_P1`
- P0–P1 fechados + P2 aberto → `FAIL_P2`
- P0–P2 fechados + só P3 → `FAIL_P3` ou `PASS_CEGO_SATURADO` se 8/8 lentes saturadas
- P0–P3 fechados (TOTAL = 0) → `PASS_CEGO_SATURADO`

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.** · FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · 2.º seller · conluio.  
`service_role` **só** fixture / observação / cleanup — **nunca** actor do exploit.

Prefixo fixtures: `RTAT-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos ANAS marketplace, ainda consigo pagar menos, duplicar captura, inflar stock, ou deixar Sessions Stripe incoerentes?**

Prioridade: variantes **novas** — não repetir exactos AN/AH/AE/AB:
- saco 14 linhas metadata 500 exact AN-P3-01 (agora compact UUID — testar **16+** linhas, drift product_ids, settle legacy)
- tier desconto selado exact AN-P3-02 (agora só `product_offer_id` — testar bundle aceite, qty offer, desconto seller PATCH)
- bundle INSERT accepted exact AN-P3-03 (agora 403 — testar PATCH accepted, total PATCH, discount_pct buyer)
- bag A+B→A+C orphan exact AH2 · single→bag orphan AH2 · bag race AH6 · EUR-only AB3 · qty hold AB5

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler: AUDITORIA/HARDENING/PRODUCTION_GATE · relatórios AN/AH/AE/AB/Y/Z/AA/ANAS.

**Podes estudar:** código · SQL · RLS · Edge `create-payment-intent` / `refund-order`.

--------------------------------------------------
NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.  
Se ≥50% achados = lista exacta AN/AH/AE/AB acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AT (obrigatório 8/8)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AT1 | Preço autoritativo | Outro caminho para selar `contract_unit_cents` abaixo do catálogo? |
| AT2 | Session / saco | Expire falhou? 2 cs_ vivos? metadata drift compact UUID? claim bypass? |
| AT3 | Conjunto / bundle / tier | Regressão desconto saco · 2 bundle_id · accepted hostil |
| AT4 | Capturado / FSM | 2.ª Session, hop pós-captura, cancel 403 pós-pago |
| AT5 | Stock / hold | Ghost hold, cross-pool, inflate qty |
| AT6 | Race | Future.wait bag/single · hold∥checkout |
| AT7 | 2.º actor | B2/S2 saco, bundle, refund |
| AT8 | Caixa | Δwallet / Stripe net / stock (Stripe TEST pago se P0) |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_at_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo**, repetir **`## CONTAGEM`** com números finais + **`TOTAL P0–P3 abertos`**.

```
AUDITOR: REDTEAM_BLIND_AT_MARKETPLACE_POS_ANAS_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AT1, AT2, AT3, AT4, AT5, AT6, AT7, AT8]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | FAIL_P3 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
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
