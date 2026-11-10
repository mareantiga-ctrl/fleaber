# FLEABER — RED TEAM CEGO AP
## Auditor independente · PÓS-FECHO AHAM · LIVE MANUAL / STAFF · v1

> Fechámos AHAM live: `mark_sold` **não** deslista `checkout_product_id` alheio nem sem PI; INSERT `status=sold` bloqueado; hitch checkout_product seller mismatch; Hub GRANT stock+broadcasting; views/REST escondem `reserved_full` e exigem broadcasting. Hostile AJ/AK PASS.  
> **Poço:** convert/mark_sold sem PI, Hub fantasma, sabotar live/catálogo alheio — ou saturar.  
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
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST só se finding exigir.  
PRODUÇÃO: **PROIBIDO TOCAR.** · FASE 4: **NÃO INICIAR.**  
Actors: seller · helper/staff · buyer · seller2.  
`service_role` **só** fixture. Prefixo: `RTAP-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois AHAM live, ainda convert/mark_sold sem PI, stock fantasma, ou sabotar live/catálogo alheio?**

Não repetir exactos AJ/AG/AD/AA:
- mark_sold foreign checkout_product exact AJ4-02
- Hub anon 401 stock exact AJ3-HUB-ANON / AK GRANT
- INSERT status=sold exact AJ4-03
- mark_sold RPC broken exact AG4 · waitlist exact AG6 · REST ghost exact AG3
- accepted→converted exact AD1 · PATCH sold exact AD3

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
Não ler AJ/AG/AD/AA/AK antes de congelar. ≥50% exactos → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AP (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AP1 | Convert bypass | Outro caminho `converted` sem order paga? |
| AP2 | Staff/helper | Escalate, view-only, mark_sold auth |
| AP3 | Stock/Hub/REST | Esgotado/ended visível? anon Hub ok? |
| AP4 | mark_sold / hitch | Deslistar alheio ou sem PI? |
| AP5 | live_id / qty / cross-seller | |
| AP6 | Race accept/convert | |
| AP7 | Sabotar live alheia, Mux | |
| AP8 | Caixa — Δ wallet / order fantasma | |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
`tool/redteam_blind_ap_<timestamp>/FROZEN_REPORT.md` — **CONTAGEM** no topo.

```
AUDITOR: REDTEAM_BLIND_AP_LIVE_POS_AHAM_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AP1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CHECKLIST`** (28 linhas):

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
