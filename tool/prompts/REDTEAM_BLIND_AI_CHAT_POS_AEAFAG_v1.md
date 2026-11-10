# FLEABER — RED TEAM CEGO AI
## Auditor independente · PÓS-FECHO AEAFAG · CHAT / PROVAS / UI · v1

> Fechámos AEAFAG chat: strip Unicode alargado + JSON cru bloqueado; outcomes estritos; `reservation_accepted` em pago bloqueado; cancel fake `display` bloqueado; label/notes mentirosos bloqueados; inbox regex alargado; `proof_url` só `fleaber_private`; `last_message_time` clamp 30s. Hostile PASS.  
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
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** se o finding exigir captura.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: buyer · seller · buyer2.  
`service_role` **só** fixture (simular recibo servidor).

Prefixo fixtures: `RTAI-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos AEAFAG chat, ainda consigo forjar recibo, mentir MB WAY/disputa/cancel/review/oferta, ou injectar URL/prova falsa?**

Prioridade: variantes **novas** — não repetir exactos AF/AC/Z:
- FF/VT/Ogham/LS/PS JSON exact AF-P1-01
- loose outcome exact AF-P1-02..05
- label PIX inteiro exact AF-P2-01 · notes MB WAY exact AF-P2-02
- inbox Transferência exact AF-P2-03 · fleaber.app proof exact AF-P2-04
- raw `{` exact Z1 · DELETE unicode exact AC5

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler AUDITORIA/HARDENING · relatórios AF/AC/Z/Y/AA/W/V.

**Podes estudar:** triggers chat · RLS · Flutter cards · storage paths.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só na lista exacta AF/AC/Z acima.  
Se ≥50% dos achados = lista exacta → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AI (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AI1 | Cards vs BD | Outro kind / outcome que mente sem cruzar tabela? |
| AI2 | Prefixo / encoding | Bypass FLEABER_JSON_V1 (RTL, ZWSP, case, BOM, nested)? |
| AI3 | Cronologia | Prazo, inbox time, backdate INSERT/UPDATE |
| AI4 | URLs / provas | XSS, open redirect, public bucket, path encoding |
| AI5 | Inbox / delete | Preview falso, apagar cards imutáveis |
| AI6 | Storage | Upsert, overwrite, cross-user signed URL |
| AI7 | Cross-user | B2 thread alheia, proofs alheios |
| AI8 | Edge vs chat | Chat mente mas Edge obedece? (controlo — não P0 sozinho) |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_ai_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo** do relatório (logo após título), repetir bloco **`## CONTAGEM`** com números finais.

```
AUDITOR: REDTEAM_BLIND_AI_CHAT_POS_AEAFAG_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AI1,…]
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
