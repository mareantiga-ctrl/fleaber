# FLEABER — RED TEAM CEGO AQ
## Auditor independente · PÓS-FECHO AHAM · HUB WEB / EDGE / DEEP LINK · v1

> Fechámos AHAM Hub/Edge: GRANT `batata_live_item_stock` + `batata_live_is_broadcasting` a anon; views Hub filtram `reserved_full` + exigem broadcasting; REST hitch ended oculto ao buyer; tip checkout **só** com live activa. Hostile AK PASS.  
> **Poço:** Hub/Edge ainda vaza stock, preço, autoridade ou settle alheio?  
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
Prefixo: `RTAQ-<timestamp>-`.  
Anon + JWT + origins hostis (`web_return_origin` / CORS).  
`service_role` só fixture.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Pela web / Edge / link, consigo dinheiro, stock, autoridade ou dados que a app esconde?**

Não re-auditar checkout JWT (AN) nem chat (AO).

Não repetir exactos AK/M:
- Hub anon 401 stock/broadcasting exact AK1-HUB-ITEMS-GRANT
- FOMO reserved_full ended exact AK1-FOMO-ENDED-RESERVED-FULL
- REST hitch ended exact AK1-REST-ENDED-HITCH
- tip ended published exact AK4-TIP-ENDED-PUB
- Hub paused · invite enum · dual Session clássico · mint pós-payout

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
≥50% = lista exacta AK/M → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AQ (obrigatório ≥4)
--------------------------------------------------
| # | Lente |
|---|--------|
| AQ1 | Hub views / FOMO / handle — leak além do publicado |
| AQ2 | `web_return_origin` / CORS / Connect return evil |
| AQ3 | Settle GET `session_id` alheio/forjado |
| AQ4 | Edge body spoof (`buyer_id`, `amount`, `tip_id`, `order_id`) |
| AQ5 | Mux/LiveKit create/complete cross-user |
| AQ6 | Storage público vs privado |
| AQ7 | Composição → Session/captura |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. Anon Hub exercitado (views + FOMO).  
2. ≥2 Edges com body/origin hostil.  
3. ≥1 settle/checkout com id alheio.  
4. Session criada ≠ captura.  
5. Flutter ≠ fronteira.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
`tool/redteam_blind_aq_<timestamp>/FROZEN_REPORT.md` — **CONTAGEM** no topo.

```
AUDITOR: REDTEAM_BLIND_AQ_HUB_EDGE_POS_AHAM_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AQ1,…]
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
