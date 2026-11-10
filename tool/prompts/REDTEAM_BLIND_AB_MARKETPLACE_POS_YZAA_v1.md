# FLEABER — RED TEAM CEGO AB
## Auditor independente · PÓS-FECHO YZAA · MARKETPLACE / CHECKOUT · v1

> Fechámos Y (ronda 20260901T1715): conjunto qty=1 por SKU, `bundle_id` só do buyer certo, capturado não reabre checkout, session reuse só se `amount_total` igual.  
> **Poço:** refutar — provar que estes fechos **não** seguram dinheiro/stock/checkout — ou saturar.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · 2.º seller · conluio.  
`service_role` **só** fixture / observação / cleanup — **nunca** actor do exploit.

Prefixo fixtures: `RTAB-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos YZAA marketplace, ainda consigo pagar menos no conjunto, anexar bundle alheio, ou abrir 2.ª Checkout após captura?**

Prioridade: variantes **novas** — não repetir qty 3+1 exact Y2-001, bundle B2 exact Y2-002, hop capturado→RP exact Y8-010, session reuse barata exact Y3-001.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler: AUDITORIA/HARDENING/PRODUCTION_GATE · relatórios Y/Z/AA/V/W/X.

**Podes estudar:** código · SQL · RLS · Edge `create-payment-intent` / `refund-order`.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 a parar só em:
qty extra mesmo bundle exact · bundle alheio exact · hop pago→RP exact ·  
session reuse montante errado exact · dois bundle_id exact · hop unship exact V.

Se ≥50% = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AB (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AB1 | Conjunto qty | Outro caminho para qty≠1 no conjunto aceite? |
| AB2 | Bundle ownership | Cross-buyer bundle_id antes/depois de pago? |
| AB3 | Checkout Edge | Nova variante session reuse, race, bag parcial |
| AB4 | Capturado | Aliases de estado que reabrem checkout? |
| AB5 | Stock / hold | Inflate, ghost hold com bundle |
| AB6 | Race | Future.wait checkout 2× |
| AB7 | 2.º actor | B2/S2 no mesmo saco |
| AB8 | Composição → caixa | Encadear até Δwallet / Stripe net |

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
- Só P3/P4 → `FAIL_P2` ou `PASS_CEGO_SATURADO` se saturado

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_ab_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo** do relatório, bloco exacto:

```
AUDITOR: REDTEAM_BLIND_AB_POS_YZAA_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AB1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CONTAGEM`** (obrigatória, números explícitos):

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
```

Secção **`## CHECKLIST`** (28 linhas, responder SIM/NÃO/NÃO COMPROVADO):

1. P0 dinheiro irreversível encontrado — …
2. Quantos P0: …
… (28 linhas — copiar modelo Y/W)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
