# FLEABER — RED TEAM CEGO AO
## Auditor independente · PÓS-FECHO AHAM · CHAT / PROVAS / UI · v1

> Fechámos AHAM chat: `display` cancel com mentira € bloqueado; notes/inbox alargados (PayPal/Bizum/Reembolso); label Seguro sem dígitos bloqueado; proof **signed** URL aceite; strip Cf (ZWSP) antes do prefixo; `product_ids` decoy no bundle bloqueado. Hostile AI PASS.  
> **Poço:** chat ainda mente, apaga provas, ou injecta URL — sem mint directo.  
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
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST se captura · produção proibida · Fase 4 não.  
Actors: buyer · seller · buyer2.  
`service_role` **só** fixture. Prefixo: `RTAO-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois AHAM chat, ainda forjo recibo, mento MB WAY/disputa/cancel/review/oferta, ou injecto URL/prova falsa?**

Não repetir exactos AI/AF/AC/Z:
- cancel `display` mentiroso exact AI P2-01
- label PIX sem dígitos exact AI P2-02 · notes Reembolso exact AI P2-03
- inbox PayPal/Bizum exact AI P2-07 · signed proof denied exact AI P2-08
- bundle product_ids decoy exact AI P2-04 · ZWSP+prefix exact AI P2-08
- FF/VT/Ogham JSON exact AF · raw `{` exact Z1 · fleaber.app proof exact AF

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
Não ler relatórios AI/AF/AC/Z antes de congelar.  
≥50% = lista exacta acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AO (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AO1 | Cards vs BD | Kind/outcome/campo novo que mente |
| AO2 | Prefixo / encoding | Bypass strip/Cf/case/nested |
| AO3 | Cronologia | Prazo, inbox time, backdate |
| AO4 | URLs / provas | Signed vs unsigned, XSS, path |
| AO5 | Inbox / delete | Preview falso, apagar imutável |
| AO6 | Storage | Upsert, cross-user signed URL |
| AO7 | Cross-user | B2 thread/proofs alheios |
| AO8 | Edge vs chat | Mentira UI sem mint (controlo) |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
`tool/redteam_blind_ao_<timestamp>/FROZEN_REPORT.md` — **CONTAGEM** no topo.

```
AUDITOR: REDTEAM_BLIND_AO_CHAT_POS_AHAM_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AO1,…]
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
