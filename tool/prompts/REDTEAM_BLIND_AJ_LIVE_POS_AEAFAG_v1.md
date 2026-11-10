# FLEABER — RED TEAM CEGO AJ
## Auditor independente · PÓS-FECHO AEAFAG · LIVE MANUAL / STAFF · v1

> Fechámos AEAFAG live: `mark_sold` RPC (flag interna); waitlist accept (pending fora do chão qty); REST `live_items` esconde esgotados; MB WAY `pago` exige `proof_url`; order em item esgotado bloqueado; inflate qty live_only/produto bloqueado; `mark_sold` sem `can_change_current_item`. Hostile PASS.  
> **Poço:** convert/mark_sold sem PI, Hub fantasma, sabotar live alheia — ou saturar.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST se preciso, cegueira, **não corrigir**.

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
Stripe: **TEST** só se finding exigir.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: seller · helper/staff · buyer · seller2.  
`service_role` **só** fixture.

Prefixo fixtures: `RTAJ-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos AEAFAG live, ainda consigo convert/mark_sold sem PI, esgotar stock via Hub/discovery fantasma, ou sabotar live alheia?**

Prioridade: variantes **novas** — não repetir exactos AG/AD/AA:
- mark_sold RPC broken exact AG4 · waitlist freeze exact AG6
- REST ghost exact AG3 · MB WAY fake pago exact AG8
- inflate qty exact AG5 · order exhausted exact AG3-buyer-insert
- accepted→converted exact AD1 · PATCH sold exact AD3 · discovery exhausted exact AD3

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler AUDITORIA/HARDENING · relatórios AG/AD/AA/Y/Z/X/V.

**Podes estudar:** RPC live · RLS staff · guards reserva · views Hub/discovery.

--------------------------------------------------
NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.  
≥50% exactos AG/AD/AA → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AJ (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AJ1 | Convert bypass | Outro caminho para `converted` sem order paga? |
| AJ2 | Staff/helper | Permissões finas, self-escalate, view-only |
| AJ3 | Stock / Hub | Item esgotado visível em hub / discovery / REST buyer? |
| AJ4 | mark_sold | Deslistar marketplace sem PI? RPC vs PATCH |
| AJ5 | live_id / qty | Mover item, inflar qty, cross-seller |
| AJ6 | Race | Dois PATCH converted / accept simultâneos |
| AJ7 | Cross-seller | Sabotar live alheia, Mux token, end live |
| AJ8 | Caixa | Δ wallet / order fantasma / Stripe live checkout |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_aj_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo**, repetir **`## CONTAGEM`** com números finais.

```
AUDITOR: REDTEAM_BLIND_AJ_LIVE_POS_AEAFAG_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AJ1,…]
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

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
