# FLEABER — RED TEAM CEGO AU
## Auditor independente · PÓS-FECHO ANAS · CHAT / PROVAS / UI · v1

> Fechámos ANAS chat: denylist alargada (Refund/Estorno/Wise/Revolut/Apple Pay/Venmo/SEPA/MBNet + cirílico normalizado); `chat_image.url` só **sign/authenticated** (sem `/object/public/`); notes HTML `<>` bloqueado; DELETE JSON após NBSP/Zs bloqueado; label Seguro rail-gap fechado. Hostile ANAS + AI/AHAM PASS.  
> **Poço:** chat ainda mente pagamento, apaga provas, ou injecta URL — sem mint directo.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST se preciso, cegueira, **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — preencher ANTES de findings)
--------------------------------------------------

Ver também `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: N
```

**VEREDICTO** (derivado da CONTAGEM):
- P0 aberto → `FAIL_P0`
- P0 fechado + P1 aberto → `FAIL_P1`
- P0–P1 fechados + P2 aberto → `FAIL_P2`
- P0–P2 fechados + só P3 → `FAIL_P3` ou `PASS_CEGO_SATURADO` se 8/8 lentes saturadas
- P0–P3 fechados (TOTAL = 0) → `PASS_CEGO_SATURADO`

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST se captura · produção proibida · Fase 4 não.  
Actors: buyer · seller · buyer2.  
`service_role` **só** fixture. Prefixo: `RTAU-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois ANAS chat, ainda forjo recibo, mento método de pagamento, ou injecto URL/prova falsa que a UI mostra?**

Não repetir exactos AO/AI/AF/AC/Z:
- cancel `display` Refund/Estorno/Wise exact AO-P2-01
- notes Wise/Revolut/Apple Pay exact AO-P2-02
- seguro label Wise/MB exact AO-P2-03
- chat_image public URL exact AO-P2-04
- inbox Wise/Revolut exact AO-P2-05
- NBSP+DELETE JSON exact AO-P3-01
- notes HTML exact AO-P3-02
- Reembolso/PayPal/Bizum exact AI · signed proof denied AI · ZWSP+prefix AI

**Variantes novas a tentar:** Klarna, Sofort, iDEAL, «cartão», unicode homoglyphs novos, URL sign de **outro** bucket/path, inbox sem dígitos mas com emoji €, `created_at` PATCH, kind homoglyph `\u0073eguro`.

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ANTI-ATROFIA
--------------------------------------------------
Não ler relatórios AO/AI/AF/ANAS antes de congelar.  
≥50% = lista exacta acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AU (obrigatório 8/8)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AU1 | Cards vs BD | Kind/outcome/campo novo que mente pagamento |
| AU2 | Prefixo / encoding | Bypass strip/Cf/case/homoglyph/nested |
| AU3 | Cronologia | Prazo, inbox time, backdate |
| AU4 | URLs / provas | Signed vs public, XSS, path alheio |
| AU5 | Inbox / delete | Preview falso, apagar imutável |
| AU6 | Storage | Upsert, cross-user signed URL |
| AU7 | Cross-user | B2 thread/proofs alheios |
| AU8 | Edge vs chat | Mentira UI sem mint (controlo) |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
`tool/redteam_blind_au_<timestamp>/FROZEN_REPORT.md` — **CONTAGEM** + **TOTAL** no topo.

```
AUDITOR: REDTEAM_BLIND_AU_CHAT_POS_ANAS_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AU1, AU2, AU3, AU4, AU5, AU6, AU7, AU8]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | FAIL_P3 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CHECKLIST`** (28 linhas — igual AT):

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
