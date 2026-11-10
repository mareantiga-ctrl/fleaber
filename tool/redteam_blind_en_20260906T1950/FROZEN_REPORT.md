# FROZEN_REPORT — RED TEAM CEGO EN · Saco + Hub + composição · RETESTE POS_OPEN_GATE

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 1

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? SIM
4. Quantos P1: 1
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_EN_BAG_COMPOSICAO_RETEST_POS_OPEN_v1
FROZEN_AT: 2026-09-06T19:58:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EN1, EN2, EN4, EN5, EN6, EN7, EN8]
probes_na_tabela: 14
classes_novas: 12
races: 7
stripe_test_pago: true
VEREDICTO: FAIL_P1
prefix: RTEN-20260906T1950
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded`: `pi_3UClEB*`, `pi_3UClFb*`, `pi_3UClFf*`; saco `setup_paid_bag` `pi_3UClFU*` 1115¢) · actores JWT B1/S1/B2/B3 · `service_role` só fixture / observação / restore. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

S1 `980f4fa1-…` `hub_published=true` à saída. Lives de fixture `ended` / `is_active=false`. B3 fresco `8b2fd649-…` para CPI de saco.

Reteste EK no fio composição **com** Hub leftover: **6∥4** e **expand** fecharam (400 `overlapping bag session`, 1 `cs_`). **bag∥single** continua a entregar **2** `cs_test_` distintas, `reused=false`. Confirm repetiu. **Não** pagámos as duas.

Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem retrieve nativo `status=open`. Prova de *open/payable* no A3 = **2× HTTP 200** + **2 `cs_test_` distintas** + `reused=false`.

--------------------------------------------------
## P1-1 — Saco de 3 e pagamento avulso da linha do meio: dois links

**O que isto é:** o comprador pede ao mesmo tempo o pagamento do saco completo (3 artigos) e o pagamento só do artigo do meio. O cadeado fail-closed tinha de entregar no máximo um link.

**Quem / onde:** Comprador B3 · Vendedor S1 · 3 SKUs qty=2 visíveis na loja (Hub n=1).

**O que fizemos:**
- `Future.wait` saco ABC ∥ CPI avulso da linha B.
- Confirm: outra ronda, mesmos 2 links, `reused=false`, Hub das 3 linhas n=1.

**Esperado vs resultado**
- API: esperado ≤1 `cs_` útil (200+400 ou reused) · visto **2** `cs_test_` distintas, ambas HTTP 200, `reused=false` (pass1 `a1t3Sv4j…` + `a16qvkig…`; confirm `a1vlEloa…` + `a1CtwG5q…`)
- Ledger confirm: as 3 linhas = Session do **saco**; a Session avulsa ficou órfã
- Loja: Hub n=1 nas 3 linhas (hold, sem oversell visível)
- Stripe: sem `sk_test_` local — **não pagámos as duas**

**Conclusão:** **P1** — bag∥single no fio de composição (com Hub) entrega dois links. O cadeado POS_OPEN cobre overlap de sacos (6∥4 / expand / shrink) mas **não** o CPI avulso em paralelo. Não é P0: não pagámos as duas.
**Prova:** `pass1.json` A3 + `confirm.json` a3.

--------------------------------------------------
## TABELA DE PROVAS (14)
--------------------------------------------------

| probe_id | superfícies tocadas | acção | HTTP | oráculos multi-sítio | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|---------------------|-------|------|----------------------|------------------|--------------|
| A1 | bag 6∥4 + Hub leftover + orders | **6∥4** após 1 pago leftover | bag6 **400** overlapping; bag4 200 1 `cs_`; leftover `pi_3UClEB…` | leftover Hub n=1 qty=1; confirm 400+200 `cs_n=1` | FAIL | SIM |
| A2 | bag expand + Hub + Session | subset AB →50ms superset ABCD | sub 200 1 `cs_`; super **400** overlapping | Hub n=1×4; confirm 200+400 `cs_n=1` | FAIL | SIM |
| A3 | bag + single CPI + Hub + orders | **bag ABC ∥ avulso B** | **2× 200** `cs_`; `reused=false` | **2 cs_**; ledger=saco; órfã single; Hub n=1×3; confirm `cs_n=2` | **HOLD** | SIM |
| A4 | bag shrink + Hub + Session | full ABCD →50ms subset AB | full **400** overlapping; small 200 1 `cs_` | Hub n=1×4; confirm 400+200 `cs_n=1` | FAIL | SIM |
| A5 | bag idêntico + Hub | 2× mesmo saco ABC | 2× 200 **1** `cs_` reused | sids=1; reused [true,false]; Hub n=1×3 | FAIL | SIM |
| B1 | Hub + 2 buyers CPI qty=1 | Future.wait B2∥B3 | Hub0 n=1; 2.º insert 400 hold; 1 `cs_` | Hub após n=0; o2 null; ≤1 encomenda | FAIL | NÃO |
| B2 | rifa + Hub + live_item + insert | draw + Hub + live_item ≠ available | draw 200 `drawn`; insert 400 hold | winner 1; qty 0; Hub n=0; item **`sold`** `is_active=false` | FAIL | SIM |
| B3 | rifa + accept A + bag B + Hub | hitch A + bag B | accept 200; bag `cs_test_a1SQaNvF…` | A accepted; B abre Session; Hub A/B n=0 | FAIL | SIM |
| B4 | Hub + CPI ∥ unlist | Future.wait CPI ∥ unlist qty=0 | CPI **400** not listed; patch 200 | listed false; qty 0; Hub n=0; sem `cs_` | FAIL | SIM |
| C1 | Hub + order + chat + wallet | bag pago único 4242 → 4 sítios | e2e 200 `pi_3UClFU…` 1115¢; ambas `pago` | paidA 335 + paidB 780 = PI; Hub leftover n=1+1; qty 3→2; Δwallet 0/0 | FAIL | SIM |
| C2 | offer + CPI + Hub + orders | oferta 8€ aceite + CPI amount=1 | CPI 200 selo **905¢** | offer accepted 8€; Hub n=1; underpay ignorado | FAIL | SIM |
| C3 | release∥disputa + wallet + Hub | Future.wait release + POST disputa | release 200 true; disputa 201 `aberta` | Δ snapshot 0; 1 efeito líquido; status `concluido`; Hub n=1 | FAIL | SIM |
| C4 | Hub + orders + CPI leftover | leftover após pago qty 2→1 | e2e 200 `pi_3UClFf…`; leftover `cs_test_a1484E6w…` | status `pago`; qty=1; Hub n=1; leftover comprável | FAIL | NÃO |
| C5 | orders + CPI denylist | **bizum** sem `cs_` | **400** off-platform | pm `bizum`; sid null | FAIL | SIM |

Linhas na tabela: **14**. Stripe TEST pago: **sim**. Residual clássico B1 2 buyers + C4 leftover = 2/14 = 14% ≪ 40%. **Não** ATROFIA_ABORT. Classes novas: A1 6∥4+Hub · A2 expand · **A3 bag∥single** · A4 shrink · A5 idêntico · B2 live_item sold · B3 hitch+bag · B4 unlist∥CPI · C1 bag pago 4 sítios · C2 oferta selo · C3 release∥disputa · C5 bizum (**12 ≥ 4**). Races: A1, A2, A3, A4, B1, B4, C3 (**7 ≥ 4** bag races A1–A4).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (C2 selo 905¢ vs body 1)
10. Buyer manipula qty autoritativa — NÃO (B1 hold `order_hold_exceeds_stock`)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (C3 Δ 0; C1 Δ 0/0 até release)
13. Refund excede captura — NÃO (fora da matriz EN)
14. Release+refund cria dinheiro líquido — NÃO (C3 net 0)
15. Payout duplica Transfer — NÃO (fora da matriz)
16. Stock=1 duas vendas válidas — NÃO (B1 2.º recusado)
17. Stock=1 duas capturas líquidas permanentes — NÃO (2 `cs_` órfãs **não pagas**)
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da matriz)
24. RPC SECURITY DEFINER perigoso executável — NÃO
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (C2 selo 905¢; C5 bizum 400)
27. Regressão funcional (happy path partido) — NÃO (C1 bag pago 4 sítios; C4 leftover; A1 leftover Hub; A5 reuse)
28. Saturação atingida — NÃO (P1 aberto; quota e classes novas cumpridas)

Poços EN: hub=SIM · live=SIM · chat=SIM (card 400, não dinheiro) · wallet=SIM · race=SIM · bag=SIM · rifa=SIM · caixa=SIM  
ATROFIA: NÃO (2/14 residual; ângulos novos = shrink, idêntico, unlist∥CPI, bizum denylist, bag∥single ainda aberto)  
Pagamento TEST: **pago** (vários PI `succeeded` + saco 1115¢).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

| ID | Severidade | Título |
|----|------------|--------|
| P1-1 | P1 | P1-A3-BAG-SINGLE-HUB — bag∥single duas Sessions úteis |

Soma P0+P1+P2+P3 `quantos` = 1.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A1 6∥4 dual | **Fechado.** 400+200; leftover Hub n=1 qty=1. Confirm `cs_n=1`. |
| A2 expand dual | **Fechado.** 200+400 overlapping. Confirm `cs_n=1`. |
| A4 shrink dual | **Fechado.** 400+200; 1 `cs_`. Confirm `cs_n=1`. |
| A5 2× idêntico | **1 `cs_` reused.** Não contar. |
| C5 bizum | **400** off-platform; sem `cs_`. Denylist OK — não P2. |
| C3 release∥disputa 1 efeito | Race API: release `true` **e** disputa `aberta`. Δ wallet **0**. **1 efeito dinheiro** — anti-atrofia, não contar. |
| C1 chat card 400 | Ambas linhas `pago`, Hub leftover, Δwallet 0. Card 400 não é dinheiro; não contar. |
| B2 Hub hide rifa drawn | **Hub n=0** + live_item `sold`+inactivo + insert 400. Anti-atrofia clássico, não contar. |
| B1 2 buyers qty=1 | 2.º insert 400 hold; 1 `cs_`. Residual, não contar. |

--------------------------------------------------
## LENTES (≥6)
--------------------------------------------------

| Lente | Evidência |
|-------|-----------|
| EN1 hub | C4 leftover visível n=1; A1 leftover n=1 qty=1; B1 Hub n=0 após hold; B4 Hub n=0 após unlist |
| EN2 live | B3 accept A ≠ bag B abre `cs_` |
| EN4 wallet | C3 Δ=0; C1 Δ 0/0 até release |
| EN5 race | A1, A2, A3, A4, B1, B4, C3 |
| EN6 bag | A1 6∥4 fechado; A2 expand fechado; **A3 bag∥single P1**; A4 shrink fechado; A5 reuse |
| EN7 rifa | B2 item sold+Hub 0+insert 400 |
| EN8 caixa | C1 saco 1115¢ proporcional; C4 leftover 2→1; C2 selo 905¢ |

--------------------------------------------------
## FIO (Hub + live + saco + caixa)
--------------------------------------------------

**6∥4+Hub leftover (A1 fechado)** → **expand (A2 fechado)** → **bag∥single+Hub (A3 P1)** → shrink (A4 fechado) → idêntico reuse (A5) → 2 buyers (B1) → rifa+live_item sold (B2) → hitch A + bag B (B3) → unlist∥CPI (B4) → **bag pago 4 sítios (C1)** → oferta underpay (C2) → release∥disputa (C3) → leftover qty 2→1 (C4) → bizum 400 (C5).

--------------------------------------------------
## GATE
--------------------------------------------------

P0–P2=0 → `PASS_CEGO_SATURADO`. Dual bag → `FAIL_P1`.  
**Este relatório:** dual create no bag∥single → **FAIL_P1** (bloqueia abertura POS_OPEN_GATE).  
6∥4 / expand / shrink / idêntico / bizum: fail-closed como esperado.

--------------------------------------------------
## OPERAÇÃO
--------------------------------------------------

- Lives criadas: `ended` / `is_active=false` (finally pass1 + confirm).
- S1 `hub_published=true` à saída.
- Pasta: `tool/redteam_blind_en_20260906T1950/` (`pass1.json`, `confirm.json`).
- **NÃO CORRIGIR.** Fase 4 não.

```
AUDITOR: REDTEAM_BLIND_EN_BAG_COMPOSICAO_RETEST_POS_OPEN_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 14 · classes_novas: 12 · races: 7
VEREDICTO: FAIL_P1
```

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
