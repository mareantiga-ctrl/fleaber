# FLEABER — RED TEAM CEGO AE
## Auditor independente · PÓS-FECHO ABACAD · MARKETPLACE / CHECKOUT · v1

> Fechámos AB (ronda 20260901T1825): **só EUR** no Edge, reuse exige moeda+montante, saco não reutiliza Session barata, stock não inflaciona com holds activos. YZAA continua válido (conjunto, bundle, capturado).  
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

Prefixo fixtures: `RTAE-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos ABACAD marketplace, ainda consigo pagar menos (moeda, montante, saco), inflar stock com holds, ou reabrir checkout indevido?**

Prioridade: variantes **novas** — não repetir exactos AB:
- `currency=jpy/usd/gbp` exact AB3-currency-unpinned
- USD→EUR reuse exact AB3-usd-poisons-eur-reuse
- bag overlap reuse exact AB3-bag-reuse-no-amount-check
- seller qty 1→9 com hold exact AB5-inflate-two-sessions
- qty 3+1 conjunto exact Y2-001 · bundle B2 exact Y2-002 · hop capturado→RP exact Y8-010

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler: AUDITORIA/HARDENING/PRODUCTION_GATE · relatórios AB/Y/Z/AA/V/W/X.

**Podes estudar:** código · SQL · RLS · Edge `create-payment-intent` / `refund-order`.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 a parar só na lista exacta AB/Y acima.  
Se ≥50% dos achados = lista exacta → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AE (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AE1 | Moeda / minor units | Bypass EUR-only? outra ISO? zero-decimal? |
| AE2 | Session reuse | Single-order e saco: montante, moeda, linhas diferentes |
| AE3 | Conjunto / bundle | Regressão YZAA qty=1 / buyer match / 2 bundle_id |
| AE4 | Capturado / FSM | 2.ª Session, aliases pós-captura |
| AE5 | Stock / hold | Inflate qty, ghost hold, cross-pool |
| AE6 | Race | Future.wait checkout · hold∥checkout |
| AE7 | 2.º actor | B2/S2 saco, bundle, refund |
| AE8 | Caixa | Encadear até Δwallet / Stripe net / stock (Stripe TEST pago se P0) |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_ae_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo** do relatório (logo após título), repetir bloco **`## CONTAGEM`** com números finais.

Cabeçalho fixo:

```
AUDITOR: REDTEAM_BLIND_AE_MARKETPLACE_POS_ABACAD_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AE1,…]
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
