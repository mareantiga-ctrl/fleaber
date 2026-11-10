# FROZEN_REPORT — RED TEAM CEGO CX

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 1

```
1. P0? NÃO  2. Quantos P0: 0
3. P1? NÃO  4. Quantos P1: 0
5. P2? SIM  6. Quantos P2: 1
7. P3? NÃO  8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_CX_LIVE_POS_CPCU_v1
FROZEN_AT: 2026-09-06T13:55:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CX1, CX2, CX3, CX4, CX5, CX6, CX7]
probes_na_tabela: 25
VEREDICTO: FAIL_P2
prefix: RTCX-20260906T1448
staging: fxdknzrqjenzqcvnwqqq
```

Exactos residual **não contados** (HOLD): `já foi` · `esaurito`.  
A1 welcome **OK**. Hitch / convert / Mux residual **HOLD**.

---

## Missão

Welcome / «directo a começar» visíveis. Scarcity/FOMO → `purchase_announce_via_broadcast_only`. Bypass por morfologia / espaços / emoji **sem** repetir exactos CR.

**Resposta:** stems alargados pós-CPCU **fecham** os exactos CR (`já foi`, `esaurito`, soft-hyphen em `esaurito`). Welcome continua OK. Frases **novas** (PT-BR / EN / NL / PL), emoji 🔥 **sem dígito**, inserção `0`/`✅` no meio do stem, e «restam 2» persistem como `kind=system` `sender_label=Sistema`. Hub público (comprador **e** anónimo) vê-as **sem** convert pago. Helper zero-perms, buyer INSERT, hitch, convert e Mux **não** passaram.

---

## Findings abertos

### CX-P2-01 — FOMO morfologia nova fura stems alargados (Hub)

- **Sev:** P2 · **Lente:** CX2/CX3 · **Actor:** seller JWT (`batata_live_system_message`)
- **Pré:** stems CPCU alargados. Sem convert pago nesta live.
- **Repro:**
  1. Live `status=live` `is_active=true`
  2. `POST /rest/v1/rpc/batata_live_system_message` com frase **nova** (não exacto CR)
  3. `GET hub_live_messages_public?live_id=eq.{id}` (buyer JWT e anon)
- **Esperado:** `ok=false` `purchase_announce_via_broadcast_only`
- **Obtido:**
  - A1 `Bem-vindos ao directo!` → `200 {"ok": true}` + Hub buyer/anon **visível** (**controlo positivo OK**)
  - A2 `O directo está a começar` → idem OK
  - Residual: `já foi` · `esaurito` → `purchase_announce_via_broadcast_only` (**não contar**)
  - Soft-hyphen `es[SHY]aurito` → recusado (fold SHY → `esaur`) HOLD
  - **10 FAIL:** `sumiu tudo` · `não sobra nada` · `selling fast` · `bijna op` · `wyprzedane` · `🔥🔥🔥` · `🔥GO` · `es0aurito` · `es✅aurito` · `restam 2` → `200 {"ok": true}` + Hub system Sistema (buyer **e** anon)
  - REST `live_messages` buyer: `200 []` (SELECT na tabela sujeito a RLS; o furo visível ao público é a view Hub)
  - Stock `available_qty` 2→2 inalterado; zero orders pagas nesta live
  - Helper zero-perms na mesma frase `sumiu tudo`: `not_allowed`
  - Buyer INSERT `kind=system`: RLS 403
- **Impacto:** o vendedor publica no directo, com etiqueta oficial Sistema, scarcity em PT-BR / EN / NL / PL, 🔥 sem dígito, e morfologia que parte o stem (`0`/`✅` no meio de `esaur`) **sem** reserva aceite nem order paga. Espectadores no Hub vêem FOMO oficial. Não mexe stock nem caixa.
- **Prova:** `pass1.json` · `confirm_hub_msgs.json` · live `6fe7a01e-452e-4ac1-b38b-25e6b7a12f92`

Uma classe, 10 payloads — **conta 1**.

---

## HOLD (não contar)

| Lente | Prova | Resultado |
|-------|--------|-----------|
| CX1 | A1 welcome `Bem-vindos ao directo!` | `ok:true` + Hub visível |
| CX1 | A2 `O directo está a começar` | `ok:true` + Hub visível |
| CX2 | `já foi` | `purchase_announce_via_broadcast_only` |
| CX2 | `esaurito` | `purchase_announce_via_broadcast_only` |
| CX2 | B4 soft-hyphen `es[SHY]aurito` | recusado (fold → `esaur`) |
| CX2 | B5 buyer INSERT `kind=system` | RLS 403 |
| CX2 | B5 helper0 RPC `sumiu tudo` | `not_allowed` |
| CX3 | FOMO vs stock | `available_qty` 2→2 |
| CX5 | FOMO → order paga | zero pago |
| CX5 | C2 `stripe_convert` sem PI | 403 permission denied for function |
| CX5 | C2b reconcile PI live A → res live B | 403 `convert_requires_paid_order` |
| CX4 | C1 hitch marketplace+live_only qty=1 | 2º accept `qty_exceeds_stock` |
| CX6 | C3 `end_live` ∥ accept | accept ganhou a race (reserva accepted; live ended) — sem caixa; **não P0** |
| CX6 | accept depois de ended | já decided / sem novo accept |
| CX7 | C4 GET playback/mux/livekit unpublished | 403 table lives |
| CX7 | C4 realtime `postgres_changes` lives | join ok; payload sem playback |

