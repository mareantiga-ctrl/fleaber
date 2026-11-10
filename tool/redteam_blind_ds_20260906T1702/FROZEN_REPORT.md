# FROZEN_REPORT — RED TEAM CEGO DS · Composição multi-superfície · POS_DHDM

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 1

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DS_COMPOSICAO_POS_DHDM_v1
FROZEN_AT: 2026-09-06T17:15:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DS1, DS2, DS3, DS4, DS5, DS6, DS7, DS8]
probes_na_tabela: 16
classes_novas: 8
stripe_test_pago: true
VEREDICTO: FAIL_P2
prefix: RTDS-20260906T1702
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded`: `pi_3UCidC*`, `pi_3UCidO*`, `pi_3UCide*`, `pi_3UCidk*`, `pi_3UCidr*`, `pi_3UCidw*`) · actores JWT B1/S1/B2/S2 · `service_role` só fixture / observação / restore. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

S1 `980f4fa1-…` `hub_published=true` à saída. Lives de fixture `ended` / `is_active=false`. Pass1 **P0-A1-PAYOUT retractado** (levantamento de saldo existente, não mint).

--------------------------------------------------
## P2-1 — Vencedor da rifa: o Hub ainda vende o prémio; não há encomenda-prémio
--------------------------------------------------

**O que isto é:** quem ganha a rifa no directo tem de ficar com o artigo (ou o artigo sai da loja). O mesmo SKU não pode continuar à venda no Hub como se ninguém o tivesse ganho.

**Quem / onde:** Vendedor S1 · Comprador B1 (vencedor) · Hub público. Rifa `2aba4530-…` · SKU `645129b6-…` «RTDS-20260906T1702 B4r prize» · live item `a03be0b0-…`.

**O que fizemos:** artigo qty=1 listado no marketplace e atrelado ao directo como prémio. B1 recebeu 5 bilhetes. S1 fechou e sorteou. Depois olhámos Hub, stock, encomendas-prémio e tentámos uma compra nova do mesmo SKU.

**Esperado vs resultado**
- Rifa: 1 vencedor B1 rank=1 → visto **drawn** (`winners_n=1`)
- Encomenda-prémio: esperado 1 linha `premio_rifa` → visto **0** (`prize_orders: []`; o sorteio engole o erro)
- Produto: esperado qty 1→0 ou `is_sold` → visto **qty=1**, `is_sold=false`, `list_on_marketplace=true`
- Hub: esperado ocultar o prémio → visto **1 linha** (anon/JWT)
- Live item: esperado reservado/sold → visto **`available`**
- Nova encomenda do prémio: INSERT **200** (o cadeado de stock **não** trata o vencedor); checkout **429** rate-limit (não é defesa de stock)

**Conclusão:** **P2** — higiene de composição, não P0/P1. Ninguém pagou o prémio duas vezes nesta ronda (o checkout bateu no limite de sessões). O sorteio declara vencedor e o Hub continua a mostrar o artigo como comprável, sem encomenda-prémio. Quem entra pela loja vê um SKU que a rifa já atribuiu.
**Prova:** `pass2.json` B4r + `confirm_b.json` (SKU Hub n=1, `prize_orders_n=0`, insert de compra após draw).

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | superfícies tocadas | acção | HTTP | oráculos multi-sítio | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|---------------------|-------|------|----------------------|------------------|--------------|
| A1 | Hub + CPI + tip + wallet | unpublish mid-checkout **e** mid-tip + payout | CPI 200 `cs_test_a1boBvPE…`; unpub RPC 200; tip GET unpaid; connect 200 `tr_1UCid9…` | Hub mid n=0; tip `pending`; Δwallet −1€ = saldo existente; S1 restored `true` | FAIL (P0 retractado) | SIM |
| A2 | Hub + products + orders | sold+listed vs vitrine vs insert | Hub 200 []; insert 400 `order_hold_exceeds_stock` | sold+listed; Hub 0; sem encomenda | FAIL residual | NÃO |
| A3 | Hub + orders + CPI | leftover após pago parcial qty 2→1 | e2e 200 `pi_3UCidC…`; Hub 200 1 linha; CPI leftover `cs_test_a1bmmR8…` | status `pago`; qty=1; Hub n=1; leftover comprável | FAIL | NÃO |
| A4 | favorites + Hub + CPI hold | favorite + checkout hold qty=1 + 2.º buyer | fav 201; CPI B1 200 `cs_`; B2 insert 400 hold | Hub n=0 após claim; fav 1; ≤1 cs_ | FAIL | SIM |
| B1 | live accept + bag **outra** linha + Hub | accept hitch SKU-A + bag SKU-B | accept 200 accepted; bag 200 `cs_test_a1iEfjNm…` | A accepted; B abre Session; Hub A/B n=0 (claim) | FAIL | SIM |
| B2 | convert + Hub + chat card + order | pago Stripe + hitch convert/reconcile + card | e2e 200 `pi_3UCidO…`; convert 403; reconcile 403 `convert_requires_paid_order`; card 201 | res `pending`; Hub n=0 qty=0; order `pago`; card ok | FAIL | SIM |
| B3 | end_live ∥ bag CPI ∥ Hub | Future.wait end ∥ bag ∥ hub | pass1 JWT PATCH lives 403; pass2 service end 200 + bag `cs_test_a1iazCX…` | live `ended`; bag cs_; Hub SKU n=0; Hub live by-id ainda 1 (gravado — não conta) | FAIL | NÃO |
| B4 | rifa + Hub + products + prize order | award + draw winner vs stock marketplace | award 200 tickets=5; draw 200 `drawn` `prize_orders:[]` | winner 1; qty 1→1; Hub n=1; prize 0; item `available` | **HOLD P2-1** | SIM |
| C1 | offer + CPI + Hub + orders | oferta 8€ aceite + CPI amount=1 | offer 201; accept 200; CPI 200 selo **905¢** | offer accepted 8€; Hub n=1; underpay ignorado | FAIL | SIM |
| C2 | bundle + single overlap | Future.wait bag bundle ∥ single mesma linha | pass1 single insert 400 hold (qty=1); pass2 inserts 200 + CPI **429** | bundle accepted; ≤1 cs_ (0); overlap bloqueado no hold | FAIL | SIM |
| C3 | chat card + order amount | pago + card canónico vs amount hostil | e2e 200 `pi_3UCide…`; cards 201; amount_paid **590** | status `pago`; hostil persistiu; ledger inalterado | FAIL | NÃO |
| C4 | orders + wallet | seller/buyer PATCH pago sem Stripe | buyer 403 `order_status_requires_capture`; seller 403 `order_money_fields_immutable` | status `reserva_pendente`; amount_paid null; Δwallet 0 | FAIL | NÃO |
| D1 | refund ∥ CPI leftover | Future.wait refund pago ∥ CPI leftover | rf 200 `re_3UCidk…` cancelado; CPI 200 `cs_test_a1P00nRe…` | qty 1→2; old cancelado; new `reserva_pendente` | FAIL residual | NÃO |
| D2 | release ∥ disputa | Future.wait release + POST disputa | release 200 `false`; disputa 403 RLS | Δwallet 0; status `pago`; sem crédito | FAIL | SIM |
| D3 | 2 buyers Hub visível + CPI | 2 insert+CPI qty=1 Hub | pass1 2.º insert 400 hold; pass2 o2 400, Hub após hold n=0; CPI 429 | Hub inicial n=1; ≤1 encomenda; 2.º buyer recusado | FAIL | NÃO |
| D4 | Hub + order + wallet + chat | pago 4242 → 4 sítios | e2e 200 `pi_3UCidw…` 590¢ succeeded | status `pago` qty 2→1; Hub leftover n=1; Δwallet 0/0; chat 0 (e2e) | FAIL | NÃO |

Linhas na tabela: **16**. Stripe TEST pago: **sim**. Residual clássico A2 sold + D1 refund∥leftover = 2/16 ≪ 40%. **Não** ATROFIA_ABORT. Classes novas: A1 tip+payout+unpublish · A4 favorite+hold · B1 outra linha · B2 convert+chat · B4 rifa+Hub · C1 oferta+Hub · C2 bundle overlap · D2 release∥disputa (**8 ≥ 3**). Races: B3, C2, D1, D2, D3 (**≥4**).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (C1 selo 905¢ vs body 1)
10. Buyer manipula qty autoritativa — NÃO (holds `order_hold_exceeds_stock`)
11. Seller falsifica pagamento plataforma — NÃO (C4 PATCH 403)
12. JWT cria saldo/fundos — NÃO (tip pending; Δwallet 0 no pago até release)
13. Refund excede captura — NÃO (D1 idempotente 590¢)
14. Release+refund cria dinheiro líquido — NÃO (D2 release false, Δ=0)
15. Payout duplica Transfer — NÃO (A1 1× `tr_1UCid9` 100¢, balance_after=1)
16. Stock=1 duas vendas válidas — NÃO (A4/D3 2.º insert 400)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da matriz)
24. RPC SECURITY DEFINER perigoso executável — NÃO (convert 403)
25. RLS crítico quebrado — NÃO (disputa 42501; PATCH lives JWT 403)
26. Edge confia total do cliente — NÃO (C1 selo; off-platform não exercitado)
27. Regressão funcional (happy path partido) — NÃO (A3 leftover; D4 pago; C1 offer)
28. Saturação atingida — NÃO (P2 aberto na rifa vs Hub)

Poços DS: hub=SIM · live=SIM · chat=SIM · wallet=SIM · race=SIM · offer=SIM · published=SIM · caixa=SIM  
ATROFIA: NÃO (2/16 residual; ângulo novo = rifa winner vs vitrine marketplace)  
Pagamento TEST: **pago** (vários PI `succeeded`). Chat card após e2e: canónico 201; hostil 201 **sem** alterar `amount_paid_cents` (não conta).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

### P2-1 `P2-B4-RAFFLE-HUB` (DS2)

Ver secção acima. Único finding aberto. IDs: **P2-1**. Soma P2 `quantos` = 1.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| P0-A1-PAYOUT pass1 | **Retractado.** `create-connect-account` 200 `tr_1UCid9` 1,00 € `transferred` `balance_after=1` — levantamento do saldo já existente. Tip ficou `pending`. Hub unpublished não congela Connect. |
| Hub hide live accepted clássico | **Não exercitado como finding.** B1 accept A + bag B (outra linha). |
| MB WAY exact 400 | **Não exercitado** (anti-atrofia). |
| follow published 403 | **Não exercitado** (anti-atrofia). |
| 4∥2 ≤1 cs_ | **Não exercitado** (anti-atrofia). C2 é bundle∥single overlap, não 4∥2. |
| C3 card hostil amount=0.01 | Persistiu; `amount_paid_cents=590` inalterado — cards não liquidam. |
| B3 Hub lives by-id após ended | Linha ainda visível em `hub_lives_public` (possível Gravados). Sem prova de player “ao vivo”. Não conta. |
| C2r/D3r CPI 429 | Rate-limit de Sessions; defesa de stock já vista no insert 400. |

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------

| Lente | Evidência |
|-------|-----------|
| DS1 hub | A2 sold oculto; A3 leftover visível; A4 Hub n=0 após claim; D3r Hub n=0 após hold |
| DS2 live | B1 accept≠bag B; B2 convert 403; **P2-1 rifa vs Hub**; B3r end∥bag |
| DS3 chat | C3 card vs amount_paid 590; B2 card 201 |
| DS4 wallet | D2 release false Δ=0; A1r ledger 100¢ |
| DS5 race | B3, C2, D1, D2, D3 |
| DS6 offer | C1 selo 905¢; C2 bundle accepted |
| DS7 published | A1 unpublish Hub n=0; tip pending |
| DS8 caixa | D4 pago 590¢ 4 sítios; C4 PATCH 403 |

--------------------------------------------------
## FIO (Hub + live + chat + wallet + caixa)
--------------------------------------------------

Unpublish + tip + payout (A1) → sold vs Hub (A2) → leftover pago (A3) → favorite+hold (A4) → accept live **outra** linha (B1) → convert+card (B2) → end∥bag∥Hub (B3) → rifa+Hub (**P2-1**) → oferta underpay (C1) → bundle∥single (C2) → chat vs pago (C3) → PATCH pago (C4) → races D1–D4.

--------------------------------------------------
## OPERAÇÃO
--------------------------------------------------

- Lives criadas: `ended` / `is_active=false` (pass1 finally + pass2).
- S1 `hub_published=true` à saída (RPC `batata_publish_hub`).
- **NÃO CORRIGIR.** Fase 4 não.

```
AUDITOR: REDTEAM_BLIND_DS_COMPOSICAO_POS_DHDM_v1
probes_na_tabela: 16 · classes_novas: 8
VEREDICTO: FAIL_P2
```

RESUMO_NUMERICO: P0=0 P1=0 P2=1 P3=0 TOTAL=1
