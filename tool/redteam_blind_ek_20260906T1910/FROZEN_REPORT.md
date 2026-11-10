# FROZEN_REPORT — RED TEAM CEGO EK · Composição multi-sítio · POS_OPEN_MVP

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 3
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 3

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? SIM
4. Quantos P1: 3
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_EK_COMPOSICAO_POS_OPEN_v1
FROZEN_AT: 2026-09-06T19:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EK1, EK2, EK3, EK4, EK5, EK6, EK7, EK8]
probes_na_tabela: 18
classes_novas: 12
races: 8
stripe_test_pago: true
VEREDICTO: FAIL_P1
prefix: RTEK-20260906T1910
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded`: `pi_3UCkZc*`, `pi_3UCkbA*`, `pi_3UCkbQ*`, `pi_3UCkbV*`, `pi_3UCkbZ*`, `pi_3UCkbg*`; saco `setup_paid_bag` `pi_3UCkbM*` 1115¢) · actores JWT B1/S1/B2/B3/S2 · `service_role` só fixture / observação / restore. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

S1 `980f4fa1-…` `hub_published=true` à saída. Lives de fixture `ended` / `is_active=false`. B3 fresco `b8b912ae-…` para CPI de saco.

Cruzamentos **pack POS_OPEN:** **6∥4 + Hub leftover após pago** · **expand subset→superset** · **bag∥single + Hub** · saco pago único 4 sítios. **Não** se repetiu 4∥2 / Hub hide live accepted clássico / MB WAY exact / buyer refund 403.

Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem retrieve nativo `status=open`. Prova de *open/payable* = **2× HTTP 200** + **2 `cs_test_` distintas** + `reused=false`. **Não pagámos as duas.**

--------------------------------------------------
## P1-1 — Saco de 6 e saco de 4 ao mesmo tempo: dois links de pagamento (Hub leftover coerente)

**O que isto é:** o comprador pede o pagamento de um saco com 6 artigos e, no mesmo instante, um saco só com 4 desses artigos. Depois de uma compra Stripe já paga (sobra 1 unidade na loja), o cadeado do saco tinha de entregar no máximo um link útil.

**Quem / onde:** Comprador B3 · Vendedor S1 · leftover pago B1 (Hub n=1, qty=1) · 6 linhas novas B3.

**O que fizemos:**
- Pago Stripe TEST qty 2→1 (`pi_3UCkbAH7FWYUN3jh0owYk9m2`) — loja ainda mostra a unidade que sobra.
- Seis encomendas B3. `Future.wait` saco ABCDEF ∥ saco BCDE.
- Confirm: outra ronda, mesmos 2 links, `reused=false`, Hub das 6 linhas n=1.

**Esperado vs resultado**
- API: esperado ≤1 `cs_` útil · visto **2** `cs_test_` distintas, ambas HTTP 200, `reused=false` (pass1 `a1kQk0Qe…` + `a1sExFLS…`; confirm `a1T831ol…` + `a1H7TtVl…`)
- Ledger confirm: as 6 linhas = Session do saco de 6; a Session de 4 ficou órfã
- Loja (Hub leftover pago): esperado n=1 qty=1 · visto **n=1 qty=1** (coerente)
- Stripe: sem `sk_test_` local — **não pagámos as duas**

**Conclusão:** **P1** — o cliente recebeu dois links; uma Session ficou órfã. O cadeado POS_OPEN **não** impede 6∥4. Não é P0: não pagámos as duas. A loja da compra já paga manteve-se coerente.
**Prova:** `pass1.json` B1 + `confirm.json` b1.

--------------------------------------------------
## P1-2 — Encolher depois expandir o saco (2 artigos → 4): dois links, o menor não expira

**O que isto é:** o comprador começa o pagamento de 2 artigos e, 50 ms depois, pede o pagamento dos 4 (o saco cresceu). Só o link final deveria ficar pagável; o primeiro tinha de expirar.

**Quem / onde:** Comprador B3 · 4 artigos qty=2.

**O que fizemos:** `Future.wait` saco AB t=0 ∥ sleep 50 ms saco ABCD. Confirm repetiu.

**Esperado vs resultado**
- API: esperado 1 `cs_` (superset) e subset expired · visto **2** `cs_test_` (`a1Aok1bG…` + `a1P7tczx…`; confirm `a1F52o8n…` + `a1ziqIsI…`), `reused=false`
- Ledger confirm: as 4 linhas = Session do **superset**; subset órfã (não expirou)
- Loja: 4 SKUs ainda visíveis (qty=2) — sem oversell visível

**Conclusão:** **P1** — expand subset→superset continua a criar uma Session órfã pagável no cliente. Não pagámos as duas.
**Prova:** `pass1.json` B2 + `confirm.json` b2.

--------------------------------------------------
## P1-3 — Saco de 3 e pagamento avulso da linha do meio: dois links

**O que isto é:** o comprador pede ao mesmo tempo o pagamento do saco completo (3 artigos) e o pagamento só do artigo do meio. O cadeado tinha de entregar no máximo um link.

**Quem / onde:** Comprador B3 · 3 SKUs qty=2, Hub visíveis.

**O que fizemos:** `Future.wait` saco ABC ∥ CPI avulso da linha B. Confirm repetiu.

**Esperado vs resultado**
- API: esperado ≤1 `cs_` · visto **2** `cs_test_` (pass1 `a1j2Uhp9…` + `a115APDR…`; confirm `a1JDCuUQ…` + `a1XPitkY…`), `reused=false`
- Ledger: as 3 linhas = Session do **saco**; o avulso ficou órfão
- Loja: Hub n=1 nas 3 linhas (hold, sem oversell visível)

**Conclusão:** **P1** — bag∥single no fio de composição (com Hub) entrega dois links. Não pagámos as duas.
**Prova:** `pass1.json` B3 + `confirm.json` b3.

--------------------------------------------------
## TABELA DE PROVAS (18)
--------------------------------------------------

| probe_id | superfícies tocadas | acção | HTTP | oráculos multi-sítio | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|---------------------|-------|------|----------------------|------------------|--------------|
| A1 | Hub + CPI + tip + wallet | unpublish mid-checkout **e** mid-tip + payout | unpub 200; tip pending; connect 200 | Hub mid n=0; tip `pending`; Δwallet −1€ saldo existente; S1 restored `true` | FAIL | SIM |
| A2 | Hub + orders + CPI leftover | leftover após pago parcial qty 2→1 | e2e 200 `pi_3UCkZc…`; Hub 200 1 linha; leftover `cs_test_a1imo5da…` | status `pago`; qty=1; Hub n=1; leftover comprável | FAIL | NÃO |
| A3 | follows + favorites + Hub + hold | favorite + hold qty=1 + 2.º buyer | fol 409 duplicate; fav 201; B2 insert 400 hold | Hub n=0; fav 1; follow 1; ≤1 dono | FAIL | SIM |
| A4 | rifa + Hub + live_item + insert | draw + Hub + live_item ≠ available | draw 200 `drawn`; insert 400 hold | winner 1; qty 0; Hub n=0; item **`sold`** `is_active=false` | FAIL | SIM |
| A5 | Hub + products + orders | sold+listed vs vitrine vs insert | Hub 200 []; insert 400 `order_hold_exceeds_stock` | sold+listed; Hub 0; sem encomenda | FAIL residual | NÃO |
| B1 | bag 6∥4 + Hub leftover + orders | **6∥4** após 1 pago leftover | 2× 200 `cs_`; leftover Hub n=1 | **2 cs_**; ledger=saco6; órfã saco4; leftover coerente | **HOLD** | SIM |
| B2 | bag expand + Stripe + Hub | subset AB →50ms superset ABCD | 2× 200 `cs_`; ledger=superset | **2 cs_**; subset órfã não expired | **HOLD** | SIM |
| B3 | bag + single CPI + Hub + orders | **bag ABC ∥ avulso B** | 2× 200 `cs_`; Hub n=1×3 | **2 cs_**; ledger=saco; órfã single | **HOLD** | SIM |
| B4 | Hub + order + chat + wallet | bag pago único 4242 → 4 sítios | e2e 200 `pi_3UCkbM…` 1115¢; ambas `pago` | paidA 335 + paidB 780 = PI; Hub leftover n=1+1; qty 3→2; Δwallet 0/0 | FAIL | SIM |
| C1 | rifa + accept A + bag B + Hub | rifa activa A + hitch A + bag B | accept 200; bag `cs_test_a1EQrUHj…` | A accepted; B abre Session; Hub A/B n=0 | FAIL | SIM |
| C2 | offer + CPI + Hub + orders | oferta 8€ aceite + CPI amount=1 | CPI 200 selo **905¢** | offer accepted 8€; Hub n=1; underpay ignorado | FAIL | SIM |
| C3 | release∥disputa + chat + wallet | Future.wait release + POST disputa + card | release 200 true; disputa 201 `aberta` | Δ snapshot 0; 1 efeito líquido; status `concluido` | FAIL | SIM |
| C4 | storage + disputa + proof_ok + reply | revoke proof mid-disputa + UI path | disp 201; rev true; **proof_ok false**; reply recusado | auth 400; UI recusa URL morta | FAIL | SIM |
| C5 | rifa draw ∥ CPI + Hub | Future.wait draw ∥ CPI B2 qty=1 | draw 200 `drawn`; CPI 400 `product is marked sold` | winner 1; qty 0; Hub n=0; sem 2 donos | FAIL | SIM |
| D1 | 2 buyers Hub + CPI qty=1 | Future.wait B2∥B3 CPI | Hub inicial n=1; 2.º insert 400 hold; 1 cs_ | Hub após hold n=0; ≤1 encomenda | FAIL | NÃO |
| D2 | refund ∥ CPI leftover | Future.wait refund pago ∥ CPI leftover | rf 200 `re_3UCkbZ…` cancelado; CPI leftover `cs_` | qty 1→2; old cancelado; new `reserva_pendente` | FAIL residual | NÃO |
| D3 | end_live ∥ bag CPI ∥ Hub | Future.wait end ∥ bag ∥ hub | end 200 ended; bag `cs_test_a1AMtYGE…` | live `ended`; Hub SKU n=0; Hub live by-id 1 | FAIL | NÃO |
| D4 | Hub + order + wallet + chat | pago 4242 → 4 sítios | e2e 200 `pi_3UCkbg…` 590¢ succeeded; card 201 | status `pago` qty 2→1; Hub leftover n=1; Δwallet 0/0; chat 1 | FAIL | NÃO |

Linhas na tabela: **18**. Stripe TEST pago: **sim**. Residual clássico A5 sold + D2 refund∥leftover = 2/18 = 11% ≪ 40%. **Não** ATROFIA_ABORT. Classes novas: A1 tip+unpublish · A3 fav+hold · A4 live_item sold · **B1 6∥4+Hub** · **B2 expand** · **B3 bag∥single+Hub** · **B4 bag pago 4 sítios** · C1 rifa+bag · C2 oferta selo · C3 release∥disputa · C4 revoke mid-disputa · C5 rifa∥CPI (**12 ≥ 4**). Races: B1, B2, B3, C3, C5, D1, D2, D3 (**8 ≥ 5**).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 3
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (C2 selo 905¢ vs body 1)
10. Buyer manipula qty autoritativa — NÃO (holds `order_hold_exceeds_stock`)
11. Seller falsifica pagamento plataforma — NÃO (C4 storage)
12. JWT cria saldo/fundos — NÃO (C3 Δ 0; D4/B4 Δ 0 até release)
13. Refund excede captura — NÃO (D2 idempotente 590¢)
14. Release+refund cria dinheiro líquido — NÃO (C3 net 0)
15. Payout duplica Transfer — NÃO (A1 1× débito de saldo existente)
16. Stock=1 duas vendas válidas — NÃO (A3/D1/C5 2.º recusado)
17. Stock=1 duas capturas líquidas permanentes — NÃO (2 `cs_` órfãs **não pagas**)
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (C4 reply recusado)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da matriz)
24. RPC SECURITY DEFINER perigoso executável — NÃO
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (C2 selo 905¢)
27. Regressão funcional (happy path partido) — NÃO (A2 leftover; B4 bag pago 4 sítios; D4 pago 4 sítios; C2 offer; C1 bag B)
28. Saturação atingida — NÃO (P1 abertos; quota e classes novas cumpridas)

Poços EK: hub=SIM · live=SIM · chat=SIM · wallet=SIM · race=SIM · bag=SIM · rifa=SIM · caixa=SIM  
ATROFIA: NÃO (2/18 residual; ângulos novos = 6∥4+Hub, expand, bag∥single+Hub, bag pago 4 sítios)  
Pagamento TEST: **pago** (vários PI `succeeded` + saco 1115¢).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

| ID | Severidade | Título |
|----|------------|--------|
| P1-1 | P1 | P1-B1-64-BAG-HUB — 6∥4 duas Sessions úteis |
| P1-2 | P1 | P1-B2-EXPAND-OPEN — expand duas Sessions; subset não expira |
| P1-3 | P1 | P1-B3-BAG-SINGLE-HUB — bag∥single duas Sessions úteis |

Soma P0+P1+P2+P3 `quantos` = 3.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A1 payout unpublished | **Não mint.** Connect 200 debitou 1,00 € de saldo já existente; tip `pending`. Anti-atrofia. |
| Hub hide live accepted clássico | **Não exercitado como finding.** C1: accept A + bag B abre `cs_`. |
| Hub hide rifa drawn qty=1 | **Hub n=0** após draw (A4/C5). Item `sold`+inactivo — não contar. |
| MB WAY exact 400 | **Não exercitado** (anti-atrofia). |
| 4∥2 ≤1 cs_ | **Não exercitado** (substituído por 6∥4, expand, bag∥single). |
| buyer refund 403 | **Não exercitado** (anti-atrofia). |
| C3 release∥disputa 1 efeito | Race API: release `true` **e** disputa `aberta`. Δ wallet **0**. **1 efeito dinheiro** — anti-atrofia, não contar. |
| B4 chat card 400 | Ambas linhas `pago`, Hub leftover, Δwallet 0. Card 400 não é dinheiro; não contar. |
| D3 Hub lives by-id após ended | Linha visível em `hub_lives_public` (possível Gravados). Sem player “ao vivo”. Não conta. |
| A4 prize_orders [] | Draw sem encomenda-prémio; Hub+live_item+stock selados. |

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------

| Lente | Evidência |
|-------|-----------|
| EK1 hub | A5 sold oculto; A2 leftover visível; A3 Hub n=0 após claim; A4 Hub n=0 após draw; D1 Hub n=0 após hold |
| EK2 live | C1 accept≠bag B; D3 end∥bag; A4 live_item `sold` |
| EK3 chat | D4 card 201; C4 reply recusado após revoke |
| EK4 wallet | C3 Δ=0; A1 débito saldo existente; D4/B4 Δ 0/0 até release |
| EK5 race | B1, B2, B3, C3, C5, D1, D2, D3 |
| EK6 bag | B1 6∥4; B2 expand; B3 bag∥single; B4 bag pago |
| EK7 rifa | A4 item sold+Hub 0; C5 draw∥CPI sold |
| EK8 caixa | D4 pago 590¢ 4 sítios; B4 saco 1115¢ proporcional; D2 refund 590¢ |

--------------------------------------------------
## FIO (Hub + live + chat + wallet + caixa)
--------------------------------------------------

Unpublish + tip + payout (A1) → leftover pago (A2) → favorite+hold (A3) → rifa+live_item sold (A4) → sold vs Hub (A5) → rifa+accept A + bag B (C1) → **bag∥single+Hub (B3 P1)** → end∥bag∥Hub (D3) → rifa∥CPI (C5) → **6∥4+Hub pago (B1 P1)** → oferta underpay (C2) → **bag pago 4 sítios (B4)** → release∥disputa (C3) → revoke mid-disputa (C4) → refund∥leftover (D2) → 2 buyers (D1) → pago 4 sítios (D4) → **expand (B2 P1)**.

--------------------------------------------------
## GATE ABERTURA
--------------------------------------------------

`PASS_CEGO_SATURADO` aqui **e** EF/EG sem P0–P2 → candidato a abrir a todos.  
**Este relatório:** P1 bag dual open (6∥4, expand, bag∥single) → **NÃO ABRIR**.

--------------------------------------------------
## OPERAÇÃO
--------------------------------------------------

- Lives criadas: `ended` / `is_active=false` (finally pass1 + confirm).
- S1 `hub_published=true` à saída (RPC `batata_publish_hub`).
- Pasta: `tool/redteam_blind_ek_20260906T1910/` (`pass1.json`, `confirm.json`).
- **NÃO CORRIGIR.** Fase 4 não.

```
AUDITOR: REDTEAM_BLIND_EK_COMPOSICAO_POS_OPEN_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 18 · classes_novas: 12 · races: 8
VEREDICTO: FAIL_P1
```

RESUMO_NUMERICO: P0=0 P1=3 P2=0 P3=0 TOTAL=3