---

## TABELA DE PROVAS

| # | probe_id | poço | payload | RPC/HTTP | Hub buyer/anon | HOLD\|FAIL\|SKIP |
|---|----------|------|---------|----------|----------------|------------------|
| 1 | A1.welcome | CX-A | `Bem-vindos ao directo!` | 200 `ok:true` | buyer+anon VISIBLE | HOLD |
| 2 | A2.neutra.comecar | CX-A | `O directo está a começar` | 200 `ok:true` | buyer+anon VISIBLE | HOLD |
| 3 | R1.ja_foi | residual | `já foi` | 200 `purchase_announce_via_broadcast_only` | n/a | HOLD |
| 4 | R2.esaurito | residual | `esaurito` | 200 `purchase_announce_via_broadcast_only` | n/a | HOLD |
| 5 | B1.ptbr.sumiu_tudo | CX-B | `sumiu tudo` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 6 | B1.ptbr.nao_sobra | CX-B | `não sobra nada` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 7 | B2.en.selling_fast | CX-B | `selling fast` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 8 | B2.nl.bijna_op | CX-B | `bijna op` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 9 | B2.pl.wyprzedane | CX-B | `wyprzedane` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 10 | B3.emoji.fire_only | CX-B | `🔥🔥🔥` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 11 | B3.emoji.fire_go | CX-B | `🔥GO` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 12 | B4.shy.esaurito | CX-B | `es[SHY]aurito` | 200 `purchase_announce_via_broadcast_only` | n/a | HOLD |
| 13 | B4.morph.es0aurito | CX-B | `es0aurito` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 14 | B4.morph.es_check | CX-B | `es✅aurito` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 15 | B4.morph.restam_2 | CX-B | `restam 2` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 16 | B5.buyer.insert.system | CX-B | POST `live_messages` kind=system | 403 RLS | n/a | HOLD |
| 17 | B5.helper0.sumiu | CX-B | helper0 RPC `sumiu tudo` | 200 `not_allowed` | n/a | HOLD |
| 18 | B6.fomo.stock.delta | CX-B | stock before/after FOMO | available 2→2 | n/a | HOLD |
| 19 | C1.hitch.qty_stock | CX-C | hitch marketplace+live_only qty=1 | 400 `qty_exceeds_stock` | n/a | HOLD |
| 20 | C2.convert.nopi | CX-C | stripe_convert accepted sem PI | 403 permission denied | n/a | HOLD |
| 21 | C2b.convert.pi_alheio | CX-C | reconcile PI liveA → res liveB | 403 `convert_requires_paid_order` | n/a | HOLD |
| 22 | C3.end_parallel_accept | CX-C | end_live ∥ PATCH accepted | accept won race; live ended | n/a | HOLD |
| 23 | C3.accept.after.end | CX-C | PATCH accepted após ended | já decided | n/a | HOLD |
| 24 | C4.buyer.playback_cols | CX-C | GET lives playback unpublished | 403 table lives | n/a | HOLD |
| 25 | C4.realtime.playback | CX-C | ws postgres_changes + PATCH playback | join ok; sem playback no payload | n/a | HOLD |

`probes_na_tabela: 25`. Residual CR exactos = 2 linhas (`já foi`, `esaurito`). A1 welcome OK.

---

## Lentes (≥5/7)

| ID | Resultado |
|----|-----------|
| CX1 welcome | HOLD — A1+A2 visíveis no Hub |
| CX2 FOMO | FAIL — 10 frases/morfologias novas |
| CX3 Hub | FAIL — mesma classe Hub system buyer+anon |
| CX4 hitch | HOLD — 2º `qty_exceeds_stock` |
| CX5 convert | HOLD — sem PI / PI alheio |
| CX6 race | HOLD — end∥accept sem caixa |
| CX7 Mux | HOLD — REST 403; realtime sem playback |

---

## Anti-atrofia

Residual HOLD exactos (`já foi` + `esaurito`) = 2 / 25 = 8% (< 50%). **Não** `ATROFIA_ABORT`.  
Não se repetiram exactos CR FAIL (`queda poco`, `uitverkocht`, `ostatni`, `🔥1️⃣`).

---

## Saturação

Tabela ≥12 · A1 welcome OK · P0–P2 = **1** → **não** `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_CX_LIVE_POS_CPCU_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 25
VEREDICTO: FAIL_P2
```

**NÃO CORRIGIR.**
