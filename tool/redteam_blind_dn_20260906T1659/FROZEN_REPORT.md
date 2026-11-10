# FROZEN_REPORT — REDTEAM_BLIND_DN_BAG_MUTEX_POS_DHDM_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 1

1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? SIM
4. Quantos P1: 1
5. P2 hygiene? NÃO
6. Quantos P2: 0
7. P3 baixo risco? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DN_BAG_MUTEX_POS_DHDM_v1
FROZEN_AT: 2026-09-06T17:10:00+01:00
production_touched: false
fase4: false
corrections_applied: false
probes_na_tabela: 18
classes_novas: 7
lentes_cobertas: [DN1, DN2, DN3, DN4, DN5, DN6, DN7, DN8]
pocos_tentados: [DN-A, DN-B, DN-C, DN-D]
races_future_wait: [A3, A4, B1, B2, B3, B4, B5, B6, C4]
stripe_test_pago: true
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTDN-20260906T1659-` · pasta: `tool/redteam_blind_dn_20260906T1659/`.  
Atacantes: anon · buyer JWT · seller JWT · buyer2 · seller2. `service_role` só fixture/observação (`plantClaim`, `setup_paid_order`, mutex peek).

---

## P1-1 — Overlap 5∥3 (subset no meio) e bag∥single linha do meio: duas Sessions Stripe

**O que isto é:** o comprador pede ao mesmo tempo o pagamento de cinco artigos e, em paralelo, só dos três do meio (ou o pagamento avulso da linha do meio do mesmo saco). Depois do fecho DHDM dos casos 4∥2 / bag∥single «clássicos», o cadeado ainda tinha de entregar no máximo um link Stripe útil, ou recusar o segundo.

**Quem / onde:** comprador (JWT) no checkout do saco.

**O que fizemos:**
- B1: 5 encomendas do mesmo vendedor. `Future.wait` saco ABCDE ∥ saco BCD (subset no meio). Confirm pass2.
- B5: saco de 5 ∥ pagamento avulso da linha C (meio, não extrema). Confirm pass2.
- A3 (classe nova): timeout 250 ms ∥ retry do saco ∥ 3.º CPI avulso.
- B6 (classe nova): timeout 200 ms ∥ saco completo ∥ CPI avulso da linha do meio.

**Esperado vs resultado**
- API B1 5∥3: esperado ≤1 `cs_` útil ou 2.º contention · visto **2** `cs_test_` distintas, ambas HTTP 200 (`a1HlQEis…` + `a1HWSVre…`); pass2 `a18Zts6i…` + `a1aTyrhQ…`; `reused=false` nas duas
- Ledger B1: A–E todas com a Session do saco de 5; a Session de 3 linhas ficou órfã (pass1 e pass2)
- API B5 bag∥single-meio: **2** `cs_test_` (`a1XlnvzO…` + `a1h4ws8U…`); pass2 `a1LP4rmS…` + `a18TbFIr…`; ledger nas 5 linhas = sid do saco; single órfã
- API A3: 598 + 200 + 200; 2 `cs_` (`a1vbEVME…` no ledger + órfã `a1wu9r6I…` do 3.º CPI)
- API B6: 598 + 200 (bag, `reused=true` no 2.º bag) + 200 single órfã `a1UtLlIp…`; ledger nas 3 linhas = sid do saco
- Stripe: sem `sk_test_` local; settle 402 nas duas (payable=2). **Não pagámos as duas.**

**Conclusão:** **P1** — o cliente recebeu dois links; uma Session ficou órfã. Não é P0: não pagámos as duas. O mutex por buyer **não** impede duas criações em overlap 5∥3 (subset no meio) nem bag∥single da linha do meio. AB∥BC, ABC∥CBA e 2× single mesma order **fecharam** (≤1 / reuse / overlapping bag session).  
**Prova:** `probes.json` A3/B1/B5/B6 + `pass2.json`.

---

## Anti-atrofia

Exactos **não corridos / não contados** (HOLD residual clássico):
- 4∥2 clássico — **não** na tabela (substituído por 5∥3)
- bag∥single extrema clássico — **não** na tabela (substituído por linha do meio)
- `mb way x` / `xxmbway` / `mbωay` / PaysafeCash — **não** na tabela (fora de DN-C desta ronda)
- claiming TTL exacto DBDG — **não** na tabela (A2 = futuro/malform, 1 linha)

Fechos novos documentados (FAIL, não contar como finding):
- B2 AB∥BC → 200 + **400 overlapping bag session**; 1 `cs_`
- B3 ABC∥CBA → 200 + 200 **mesmo** `cs_` (`reused=true`)
- B4 2× single mesma order → 200 + 200 **mesmo** `cs_` (`reused=true`)
- A1 dead `cs_` → buyer2 400; owner reclaim 200
- A2 claiming futuro → RPC JWT 403; CPI 200 `cs_` coerente no ledger
- A4 bags disjuntos → 2 `cs_` após serializar (linhas sem overlap); JWT mutex **403**
- A5 JWT PATCH `cs_` 403 immutable; RPC claim alheio 403; buyer2 CPI 400
- C1 underpay → Session **2323** ¢
- C2 PATCH shipping HTTP 200 **sem mutar** (`entrega em mão`); amount 2995 estável
- C3 2.º insert 400 `order_hold_exceeds_stock`
- C4 unlist∥CPI → CPI 400 not listed
- D1 cross-seller 400
- D2 qty JWT 403; CPI 1745 ¢ (1 unidade)

HOLD na tabela = 4 linhas (A3, B1, B5, B6) = **1** finding P1-1. 4/18 = 22% < 40%. **Não** ATROFIA_ABORT.  
classe_nova=SIM: A3, B1, B2, B3, B4, B5, B6 (**7** ≥ 3).

---

## TABELA DE PROVAS

| probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|------|----------------|----------|-----------|------------------|--------------|
| A1 | DN-A | plant `cs_test_dead`; buyer2 CPI; owner retry | buyer2 400; retry 200 `cs_test_a17Jigkn…` | sid novo; morta não persiste | FAIL | NÃO |
| A2 | DN-A | `claiming:<now+1y>:malformtok12ab` + RPC JWT | RPC 403; CPI 200 | sid `cs_test_a1ZCNeT8…` coerente | FAIL | NÃO |
| A3 | DN-A | Future.wait bag timeout 250ms ∥ retry bag ∥ 3.º CPI single | 598 + 200 + 200 duas `cs_` | ledger `a1vbEVME…`; órfã `a1wu9r6I…`; payable=2 | **HOLD** P1-1 | SIM |
| A4 | DN-A | Future.wait 2 bags disjuntos mesmo buyer | 200+200 duas `cs_` | bags A/B sid distintos; JWT mutex 403 | FAIL | NÃO |
| A5 | DN-A | JWT PATCH cs_ sem claim; buyer2 RPC token alheio + CPI | PATCH 403; RPC 403; CPI 400 | claiming plantado; owner 400 contention | FAIL | NÃO |
| B1 | DN-B | Future.wait bag 5-line ∥ bag 3-line subset meio (BCD) | 200+200 duas `cs_` | A–E `a1HlQEis…`; órfã `a1HWSVre…`; pass2 repeat 2 `cs_` | **HOLD** P1-1 | SIM |
| B2 | DN-B | Future.wait bag AB ∥ bag BC (overlap 1 linha) | 200 + 400 overlapping bag session | 1 `cs_test_a1fqBfcp…`; C sem sid | FAIL | SIM |
| B3 | DN-B | Future.wait bag ABC ∥ bag CBA (ordem inversa) | 200+200 mesmo `cs_` reused | 1 `cs_test_a11fZpmm…` | FAIL | SIM |
| B4 | DN-B | Future.wait 2× CPI single mesma order_id | 200+200 mesmo `cs_` reused | 1 `cs_test_a12UcAt2…` | FAIL | SIM |
| B5 | DN-B | Future.wait bag 5-line ∥ CPI single linha do meio (C) | 200+200 duas `cs_` | ledger saco `a1XlnvzO…`; single órfã `a1h4ws8U…`; pass2 repeat 2 `cs_` | **HOLD** P1-1 | SIM |
| B6 | DN-B | Future.wait bag timeout 200ms ∥ bag full ∥ CPI single meio | 598 + 200 reused + 200 | ledger `a1lWEHYf…`; órfã `a1UtLlIp…`; payable=2 | **HOLD** P1-1 | SIM |
| C1 | DN-C | `total_eur=0`+`item_price=0.01` SKU 18€ | 200 **2323** ¢ | amount catálogo | FAIL | NÃO |
| C2 | DN-C | Session open → JWT PATCH shipping=ctt; coupon SAVE90 | PATCH 200; re-CPI/coupon 2995 | shipping **não** mudou (`entrega em mão`) | FAIL | NÃO |
| C3 | DN-C | 2 buyers última unidade qty=1 | insert2 400 `order_hold_exceeds_stock` | 0 Sessions do 2.º | FAIL | NÃO |
| C4 | DN-C | Future.wait CPI ∥ unlist+qty=0 | CPI 400 not listed | `list_on_marketplace=false` qty=0 | FAIL | NÃO |
| C5 | DN-C | Stripe TEST pago 4242 + caixa | e2e `setup_paid_order` 200 | `pago` PI `pi_3UCiZoH7FWYUN3jh0XvcFxjd` 590¢ stock 2→1 `applied=1` | FAIL | NÃO |
| D1 | DN-D | bag 2 sellers | 400 one seller | sem `cs_` | FAIL | NÃO |
| D2 | DN-D | JWT PATCH qty=99; CPI quantity=99 stock=1 | JWT 403; CPI 200 catálogo 1745 ¢ | quantity imutável | FAIL | NÃO |

Linhas na tabela: **18** (≥18). Races `Future.wait`: **9** (A3, A4, B1, B2, B3, B4, B5, B6, C4). Stripe TEST pago: **sim**. classe_nova=SIM: **7**.

HOLD na tabela = finding (A3/B1/B5/B6 = um P1). FAIL = ataque bloqueado. SKIP = 0.

---

## Lentes (≥6/8)

| Lente | Evidência |
|-------|-----------|
| DN1 Session | C5 PI succeeded; D1 bag sem Session cross-seller |
| DN2 mutex | A4 bags disjuntos; JWT sem GRANT (403) na tabela mutex |
| DN3 overlap novo | B1 5∥3 duas `cs_`; B5 bag∥single-meio duas `cs_`; B2 AB∥BC 400; B3/B4 reuse |
| DN4 stock | C3 hold stock; C4 unlist 400; D2 qty 403 |
| DN5 preço | C1 2323 ¢; C2 amount estável 2995 |
| DN6 claim | A1 reclaim morta; A2 futuro; A5 JWT/RPC/CPI alheio 403/400 |
| DN7 race | Future.wait A3/A4/B1/B2/B3/B4/B5/B6/C4 |
| DN8 caixa | PI succeeded 590¢; wallets buyer 61,10 / seller 35,00 estáveis |

---

## Tácticas mínimas (quota)

1. Checkout Stripe TEST pago (4242 / `setup_paid_order`): **sim** — order `199358b1-c365-4361-afef-4c294ded22b9`, PI `pi_3UCiZoH7FWYUN3jh0XvcFxjd`, `amount_paid_cents=590`, qty 2→1
2. ≥4 races `Future.wait` distintas: **sim** (9: A3, A4, B1, B2, B3, B4, B5, B6, C4)
3. Tabela ≥18: **18**
4. Matriz DN-A (5) DN-B (6) DN-C (5) DN-D (2): **sim**
5. Lentes ≥6/8: **8/8**
6. ≥3 classe_nova: **7** (A3, B1–B6)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` local → sem expire/retrieve nativo; settle 402
- A5 owner CPI 400 `order claim contention` enquanto o token `claiming:` plantado por service_role ainda estava vivo — esperado no TTL; **não** é finding (JWT não escreveu o claim)
- Wallets buyer 61,10 / seller 35,00 estáveis nesta ronda (pago 5,90 € via e2e não creditou wallet imediato — igual a DH)
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_dn_20260906T1659/_rtdn.dart`
- `tool/redteam_blind_dn_20260906T1659/pass1.dart` + `pass1_findings.json` + `probes.json`
- `tool/redteam_blind_dn_20260906T1659/pass2.dart` + `pass2.json`

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
