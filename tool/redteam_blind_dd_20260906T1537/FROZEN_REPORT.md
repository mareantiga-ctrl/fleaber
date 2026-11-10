# FROZEN_REPORT — RED TEAM CEGO DD

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 1

```
1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? NÃO
4. Quantos P1: 0
5. P2 hygiene? SIM
6. Quantos P2: 1
7. P3 baixo risco? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_DD_LIVE_POS_CVDA_v1
FROZEN_AT: 2026-09-06T14:43:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DD1, DD2, DD3, DD4, DD5, DD6, DD7]
probes_na_tabela: 25
VEREDICTO: FAIL_P2
prefix: RTDD-20260906T1537
staging: fxdknzrqjenzqcvnwqqq
```

Exactos residual **não contados** (HOLD): `sumiu tudo` · `🔥🔥🔥`.  
A1 welcome **OK**. Hitch / convert / Mux residual **HOLD**.

---

## Missão

Welcome visível. FOMO/scarcity → `purchase_announce_via_broadcast_only`. Bypass por morfologia **nova** (não exactos CX).

**Resposta:** CVDA fecha os exactos CX (`sumiu tudo`, `🔥🔥🔥`). Welcome continua OK. Frases **novas** (PT / EN / DE / FR), emoji sem 🔥 (💨 ⚡ 🧨), dígito no meio de `sold` (`s0ld`), `✅` no meio de stem novo, e homóglifo cirílico `ѕold` persistem como `kind=system` `sender_label=Sistema`. Hub público (comprador **e** anónimo) vê-as **sem** convert pago. Helper zero-perms, buyer INSERT, hitch, convert e Mux **não** passaram.

---

## Findings abertos

### DD-P2-01 — FOMO morfologia nova fura stems CVDA (Hub)

- **Sev:** P2 · **Lente:** DD2/DD3 · **Actor:** seller JWT (`batata_live_system_message`)
- **Pré:** CVDA 🔥 + stems + anti digit-in-stem. Sem convert pago nesta live.
- **Repro:**
  1. Live `status=live` `is_active=true`
  2. `POST /rest/v1/rpc/batata_live_system_message` com frase **nova** (não exacto CX)
  3. `GET hub_live_messages_public?live_id=eq.{id}` (buyer JWT e anon)
- **Esperado:** `ok=false` `purchase_announce_via_broadcast_only`
- **Obtido:**
  - A1 `Bem-vindos ao directo!` → `200 {"ok": true}` + Hub buyer/anon **visível** (**controlo positivo OK**)
  - A2 `O directo está a começar` → idem OK
  - Residual CX: `sumiu tudo` · `🔥🔥🔥` → `purchase_announce_via_broadcast_only` (**não contar**)
  - **11 FAIL:** `voou tudo` · `zerou o lote` · `running out` · `knapp` · `plus rien` · `💨💨💨` · `⚡GO` · `🧨 agora` · `s0ld` · `liq✅uidado` · `ѕold` (U+0455) → `200 {"ok": true}` + Hub system Sistema (buyer **e** anon)
  - REST `live_messages` buyer: `200 []` (SELECT na tabela sujeito a RLS; o furo visível ao público é a view Hub)
  - Stock `available_qty` 2→2 inalterado; zero orders pagas nesta live
  - Helper zero-perms na mesma frase `voou tudo`: `not_allowed`
  - Buyer INSERT `kind=system`: RLS 403
- **Impacto:** o vendedor publica no directo, com etiqueta oficial Sistema, scarcity em PT / EN / DE / FR, emoji de urgência sem 🔥, e morfologia que parte o stem (`0` no meio de `sold`; homóglifo `ѕold`) **sem** reserva aceite nem order paga. Espectadores no Hub vêem FOMO oficial. Não mexe stock nem caixa.
- **Prova:** `pass1.json` · `confirm_hub_msgs.json` · live `0e300f43-de2d-4a2c-a1cc-5779461f277e`

Uma classe, 11 payloads — **conta 1**.

---

## HOLD (não contar)

| Lente | Prova | Resultado |
|-------|--------|-----------|
| DD1 | A1 welcome `Bem-vindos ao directo!` | `ok:true` + Hub visível |
| DD1 | A2 `O directo está a começar` | `ok:true` + Hub visível |
| DD2 | `sumiu tudo` | `purchase_announce_via_broadcast_only` |
| DD2 | `🔥🔥🔥` | `purchase_announce_via_broadcast_only` |
| DD2 | B5 buyer INSERT `kind=system` | RLS 403 |
| DD2 | B5 helper0 RPC `voou tudo` | `not_allowed` |
| DD3 | FOMO vs stock | `available_qty` 2→2 |
| DD5 | FOMO → order paga | zero pago |
| DD5 | C2 `stripe_convert` sem PI | 403 permission denied for function |
| DD5 | C2b reconcile PI live A → res live B | 403 `convert_requires_paid_order` |
| DD4 | C1 hitch marketplace+live_only qty=1 | 2º accept `qty_exceeds_stock` |
| DD6 | C3 `end_live` ∥ accept | accept ganhou a race (reserva accepted; live ended) — sem caixa; **não P0** |
| DD6 | accept depois de ended | já decided / sem novo accept |
| DD7 | C4 GET playback/mux/livekit unpublished | 403 table lives |
| DD7 | C4 realtime `postgres_changes` lives | join ok; payload sem playback |

