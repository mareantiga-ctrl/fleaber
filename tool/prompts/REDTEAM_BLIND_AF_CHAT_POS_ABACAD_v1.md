# FLEABER — RED TEAM CEGO AF
## Auditor independente · PÓS-FECHO ABACAD · CHAT / PROVAS / UI · v1

> Fechámos AC (ronda 20260901T1825) + ABACAD: Unicode/raw JSON bloqueado, inbox INSERT/UPDATE, cards outcome/offer/review vs BD, proof_url paridade orders (nested URL, fleaber_private), label Seguro, regex inbox alargado. YZAA continua válido.  
> **Poço:** provar que o chat ainda mente, apaga provas, ou injecta URL falsa — sem mint directo.  
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

Prefixo fixtures: `RTAF-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos ABACAD chat, ainda consigo forjar recibo, mentir MB WAY/disputa/cancel/review/oferta, ou injectar URL/prova falsa?**

Prioridade: variantes **novas** — não repetir exactos AC/Z:
- NBSP+JSON exact AC2-WS-UNICODE-RAW
- outcome rejected lie exact AC1-RES-OUTCOME
- price_offer orphan exact AC1-PRICE-OFFER-ORPHAN
- offer outcome pending exact AC1-PRICE-OFFER-OUTCOME-STATUS
- URL-em-URL allowlist exact AC4-PROOF-OPEN-REDIRECT
- inbox INSERT forge exact AC5-INBOX-INSERT
- DELETE unicode card exact AC5-DELETE-UNICODE
- javascript proof exact Z4 · raw `{` exact Z1-BUNDLE-RAW

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler AUDITORIA/HARDENING · relatórios AC/Z/Y/AA/W/V.

**Podes estudar:** triggers chat · RLS · Flutter cards · storage paths.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só na lista exacta AC/Z acima.  
Se ≥50% dos achados = lista exacta → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AF (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AF1 | Cards vs BD | Outro kind / outcome que mente sem cruzar tabela? |
| AF2 | Prefixo / encoding | Bypass FLEABER_JSON_V1 (RTL, ZWSP, case, BOM, nested)? |
| AF3 | Cronologia | Prazo, inbox time, backdate INSERT/UPDATE |
| AF4 | URLs / provas | XSS, open redirect, public bucket, path encoding |
| AF5 | Inbox / delete | Preview falso, apagar cards imutáveis |
| AF6 | Storage | Upsert, overwrite, cross-user signed URL |
| AF7 | Cross-user | B2 thread alheia, proofs alheios |
| AF8 | Edge vs chat | Chat mente mas Edge obedece? (controlo — não conta P0 sozinho) |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_af_<timestamp>/` · **`FROZEN_REPORT.md`**

No **topo** do relatório (logo após título), repetir bloco **`## CONTAGEM`** com números finais.

Cabeçalho fixo:

```
AUDITOR: REDTEAM_BLIND_AF_CHAT_POS_ABACAD_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AF1,…]
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
