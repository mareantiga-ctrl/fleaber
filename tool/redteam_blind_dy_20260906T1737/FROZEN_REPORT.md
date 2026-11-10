# FROZEN_REPORT — RED TEAM CEGO DY · Composição multi-superfície · POS_DNDS

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 0

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DY_COMPOSICAO_POS_DNDS_v1
FROZEN_AT: 2026-09-06T17:52:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DY1, DY2, DY3, DY4, DY5, DY6, DY7, DY8]
probes_na_tabela: 18
classes_novas: 10
races: 6
stripe_test_pago: true
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTDY-20260906T1737
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded`: `pi_3UCjCH*`, `pi_3UCjCV*`, `pi_3UCjCn*`, `pi_3UCjCt*`, `pi_3UCjCz*`, `pi_3UCjD6*`) · actores JWT B1/S1/B2/S2 · `service_role` só fixture / observação / restore. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

S1 `980f4fa1-…` `hub_published=true` à saída. Lives de fixture `ended` / `is_active=false`.

Cruzamentos **novos vs DS**: follow+favorite+hold · rifa∥CPI no draw · live_only vs Hub · oferta+bundle Session · disputa+release+stock · rifa+bag+Hub. **Não** se repetiu só o fio hitch+Hub clássico.

--------------------------------------------------
## TABELA DE PROVAS (18)
--------------------------------------------------

| probe_id | superfícies tocadas | acção | HTTP | oráculos multi-sítio | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|---------------------|-------|------|----------------------|------------------|--------------|
| A1 | Hub + CPI + tip + wallet | unpublish mid-checkout **e** mid-tip + payout | unpub 200; tip GET unpaid; connect 200 | Hub mid n=0; tip `pending`; Δwallet −1€ saldo existente; S1 restored `true` | FAIL | SIM |
| A2 | Hub + products + orders | sold+listed vs vitrine vs insert | Hub 200 []; insert 400 `order_hold_exceeds_stock` | sold+listed; Hub 0; sem encomenda | FAIL residual | NÃO |
| A3 | Hub + orders + CPI | leftover após pago parcial qty 2→1 | e2e 200 `pi_3UCjCH…`; Hub 200 1 linha; CPI leftover `cs_test_a1RzPKhV…` | status `pago`; qty=1; Hub n=1; leftover comprável | FAIL | NÃO |
| A4 | follows + favorites + Hub + hold | follow + favorite + hold qty=1 + 2.º buyer | fol 409 duplicate; fav 201; B2 insert 400 hold | Hub n=0; fav 1; follow 1; ≤1 dono | FAIL | SIM |
| A5 | rifa + Hub + insert + live_item | draw + Hub + insert (reteste Hub 0) | draw 200 `drawn`; insert 400 hold | winner 1; qty 1→0; Hub n=0; prize 0; item `available` | FAIL | SIM |
| B1 | rifa + accept A + bag B + Hub | rifa activa A + hitch A + bag B | pass1 bag 429; **pass3** accept 200 + bag `cs_test_a1FGbSPw…` | A accepted; B abre Session; Hub A/B n=0 (hold) | FAIL | SIM |
| B2 | convert + Hub + chat card + order | pago Stripe + hitch convert/reconcile + card | e2e 200 `pi_3UCjCV…`; convert 403; reconcile 403; card 201 | res ≠ converted; Hub n=0 qty=0; order `pago`; card ok | FAIL | SIM |
| B3 | end_live ∥ bag CPI ∥ Hub | Future.wait end ∥ bag ∥ hub | end 200 ended; bag 429 rate-limit | live `ended`; Hub SKU n=0; Hub live by-id 1 (gravado) | FAIL | NÃO |
| B4 | rifa draw ∥ CPI marketplace + Hub | Future.wait draw ∥ CPI B2 qty=1 | draw 200 `drawn`; CPI 400 `product is marked sold` | winner 1; qty 0; Hub n=0; prize 0; sem 2 donos | FAIL | SIM |
| B5 | rifa live_only + Hub lives + products | draw prémio sem product vs Hub | draw 200 `drawn`; ghosts 0 | winner 1; prize 0; ghosts 0; Hub lives 1; sem SKU | FAIL | SIM |
| C1 | offer + CPI + Hub + orders | oferta 8€ aceite + CPI amount=1 | pass1 429; **pass3** CPI 200 selo **905¢** | offer accepted 8€; Hub n=1; underpay ignorado | FAIL | SIM |
| C2 | offer + bundle + Session + Hub | bundle∥oferta overlap SKU-X qty=1 | bundle accepted; insert X 400 hold; CPI 429 | ≤1 cs_ (0); overlap bloqueado no hold | FAIL | SIM |
| C3 | chat card + order amount | pago + card canónico vs amount hostil | e2e 200 `pi_3UCjCn…`; cards 201; amount_paid **590** | status `pago`; hostil persistiu; ledger inalterado | FAIL | NÃO |
| C4 | orders + wallet | seller/buyer PATCH pago sem Stripe | buyer 403 `order_status_requires_capture`; seller 403 `order_money_fields_immutable` | status `reserva_pendente`; amount_paid null; Δwallet 0 | FAIL | NÃO |
| D1 | refund ∥ CPI leftover | Future.wait refund pago ∥ CPI leftover | rf 200 `re_3UCjCt…` cancelado; CPI 200 `cs_test_a1ID4GMX…` | qty 1→2; old cancelado; new `reserva_pendente` | FAIL residual | NÃO |
| D2 | release ∥ disputa + stock + Hub | Future.wait release + POST disputa | release 200 `false`; disputa 403 RLS | Δwallet 0; status `pago`; qty=1; Hub n=1 leftover | FAIL | SIM |
| D3 | 2 buyers Hub visível + CPI | 2 insert+CPI qty=1 Hub | Hub inicial n=1; 2.º insert 400 hold; CPI 429 | Hub após hold n=0; ≤1 encomenda; 2.º buyer recusado | FAIL | NÃO |
| D4 | Hub + order + wallet + chat | pago 4242 → 4 sítios | e2e 200 `pi_3UCjD6…` 590¢ succeeded; card 201 | status `pago` qty 2→1; Hub leftover n=1; Δwallet 0/0; chat 1 | FAIL | NÃO |

Linhas na tabela: **18**. Stripe TEST pago: **sim**. Residual clássico A2 sold + D1 refund∥leftover = 2/18 = 11% ≪ 40%. **Não** ATROFIA_ABORT. Classes novas: A1 tip+payout+unpublish · A4 follow+favorite+hold · A5 rifa+insert Hub 0 · B1 rifa+bag+Hub · B2 convert+chat · B4 rifa∥CPI draw · B5 live_only · C1 oferta+selo · C2 oferta+bundle · D2 release∥disputa+stock (**10 ≥ 4**). Races: B3, B4, C2, D1, D2, D3 (**6 ≥ 5**).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (C1b selo 905¢ vs body 1)
10. Buyer manipula qty autoritativa — NÃO (holds `order_hold_exceeds_stock`)
11. Seller falsifica pagamento plataforma — NÃO (C4 PATCH 403)
12. JWT cria saldo/fundos — NÃO (tip pending; Δwallet 0 no pago até release)
13. Refund excede captura — NÃO (D1 idempotente 590¢)
14. Release+refund cria dinheiro líquido — NÃO (D2 release false, Δ=0)
15. Payout duplica Transfer — NÃO (A1 1× débito de saldo existente, não mint)
16. Stock=1 duas vendas válidas — NÃO (A4/D3/B4 2.º recusado)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da matriz)
24. RPC SECURITY DEFINER perigoso executável — NÃO (convert 403)
25. RLS crítico quebrado — NÃO (disputa 42501)
26. Edge confia total do cliente — NÃO (C1b selo 905¢)
27. Regressão funcional (happy path partido) — NÃO (A3 leftover; D4 pago; C1b offer; B1b bag)
28. Saturação atingida — SIM (18 probes; 10 classe_nova; 6 races; 1+ pago; P0–P2=0; residual 11%)

Poços DY: hub=SIM · live=SIM · chat=SIM · wallet=SIM · race=SIM · offer=SIM · rifa=SIM · caixa=SIM  
ATROFIA: NÃO (2/18 residual; ângulos novos = rifa∥CPI no draw, live_only vs Hub, follow+favorite+hold, oferta+bundle)  
Pagamento TEST: **pago** (vários PI `succeeded`). Chat card após e2e: canónico 201; hostil 201 **sem** alterar `amount_paid_cents` (não conta).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

Nenhum. IDs abertos: nenhum. Soma P0+P1+P2+P3 `quantos` = 0.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A1 payout unpublished | **Não mint.** Connect 200 debitou 1,00 € de saldo já existente; tip ficou `pending`. Hub unpublished não congela Connect. Anti-atrofia. |
| Hub hide live accepted clássico | **Não exercitado como finding.** B1b: accept A + bag B (outra linha) com rifa activa — bag abriu `cs_`. |
| Hub hide rifa drawn clássico | **Hub n=0** após draw (A5/A5r/B4). Insert 400. Selagem DNDS visível. Não contar o P2 DS (vitrine ainda listava). |
| MB WAY exact 400 | **Não exercitado** (anti-atrofia). |
| follow published 403 | **Não exercitado** (anti-atrofia). A4 follow 409 duplicate (já seguia S1). |
| 4∥2 ≤1 cs_ | **Não exercitado** (anti-atrofia). C2 é oferta∥bundle overlap, não 4∥2. |
| C3 card hostil amount=0.01 | Persistiu; `amount_paid_cents=590` inalterado — cards não liquidam. |
| B3 Hub lives by-id após ended | Linha ainda visível em `hub_lives_public` (possível Gravados). Sem prova de player “ao vivo”. Não conta. |
| A5/B5 prize_orders [] | Draw sem encomenda-prémio; Hub+stock selados (qty 0, insert 400, CPI sold). Selo fecha a montra. |
| A5r hitch pós-draw | Reserva `pending` inserida; accept 400 `qty_exceeds_stock`. Sem segundo dono. Label `live_item.status=available` stale — não conta (caminho de claim fechado). |
| C1/C2/D3/B1/B3 CPI 429 | Rate-limit de Sessions no actor B1; C1b/B1b com B2 fecharam o oráculo. |

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------

| Lente | Evidência |
|-------|-----------|
| DY1 hub | A2 sold oculto; A3 leftover visível; A4 Hub n=0 após claim; A5 Hub n=0 após draw; D3 Hub n=0 após hold |
| DY2 live | B1b accept≠bag B; B2 convert 403; B3 end∥bag; B5 live_only sem SKU |
| DY3 chat | C3 card vs amount_paid 590; B2 card 201; D4 card 201 |
| DY4 wallet | D2 release false Δ=0; A1 débito saldo existente; D4 Δ 0/0 até release |
| DY5 race | B3, B4, C2, D1, D2, D3 |
| DY6 offer | C1b selo 905¢; C2 oferta∥bundle hold |
| DY7 rifa | A5 Hub 0+insert 400; B4 draw∥CPI sold; B5 live_only sem ghost SKU |
| DY8 caixa | D4 pago 590¢ 4 sítios; C4 PATCH 403; D2 disputa RLS |

--------------------------------------------------
## FIO (Hub + live + chat + wallet + caixa)
--------------------------------------------------

Unpublish + tip + payout (A1) → sold vs Hub (A2) → leftover pago (A3) → follow+favorite+hold (A4) → rifa drawn+insert (A5) → rifa+accept A + bag B (B1) → convert+card (B2) → end∥bag∥Hub (B3) → rifa∥CPI no draw (B4) → live_only vs Hub (B5) → oferta underpay (C1) → oferta∥bundle (C2) → chat vs pago (C3) → PATCH pago (C4) → races D1–D4.

--------------------------------------------------
## OPERAÇÃO
--------------------------------------------------

- Lives criadas: `ended` / `is_active=false` (finally pass1–pass3).
- S1 `hub_published=true` à saída (RPC `batata_publish_hub`).
- Pasta: `tool/redteam_blind_dy_20260906T1737/` (`pass1.json`, `pass2.json`, `pass3.json`).
- **NÃO CORRIGIR.** Fase 4 não.

```
AUDITOR: REDTEAM_BLIND_DY_COMPOSICAO_POS_DNDS_v1
probes_na_tabela: 18 · classes_novas: 10 · races: 6
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