---

## TABELA DE PROVAS

| # | probe_id | poço | payload | RPC/HTTP | Hub buyer/anon | HOLD\|FAIL\|SKIP |
|---|----------|------|---------|----------|----------------|------------------|
| 1 | A1.welcome | DD-A | `Bem-vindos ao directo!` | 200 `ok:true` | buyer+anon VISIBLE | HOLD |
| 2 | A2.neutra.comecar | DD-A | `O directo está a começar` | 200 `ok:true` | buyer+anon VISIBLE | HOLD |
| 3 | R1.sumiu_tudo | residual | `sumiu tudo` | 200 `purchase_announce_via_broadcast_only` | n/a | HOLD |
| 4 | R2.fire3 | residual | `🔥🔥🔥` | 200 `purchase_announce_via_broadcast_only` | n/a | HOLD |
| 5 | B2.pt.voou_tudo | DD-B | `voou tudo` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 6 | B2.pt.zerou_lote | DD-B | `zerou o lote` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 7 | B2.en.running_out | DD-B | `running out` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 8 | B2.de.knapp | DD-B | `knapp` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 9 | B2.fr.plus_rien | DD-B | `plus rien` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 10 | B3.emoji.dash | DD-B | `💨💨💨` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 11 | B3.emoji.bolt_go | DD-B | `⚡GO` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 12 | B3.emoji.cracker | DD-B | `🧨 agora` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 13 | B4.morph.s0ld | DD-B | `s0ld` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 14 | B4.morph.liq_check | DD-B | `liq✅uidado` | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 15 | B4.morph.homoglyph_sold | DD-B | `ѕold` (U+0455) | 200 `ok:true` | buyer+anon VISIBLE | FAIL |
| 16 | B5.buyer.insert.system | DD-B | POST `live_messages` kind=system | 403 RLS | n/a | HOLD |
| 17 | B5.helper0.voou | DD-B | helper0 RPC `voou tudo` | 200 `not_allowed` | n/a | HOLD |
| 18 | B6.fomo.stock.delta | DD-B | stock before/after FOMO | available 2→2 | n/a | HOLD |
| 19 | C1.hitch.qty_stock | DD-C | hitch marketplace+live_only qty=1 | 400 `qty_exceeds_stock` | n/a | HOLD |
| 20 | C2.convert.nopi | DD-C | stripe_convert accepted sem PI | 403 permission denied | n/a | HOLD |
| 21 | C2b.convert.pi_alheio | DD-C | reconcile PI liveA → res liveB | 403 `convert_requires_paid_order` | n/a | HOLD |
| 22 | C3.end_parallel_accept | DD-C | end_live ∥ PATCH accepted | accept won race; live ended | n/a | HOLD |
| 23 | C3.accept.after.end | DD-C | PATCH accepted após ended | já decided | n/a | HOLD |
| 24 | C4.buyer.playback_cols | DD-C | GET lives playback unpublished | 403 table lives | n/a | HOLD |
| 25 | C4.realtime.playback | DD-C | ws postgres_changes + PATCH playback | join ok; sem playback no payload | n/a | HOLD |

`probes_na_tabela: 25`. Residual CX exactos = 2 linhas (`sumiu tudo`, `🔥🔥🔥`). A1 welcome OK.

---

## Lentes (≥5/7)

| ID | Resultado |
|----|-----------|
| DD1 welcome | HOLD — A1+A2 visíveis no Hub |
| DD2 FOMO | FAIL — 11 frases/morfologias novas |
| DD3 Hub | FAIL — mesma classe Hub system buyer+anon |
| DD4 hitch | HOLD — 2º `qty_exceeds_stock` |
| DD5 convert | HOLD — sem PI / PI alheio |
| DD6 race | HOLD — end∥accept sem caixa |
| DD7 Mux | HOLD — REST 403; realtime sem playback |

---

## Anti-atrofia

Residual HOLD exactos (`sumiu tudo` + `🔥🔥🔥`) = 2 / 25 = 8% (< 50%). **Não** `ATROFIA_ABORT`.  
Não se repetiram exactos CX FAIL (`selling fast`, `es0aurito`, `já foi`, `esaurito`).

---

## Saturação

Tabela ≥12 · A1 welcome OK · B* **não** todos deny · P0–P2 = **1** → **não** `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DD_LIVE_POS_CVDA_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 25
VEREDICTO: FAIL_P2
```

**NÃO CORRIGIR.**
