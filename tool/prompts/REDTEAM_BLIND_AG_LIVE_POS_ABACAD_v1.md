# FLEABER — RED TEAM CEGO AG
## Auditor independente · PÓS-FECHO ABACAD · LIVE MANUAL / STAFF · v1

> Fechámos AD (ronda 20260901T1825) + ABACAD: `converted` exige order paga **sempre** (incl. accepted→converted), INSERT fleaber_live converted bloqueado, discovery filtra available_qty, PATCH status=sold só via RPC. AA/YZAA continuam válidos.  
> **Poço:** provar que Facebook/manual/staff ainda consome stock sem dinheiro — ou saturar.  
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

Prefixo fixtures: `RTAG-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos ABACAD live, ainda consigo convert/mark_sold sem PI, esgotar stock via Hub/discovery fantasma, ou sabotar live alheia?**

Prioridade: variantes **novas** — não repetir exactos AD/AA:
- accepted→PATCH converted exact AD1-patch-accepted-converted-iso
- helper accepted→converted exact AD2
- INSERT fleaber_live converted exact AD1-insert-fleaber-converted
- discovery exhausted exact AD3-discovery-shows-exhausted
- PATCH status=sold exact AD3-patch-status-sold-hub
- pending→converted exact AA1 · helper pending→converted exact AA2 · hub qty=0 exact AA3-hub

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler AUDITORIA/HARDENING · relatórios AD/AA/Y/Z/X/V.

**Podes estudar:** RPC live · RLS staff · guards reserva · views Hub/discovery.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só na lista exacta AD/AA acima.  
Se ≥50% dos achados = lista exacta → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AG (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AG1 | Convert bypass | Outro caminho para `converted` sem order paga? RPC vs PATCH vs INSERT |
| AG2 | Staff/helper | Permissões finas, self-escalate, view-only |
| AG3 | Stock / Hub | Item esgotado visível em hub_live / discovery / REST buyer? |
| AG4 | mark_sold | Deslistar marketplace sem PI? RPC vs PATCH |
| AG5 | live_id / qty | Mover item, inflar qty, cross-seller |
| AG6 | Race | Dois PATCH converted / accept simultâneos |
| AG7 | Cross-seller | Sabotar live alheia, Mux token, end live |
| AG8 | Caixa | Δ wallet / order fantasma / Stripe live checkout |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_ag_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo** do relatório (logo após título), repetir bloco **`## CONTAGEM`** com números finais.

Cabeçalho fixo:

```
AUDITOR: REDTEAM_BLIND_AG_LIVE_POS_ABACAD_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AG1,…]
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
