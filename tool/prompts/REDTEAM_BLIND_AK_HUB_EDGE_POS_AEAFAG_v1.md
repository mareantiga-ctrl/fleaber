# FLEABER — RED TEAM CEGO AK
## Auditor independente · PÓS-FECHO AEAFAG · HUB WEB / EDGE / DEEP LINK · v1

> Superfície **fora da app nativa**: Hub público, Edge Functions, origins, deep links, settle GET. AEAFAG alinhou live_item RLS/discovery — **poço:** Hub/Edge ainda vaza stock, preço, autoridade ou settle alheio?  
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
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 não.  
Prefixo: `RTAK-<timestamp>-`.  
Anon + JWT + origins hostis em headers / `web_return_origin`.  
`service_role` só fixture.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Pela web / Edge / link, consigo dinheiro, stock, autoridade ou dados que a app esconde?**

Não re-auditar checkout JWT clássico (AH) nem chat (AI).

Prioridade: variantes **novas** — não repetir exactos M:
- Hub paused items · invite enum · pairing ended · dual Session clássico · mint pós-payout · plain→JSON

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR
--------------------------------------------------
Não ler HARDENING como roteiro. Não corrigir. Provar → documentar.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
≥50% = lista exacta M acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AK (obrigatório ≥4)
--------------------------------------------------
| # | Lente |
|---|--------|
| AK1 | Hub views / FOMO / handle resolve (anon) — leak além do publicado |
| AK2 | Edge `web_return_origin` / CORS / Connect return → domínio evil |
| AK3 | Deep link / settle GET com `session_id` alheio ou forjado |
| AK4 | Edge body spoof (`buyer_id`, `amount`, `tip_id`, `user_id`, `order_id`) |
| AK5 | Mux/LiveKit create/complete cross-user |
| AK6 | Storage público vs privado (não chat_uploads — AI faz chat) |
| AK7 | Composição AK*→Session/captura |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. Anon Hub exercitado.  
2. ≥2 Edges com body/origin hostil.  
3. ≥1 tentativa settle/checkout com id alheio.  
4. Distinguir SESSION criada ≠ captura.  
5. Flutter ≠ fronteira.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
`tool/redteam_blind_ak_<timestamp>/FROZEN_REPORT.md`

No **topo**, repetir **`## CONTAGEM`** com números finais.

```
AUDITOR: REDTEAM_BLIND_AK_HUB_EDGE_POS_AEAFAG_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AK1,…]
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
