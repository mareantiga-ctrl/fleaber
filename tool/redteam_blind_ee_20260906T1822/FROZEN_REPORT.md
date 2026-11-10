# FROZEN_REPORT — RED TEAM CEGO EE · Composição multi-superfície · POS_DTDY

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 2
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 2

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? SIM
4. Quantos P1: 2
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_EE_COMPOSICAO_POS_DTDY_v1
FROZEN_AT: 2026-09-06T18:36:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EE1, EE2, EE3, EE4, EE5, EE6, EE7, EE8]
probes_na_tabela: 18
classes_novas: 12
races: 8
stripe_test_pago: true
VEREDICTO: FAIL_P1
prefix: RTEE-20260906T1822
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded`: `pi_3UCjuo*`, `pi_3UCjv0*`, `pi_3UCjv8*`, `pi_3UCjvQ*`, `pi_3UCjvV*`, `pi_3UCjvZ*`, `pi_3UCjvh*`, confirm `pi_3UCjxO*`) · actores JWT B1/S1/B2/B3/S2 · `service_role` só fixture / observação / restore. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

S1 `980f4fa1-…` `hub_published=true` à saída. Lives de fixture `ended` / `is_active=false`. B3 fresco `ad3949b7-…` para CPI de saco (evitar tecto do buyer LIVE_OPS).

Cruzamentos **novos vs DY**: rifa+Hub+`live_item≠available` · **6∥4 bag + Hub leftover após pago** · release∥disputa+chat+wallet · revoke mid-disputa + `proof_ok` + reply UI · **expand subset→superset**. **Não** se repetiu 4∥2 / Hub hide live accepted / MB WAY / follow 403 / buyer refund 403.

--------------------------------------------------
## P1-1 — Saco de 6 e saco de 4 ao mesmo tempo: dois links de pagamento (Hub leftover coerente)

**O que isto é:** o comprador pede o pagamento de um saco com 6 artigos e, no mesmo instante, um saco só com 4 desses artigos. Depois de uma compra Stripe já paga (sobra 1 unidade na loja), o cadeado do saco tinha de entregar no máximo um link útil.

**Quem / onde:** Comprador B3 · Vendedor S1 · leftover pago B1 (Hub n=1, qty=1) · 6 linhas novas B3.

**O que fizemos:**
- Pago Stripe TEST qty 2→1 (`pi_3UCjv8H7FWYUN3jh1BVFSRn1`) — loja ainda mostra a unidade que sobra.
- Seis encomendas B3. `Future.wait` saco ABCDEF ∥ saco BCDE.
- Confirm pass2: outra ronda, mesmos 2 links.

**Esperado vs resultado**
- API: esperado ≤1 `cs_` útil · visto **2** `cs_test_` distintas, ambas HTTP 200, `reused=false` (pass1 `a1M7as5a…` + `a1UfPlZM…`; confirm `a15NPFlO…` + `a1fhs3r6…`)
- Ledger: as 6 linhas ficam com a Session do saco de 6; a Session de 4 ficou órfã
- Loja (Hub leftover pago): esperado n=1 qty=1 · visto **n=1 qty=1** (coerente)
- Stripe: sem `sk_test_` local — **não pagámos as duas**

**Conclusão:** **P1** — o cliente recebeu dois links; uma Session ficou órfã. O fecho DTDY do saco (espera + expand re-claim) **não** impede 6∥4. Não é P0: não pagámos as duas. A loja da compra já paga manteve-se coerente.
**Prova:** `pass1.json` B5 + `confirm.json` b5.

--------------------------------------------------
## P1-2 — Encolher depois expandir o saco (2 artigos → 4): dois links, o menor não expira

**O que isto é:** o comprador começa o pagamento de 2 artigos e, 50 ms depois, pede o pagamento dos 4 (o saco cresceu). Só o link final deveria ficar pagável; o primeiro tinha de expirar.

**Quem / onde:** Comprador B3 · 4 artigos qty=2.

**O que fizemos:** `Future.wait` saco AB t=0 ∥ sleep 50 ms saco ABCD. Confirm pass2 repetiu.

**Esperado vs resultado**
- API: esperado 1 `cs_` open (superset) e subset expired · visto **2** `cs_test_` (`a1jjUq3o…` + `a1AezcBa…`; confirm `a1Ly4hvn…` + `a1oh2FqO…`), `reused=false`
- Ledger: as 4 linhas = Session do **superset**; subset órfã (não expirou)
- Loja: 4 SKUs ainda visíveis (qty=2, hold 1) — sem oversell visível

**Conclusão:** **P1** — expand subset→superset continua a criar uma Session órfã pagável no cliente. Não pagámos as duas.
**Prova:** `pass1.json` D4 + `confirm.json` d4.

--------------------------------------------------
## TABELA DE PROVAS (18)
--------------------------------------------------

| probe_id | superfícies tocadas | acção | HTTP | oráculos multi-sítio | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|---------------------|-------|------|----------------------|------------------|--------------|
| A1 | Hub + CPI + tip + wallet | unpublish mid-checkout **e** mid-tip + payout | unpub 200; tip GET unpaid; connect 200 | Hub mid n=0; tip `pending`; Δwallet −1€ saldo existente; S1 restored `true` | FAIL | SIM |
| A2 | Hub + products + orders | sold+listed vs vitrine vs insert | Hub 200 []; insert 400 `order_hold_exceeds_stock` | sold+listed; Hub 0; sem encomenda | FAIL residual | NÃO |
| A3 | Hub + orders + CPI | leftover após pago parcial qty 2→1 | e2e 200 `pi_3UCjuo…`; Hub 200 1 linha; CPI leftover `cs_test_a11UNL9z…` | status `pago`; qty=1; Hub n=1; leftover comprável | FAIL | NÃO |
| A4 | follows + favorites + Hub + hold | favorite + hold qty=1 + 2.º buyer | fol 409 duplicate; fav 201; B2 insert 400 hold | Hub n=0; fav 1; follow 1; ≤1 dono | FAIL | SIM |
| A5 | rifa + Hub + live_item + insert | draw + Hub + live_item ≠ available | draw 200 `drawn`; insert 400 hold | winner 1; qty 0; Hub n=0; item **`sold`** `is_active=false` | FAIL | SIM |
| B1 | rifa + accept A + bag B + Hub | rifa activa A + hitch A + bag B | accept 200; bag `cs_test_a1GNjnZ2…` | A accepted; B abre Session; Hub A/B n=0 | FAIL | SIM |
| B2 | convert + chat card + Hub + order | pago Stripe + hitch convert/reconcile + card | e2e 200 `pi_3UCjv0…`; convert 403; card 201 | res ≠ converted; Hub n=0 qty=0; order `pago`; card ok | FAIL | SIM |
| B3 | end_live ∥ bag CPI ∥ Hub | Future.wait end ∥ bag ∥ hub | end 200 ended; bag `cs_test_a181hnC1…` | live `ended`; Hub SKU n=0; Hub live by-id 1 | FAIL | NÃO |
| B4 | rifa draw ∥ CPI marketplace + Hub | Future.wait draw ∥ CPI B2 qty=1 | draw 200 `drawn`; CPI 400 `product is marked sold` | winner 1; qty 0; Hub n=0; prize 0; sem 2 donos | FAIL | SIM |
| B5 | bag 6∥4 + Hub leftover + orders | **6∥4** após 1 pago leftover | 2× 200 `cs_`; leftover Hub n=1 | **2 cs_**; ledger=saco6; órfã saco4; leftover coerente | **HOLD** | SIM |
| C1 | offer + CPI + Hub + orders | oferta 8€ aceite + CPI amount=1 | CPI 200 selo **905¢** | offer accepted 8€; Hub n=1; underpay ignorado | FAIL | SIM |
| C2 | offer + bundle + Session + Hub | bundle∥oferta overlap SKU-X qty=1 | bundle accepted; insert X 400 hold; ≤1 cs_ | overlap bloqueado no hold | FAIL | SIM |
| C3 | release∥disputa + chat + wallet | Future.wait release + POST disputa + card | release 200 true; disputa 201 `aberta` | Δ snapshot 0; **clawback estorno 5€**; release_at null; 1 efeito líquido | FAIL | SIM |
| C4 | storage + disputa + proof_ok + reply | revoke proof mid-disputa + UI path | confirm: disp 201; rev true; **proof_ok false**; reply **400** `dispute_proof_url_denied` | auth 400; UI recusa URL morta | FAIL | SIM |
| D1 | refund ∥ CPI leftover | Future.wait refund pago ∥ CPI leftover | rf 200 `re_3UCjvZ…` cancelado; CPI leftover `cs_` | qty 1→2; old cancelado; new `reserva_pendente` | FAIL residual | NÃO |
| D2 | 2 buyers Hub + CPI qty=1 | Future.wait B2∥B3 CPI | Hub inicial n=1; 2.º insert 400 hold; 1 cs_ | Hub após hold n=0; ≤1 encomenda | FAIL | NÃO |
| D3 | Hub + order + wallet + chat | pago 4242 → 4 sítios | e2e 200 `pi_3UCjvh…` 590¢ succeeded; card 201 | status `pago` qty 2→1; Hub leftover n=1; Δwallet 0/0; chat 1 | FAIL | NÃO |
| D4 | bag expand + Stripe + Hub | subset AB →50ms superset ABCD | 2× 200 `cs_`; ledger=superset | **2 cs_**; subset órfã não expired | **HOLD** | SIM |

Linhas na tabela: **18**. Stripe TEST pago: **sim**. Residual clássico A2 sold + D1 refund∥leftover = 2/18 = 11% ≪ 40%. **Não** ATROFIA_ABORT. Classes novas: A1 tip+unpublish · A4 fav+hold · A5 live_item sold · B1 rifa+bag · B2 convert+chat · B4 rifa∥CPI · **B5 6∥4+Hub** · C1 oferta selo · C2 oferta∥bundle · C3 release∥disputa+clawback · C4 revoke mid-disputa · **D4 expand** (**12 ≥ 4**). Races: B3, B4, B5, C2, C3, D1, D2, D4 (**8 ≥ 5**).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 2
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (C1 selo 905¢ vs body 1)
10. Buyer manipula qty autoritativa — NÃO (holds `order_hold_exceeds_stock`)
11. Seller falsifica pagamento plataforma — NÃO (fora da matriz EE; C4 storage)
12. JWT cria saldo/fundos — NÃO (C3 clawback; D3 Δ 0 até release)
13. Refund excede captura — NÃO (D1 idempotente 590¢)
14. Release+refund cria dinheiro líquido — NÃO (C3 net 0 via estorno)
15. Payout duplica Transfer — NÃO (A1 1× débito de saldo existente)
16. Stock=1 duas vendas válidas — NÃO (A4/D2/B4 2.º recusado)
17. Stock=1 duas capturas líquidas permanentes — NÃO (2 `cs_` órfãs **não pagas**)
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (C4 reply 400; disputa alheia n/a)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da matriz)
24. RPC SECURITY DEFINER perigoso executável — NÃO (convert 403)
25. RLS crítico quebrado — NÃO (C4 disputa `pago` 403; confirm com concluido 201)
26. Edge confia total do cliente — NÃO (C1 selo 905¢)
27. Regressão funcional (happy path partido) — NÃO (A3 leftover; D3 pago 4 sítios; C1 offer; B1 bag B)
28. Saturação atingida — NÃO (P1 abertos; quota e classes novas cumpridas)

Poços EE: hub=SIM · live=SIM · chat=SIM · wallet=SIM · race=SIM · bag=SIM · rifa=SIM · caixa=SIM  
ATROFIA: NÃO (2/18 residual; ângulos novos = 6∥4+Hub, expand, live_item sold, revoke mid-disputa)  
Pagamento TEST: **pago** (vários PI `succeeded`).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

| ID | Severidade | Título |
|----|------------|--------|
| P1-1 | P1 | P1-B5-64-BAG-HUB — 6∥4 duas Sessions úteis |
| P1-2 | P1 | P1-D4-EXPAND-OPEN — expand duas Sessions; subset não expira |

Soma P0+P1+P2+P3 `quantos` = 2.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A1 payout unpublished | **Não mint.** Connect 200 debitou 1,00 € de saldo já existente; tip `pending`. Anti-atrofia. |
| Hub hide live accepted clássico | **Não exercitado como finding.** B1: accept A + bag B abre `cs_`. |
| Hub hide rifa drawn qty=1 | **Hub n=0** após draw (A5/B4). Item `sold`+inactivo — fecho DU visível. Não contar. |
| MB WAY exact 400 | **Não exercitado** (anti-atrofia). |
| follow published 403 | **Não exercitado.** A4 follow 409 duplicate. |
| 4∥2 ≤1 cs_ | **Não exercitado** (substituído por 6∥4 e expand). |
| buyer refund 403 | **Não exercitado** (anti-atrofia). |
| C3 release∥disputa 1 efeito | Race API: release `true` **e** disputa `aberta`. Ledger: txn `estorno` «Clawback: disputa aberta após libertação» 5€; `wallet_release_processed_at=null`; Δ líquido **0**. **1 efeito dinheiro** — anti-atrofia, não contar. |
| C4 pass1 disputa 403 | Estado `pago` sem plant. Confirm com `concluido`+mão: 201 + revoke + `proof_ok false` + reply 400. Fecho DV visível. |
| B3 Hub lives by-id após ended | Linha visível em `hub_lives_public` (possível Gravados). Sem player “ao vivo”. Não conta. |
| A5 prize_orders [] | Draw sem encomenda-prémio; Hub+live_item+stock selados. |

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------

| Lente | Evidência |
|-------|-----------|
| EE1 hub | A2 sold oculto; A3 leftover visível; A4 Hub n=0 após claim; A5 Hub n=0 após draw; D2 Hub n=0 após hold |
| EE2 live | B1 accept≠bag B; B2 convert 403; B3 end∥bag; A5 live_item `sold` |
| EE3 chat | B2 card 201; D3 card 201; C4 reply 400 após revoke |
| EE4 wallet | C3 clawback estorno 5€ Δ=0; A1 débito saldo existente; D3 Δ 0/0 até release |
| EE5 race | B3, B4, B5, C2, C3, D1, D2, D4 |
| EE6 bag | B5 6∥4; D4 expand; B1 bag B; C2 bundle hold |
| EE7 rifa | A5 item sold+Hub 0; B4 draw∥CPI sold |
| EE8 caixa | D3 pago 590¢ 4 sítios; D1 refund 590¢ |

--------------------------------------------------
## FIO (Hub + live + chat + wallet + caixa)
--------------------------------------------------

Unpublish + tip + payout (A1) → sold vs Hub (A2) → leftover pago (A3) → favorite+hold (A4) → rifa+live_item sold (A5) → rifa+accept A + bag B (B1) → convert+card (B2) → end∥bag∥Hub (B3) → rifa∥CPI (B4) → **6∥4+Hub pago (B5 P1)** → oferta underpay (C1) → oferta∥bundle (C2) → release∥disputa clawback (C3) → revoke mid-disputa (C4) → refund∥leftover (D1) → 2 buyers (D2) → pago 4 sítios (D3) → **expand (D4 P1)**.

--------------------------------------------------
## OPERAÇÃO
--------------------------------------------------

- Lives criadas: `ended` / `is_active=false` (finally pass1 + confirm).
- S1 `hub_published=true` à saída (RPC `batata_publish_hub`).
- Pasta: `tool/redteam_blind_ee_20260906T1822/` (`pass1.json`, `confirm.json`).
- **NÃO CORRIGIR.** Fase 4 não.

```
AUDITOR: REDTEAM_BLIND_EE_COMPOSICAO_POS_DTDY_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 18 · classes_novas: 12 · races: 8
VEREDICTO: FAIL_P1
```

RESUMO_NUMERICO: P0=0 P1=2 P2=0 P3=0 TOTAL=2
