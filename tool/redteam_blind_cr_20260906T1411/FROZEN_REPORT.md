# FROZEN_REPORT — RED TEAM CEGO CR

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
AUDITOR: REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1
FROZEN_AT: 2026-09-06T13:17:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CR1, CR2, CR3, CR4, CR5, CR6, CR7]
probes_na_tabela: 18 (≥12)
VEREDICTO: FAIL_P2
prefix: RTCR-20260906T1411
staging: fxdknzrqjenzqcvnwqqq
```

Controlo residual `esaurito` spaced: 1 linha (≤2). Welcome A1 OK. Não-quota residual: `último disponible` (stem `ultim`/`disponib` da allowlist — HOLD, não é IT/DE/FR CDCI).

---

## Missão

Bypass de stems FOMO com língua/forma **fora** da lista compacta pós-allowlist; system msg welcome legítima tem de continuar OK. Hitch/convert/Mux só se aberto.

**Resposta:** a allowlist compacta (`ultim`, `disponib`, `esaur`, …) recusa `último disponible` e `e s a u r i t o`, e o welcome **continua a funcionar**. Frases novas sem stem (`já foi`, NL/PL/RO, emoji 🔥1️⃣, `corre que some`, `sumiu`) passam como `kind=system` `sender_label=Sistema` e o Hub (comprador **e** anónimo) vê as 7. Staff zero-perms, buyer INSERT, hitch, convert e Mux **não** passaram.

---

## Findings abertos

### CR-P2-01 — FOMO em língua/forma fora da stem list persiste no system message e no Hub

- **Sev:** P2 · **Lente:** CR2/CR3 · **Actor:** seller JWT (`batata_live_system_message`)
- **Pré:** allowlist compacta em `batata_live_system_message` (stems PT/EN/ES/IT/DE/FR). Live fixture sem convert pago. Seller Hub publicado.
- **Repro:**
  1. Live `status=live` `is_active=true` (seller Hub publicado)
  2. `POST /rest/v1/rpc/batata_live_system_message` com cada frase nova
  3. `GET hub_live_messages_public?live_id=eq.{id}&kind=eq.system` (buyer JWT e anon)
- **Esperado:** `ok=false` `purchase_announce_via_broadcast_only`
- **Obtido:**
  - A1 `Bem-vindos ao directo!` → `200 {"ok": true}` + Hub Sistema (**legítimo OK, não contar**)
  - A2 `O directo está a começar` → `200 {"ok": true}` + Hub Sistema (**legítimo OK**)
  - `último disponible` → `purchase_announce_via_broadcast_only` (**HOLD**, stem `ultim`/`disponib`)
  - Residual `e s a u r i t o` → `purchase_announce_via_broadcast_only` (**HOLD, não contar**)
  - **7 FAIL:** `já foi` · `uitverkocht` · `wyprzedane` · `epuizat` · `🔥1️⃣` · `corre que some` · `sumiu` → `200 {"ok": true}`
  - Hub buyer **e** anon: as mesmas 9 rows system (2 legítimas + 7 FOMO) — `confirm_hub_msgs.json`
  - REST `live_messages` buyer: `200 []` (SELECT na tabela; o furo visível ao público é a view Hub)
  - Stock `available_qty` inalterado (2→2); zero orders pagas nesta live
  - Helper zero-perms na mesma frase NL: `not_allowed`
  - Buyer INSERT `kind=system`: RLS `42501`
- **Impacto:** o vendedor publica no directo, com etiqueta oficial Sistema, scarcity em NL/PL/RO/PT-BR/emoji **sem** reserva aceite nem order paga. Espectadores no Hub vêem FOMO oficial. Não mexe stock nem caixa.
- **Prova:** `probes.json` · `confirm_hub_msgs.json`

Uma classe, 7 payloads — **conta 1**.

---

## HOLD (não contar)

| Lente | Prova | Resultado |
|-------|--------|-----------|
| CR1 | A1 welcome / A2 neutro | `ok:true` + Hub Sistema |
| CR2 | `último disponible` | `purchase_announce_via_broadcast_only` |
| CR2 | `e s a u r i t o` residual CDCI | `purchase_announce_via_broadcast_only` |
| CR3 | buyer INSERT `kind=system` | RLS 403 `42501` |
| CR2 | helper0 `uitverkocht` | `not_allowed` |
| CR4 | hitch qty=1 2º accept | `qty_exceeds_stock`; r2 `pending` |
| CR5 | convert sem PI | `permission denied for function batata_live_reservation_stripe_convert`; status `accepted` |
| CR5 | reconcile PI alheio | `convert_requires_paid_order` |
| CR6 | end ∥ accept | accept ganhou a race (`accepted` + live `ended`); accept **pós**-end não abriu caminho novo |
| CR7 | GET `mux_live_id` unpublished | 403 `permission denied for table lives` |

**Não finding:** Hub VISIBLE em B5/B6 é a row do **seller** (`já foi` / `uitverkocht`), não do buyer/helper.

---

## TABELA DE PROVAS

| probe_id | poço | payload | RPC/HTTP | buyer GET | HOLD\|FAIL\|SKIP |
|----------|------|---------|----------|-----------|------------------|
| A1.welcome | CR-A | `Bem-vindos ao directo!` | 200 `ok:true` | Hub system Sistema | HOLD |
| A2.neutro.comecar | CR-A | `O directo está a começar` | 200 `ok:true` | Hub system Sistema | HOLD |
| B1.es.ultimo_disponible | CR-B | `último disponible` | 200 `purchase_announce_via_broadcast_only` | NOT VISIBLE | HOLD |
| B1.ptbr.ja_foi | CR-B | `já foi` | 200 `ok:true` | Hub system Sistema | FAIL |
| B2.nl.uitverkocht | CR-B | `uitverkocht` | 200 `ok:true` | Hub system Sistema | FAIL |
| B2.pl.wyprzedane | CR-B | `wyprzedane` | 200 `ok:true` | Hub system Sistema | FAIL |
| B2.ro.epuizat | CR-B | `epuizat` | 200 `ok:true` | Hub system Sistema | FAIL |
| B3.emoji.fire_one | CR-B | `🔥1️⃣` | 200 `ok:true` | Hub system Sistema | FAIL |
| B4.control.esaurito_spaced | CR-B | `e s a u r i t o` | 200 `purchase_announce_via_broadcast_only` | NOT VISIBLE | HOLD |
| B4.new.corre_que_some | CR-B | `corre que some` | 200 `ok:true` | Hub system Sistema | FAIL |
| B4.new.sumiu | CR-B | `sumiu` | 200 `ok:true` | Hub system Sistema | FAIL |
| B5.buyer.insert.system | CR-B | POST `live_messages` kind=system | 403 RLS `42501` | Hub VISIBLE (row seller, não INSERT) | HOLD |
| B6.helper0.scarcity | CR-B | helper0 RPC `uitverkocht` | 200 `not_allowed` | Hub VISIBLE (row seller) | HOLD |
| C1.hitch.qty_stock | CR-C | hitch marketplace+live_only qty=1 | 400 `qty_exceeds_stock` | n/a | HOLD |
| C2.convert.nopi | CR-C | `stripe_convert` sem PI | 403 function denied | n/a | HOLD |
| C2.convert.pi_alheio | CR-C | reconcile PI liveA → res liveB | 403 `convert_requires_paid_order` | n/a | HOLD |
| C3.end_parallel_accept | CR-C | end_live ∥ PATCH accepted | 200 accept + 200 ended | n/a | HOLD |
| C4.mux.live_id.unpub | CR-C | GET `mux_live_id` unpublished | 403 table `lives` | empty/403 | HOLD |

**probes_na_tabela: 18** (≥12). Residual stems ≤2. ≥50% residual? NÃO → não `ATROFIA_ABORT`.

---

## Lentes (7/7)

| Lente | Resultado |
|-------|-----------|
| CR1 welcome OK | HOLD — A1+A2 `ok:true` Hub |
| CR2 stem bypass | FAIL — NL/PL/RO + PT-BR sem stem |
| CR3 FOMO | FAIL — 7 rows Sistema sem convert pago |
| CR4 hitch | HOLD — 2º `qty_exceeds_stock` |
| CR5 convert | HOLD — function denied / `convert_requires_paid_order` |
| CR6 race | HOLD — sem accept **depois** de ended já decidido |
| CR7 Mux | HOLD — unpublished 403 |

---

## Poços

CR-A positivo 2=SIM · CR-B bypass 11=SIM · CR-C hitch/convert/race/Mux 5=SIM

---

## Saturação

Tabela ≥12 · A1 welcome OK · P0–P2 ≠ 0 → **não** `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 18
VEREDICTO: FAIL_P2
```

**NÃO CORRIGIR.**

---

## Artefactos

- `tool/redteam_blind_cr_20260906T1411/probes.json`
- `tool/redteam_blind_cr_20260906T1411/confirm_hub_msgs.json`
- Live FOMO (ended): `42a6beeb-7e0a-43ee-8cab-776f82e62095`
