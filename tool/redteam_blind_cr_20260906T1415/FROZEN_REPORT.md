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
FROZEN_AT: 2026-09-06T13:20:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CR1, CR2, CR3, CR4, CR5, CR6, CR7]
probes_na_tabela: 22
VEREDICTO: FAIL_P2
prefix: RTCR-20260906T1415
staging: fxdknzrqjenzqcvnwqqq
```

Exactos residual **não contados** (HOLD): `esaurito` · ZWJ `e[ZWJ]saurito`.  
A1 welcome **OK**. Hitch / convert / Mux residual **HOLD**.

---

## Missão

Bypass de stems FOMO com linguagem nova (fora da stem list compacta). Welcome legítima tem de continuar OK.

**Resposta:** a allowlist compacta (`ultim|disponib|esaur|last|gone|…`) **segura** IT/DE/FR conhecidos e o exemplo `último disponible`, e o **welcome** continua a funcionar. Frases **fora** desses stems (`já foi`, NL/PL/RO, emoji-only, paráfrases PT) persistem como `kind=system` `sender_label=Sistema` e o **Hub público** (comprador e anónimo) vê-as **sem** convert pago. Staff zero-perms, buyer INSERT, hitch, convert e Mux **não** passaram.

---

## Findings abertos

### CR-P2-01 — FOMO linguagem nova fura a stem list compacta (Hub)

- **Sev:** P2 · **Lente:** CR2/CR3 · **Actor:** seller JWT (`batata_live_system_message`)
- **Pré:** allowlist compacta em `batata_live_system_message`. Sem convert pago nesta live.
- **Repro:**
  1. Live `status=live` `is_active=true`
  2. `POST /rest/v1/rpc/batata_live_system_message` com frase **fora** dos stems (`já foi`, `queda poco`, `uitverkocht`, `ostatni`, `nu mai e`, `🔥1️⃣`, `fica pouco`, `correu tudo`)
  3. `GET hub_live_messages_public?live_id=eq.{id}` (buyer JWT e anon)
- **Esperado:** `ok=false` `purchase_announce_via_broadcast_only`
- **Obtido:**
  - A1 `Bem-vindos ao directo!` → `200 {"ok": true}` + Hub buyer/anon **visível** (**controlo positivo OK**)
  - A2 `O directo está a começar` → idem OK
  - Residual: `esaurito` · ZWJ `e[ZWJ]saurito` → `purchase_announce_via_broadcast_only` (**não contar**)
  - `último disponible` → recusado (`ultim`/`disponib`) HOLD
  - **8 FAIL:** `já foi` · `queda poco` · `uitverkocht` · `ostatni` · `nu mai e` · `🔥1️⃣` · `fica pouco` · `correu tudo` → `200 {"ok": true}` + Hub system Sistema (buyer **e** anon)
  - REST `live_messages` buyer: `200 []` (SELECT na tabela sujeito a RLS; o furo visível ao público é a view Hub)
  - Stock `available_qty` inalterado; zero orders pagas nesta live
  - Helper zero-perms na mesma frase `já foi`: `not_allowed`
  - Buyer INSERT `kind=system`: RLS 403
- **Impacto:** o vendedor publica no directo, com etiqueta oficial Sistema, scarcity em PT-BR / ES / NL / PL / RO / emoji **sem** reserva aceite nem order paga. Espectadores no Hub vêem FOMO oficial. Não mexe stock nem caixa.
- **Prova:** `pass1.json` · `confirm_hub_msgs.json`

Uma classe, 8 payloads — **conta 1**.

---

## HOLD (não contar)

| Lente | Prova | Resultado |
|-------|--------|-----------|
| CR1 | A1 welcome `Bem-vindos ao directo!` | `ok:true` + Hub visível |
| CR1 | A2 `O directo está a começar` | `ok:true` + Hub visível |
| CR3 | `esaurito` | `purchase_announce_via_broadcast_only` |
| CR2 | ZWJ `e[ZWJ]saurito` | recusado (fold ZWJ → `esaur`) |
| CR2 | `último disponible` | recusado (`ultim`/`disponib`) |
| CR3 | B5 buyer INSERT `kind=system` | RLS 403 |
| CR2 | B6 helper0 RPC `já foi` | `not_allowed` |
| CR3 | FOMO vs stock | `available_qty` inalterado |
| CR5 | FOMO → order paga | zero pago |
| CR5 | C2 `stripe_convert` sem PI | 403 permission denied for function |
| CR5 | C2b reconcile PI live A → res live B | 403 `convert_requires_paid_order` |
| CR4 | C1 hitch marketplace+live_only qty=1 | 2º accept `qty_exceeds_stock` |
| CR6 | C3 `end_live` ∥ accept | accept ganhou a race (reserva accepted; live ended) — sem caixa; **não P0** |
| CR6 | accept depois de ended | já decided / sem novo accept |
| CR7 | C4 GET playback/mux/livekit unpublished | 403 table lives |
| CR7 | C4 realtime `postgres_changes` lives | join ok; payload sem playback |

---

## TABELA DE PROVAS

| # | probe_id | poço | payload | RPC/HTTP | buyer GET | HOLD\|FAIL\|SKIP |
|---|----------|------|---------|----------|-----------|------------------|
| 1 | A1.welcome | CR-A | `Bem-vindos ao directo!` | 200 `ok:true` | Hub buyer+anon VISIBLE | HOLD |
| 2 | A2.neutra.comecar | CR-A | `O directo está a começar` | 200 `ok:true` | Hub buyer+anon VISIBLE | HOLD |
| 3 | R1.esaurito | residual | `esaurito` | 200 `purchase_announce_via_broadcast_only` | n/a | HOLD |
| 4 | B1.es.ultimo_disponible | CR-B | `último disponible` | 200 `purchase_announce_via_broadcast_only` | n/a | HOLD |
| 5 | B1.ptbr.ja_foi | CR-B | `já foi` | 200 `ok:true` | Hub buyer+anon VISIBLE | FAIL |
| 6 | B1.es.queda_poco | CR-B | `queda poco` | 200 `ok:true` | Hub buyer+anon VISIBLE | FAIL |
| 7 | B2.nl.uitverkocht | CR-B | `uitverkocht` | 200 `ok:true` | Hub buyer+anon VISIBLE | FAIL |
| 8 | B2.pl.ostatni | CR-B | `ostatni` | 200 `ok:true` | Hub buyer+anon VISIBLE | FAIL |
| 9 | B2.ro.nu_mai_e | CR-B | `nu mai e` | 200 `ok:true` | Hub buyer+anon VISIBLE | FAIL |
| 10 | B3.emoji.fire_one | CR-B | `🔥1️⃣` | 200 `ok:true` | Hub buyer+anon VISIBLE | FAIL |
| 11 | B4.zwj.esaurito | CR-B | `e[ZWJ]saurito` | 200 `purchase_announce_via_broadcast_only` | n/a | HOLD |
| 12 | B4.new.fica_pouco | CR-B | `fica pouco` | 200 `ok:true` | Hub buyer+anon VISIBLE | FAIL |
| 13 | B4.new.correu_tudo | CR-B | `correu tudo` | 200 `ok:true` | Hub buyer+anon VISIBLE | FAIL |
| 14 | B5.buyer.insert.system | CR-B | POST `live_messages` kind=system | 403 RLS | n/a | HOLD |
| 15 | B6.helper0.ja_foi | CR-B | helper0 RPC `já foi` | 200 `not_allowed` | n/a | HOLD |
| 16 | C1.hitch.qty_stock | CR-C | hitch marketplace+live_only qty=1 | 400 `qty_exceeds_stock` | n/a | HOLD |
| 17 | C2.convert.nopi | CR-C | stripe_convert accepted sem PI | 403 permission denied | n/a | HOLD |
| 18 | C2b.convert.pi_alheio | CR-C | reconcile PI liveA → res liveB | 403 `convert_requires_paid_order` | n/a | HOLD |
| 19 | C3.end_parallel_accept | CR-C | end_live ∥ PATCH accepted | accept won race; live ended | n/a | HOLD |
| 20 | C3.accept.after.end | CR-C | PATCH accepted após ended | já decided | n/a | HOLD |
| 21 | C4.buyer.playback_cols | CR-C | GET lives playback unpublished | 403 table lives | n/a | HOLD |
| 22 | C4.realtime.playback | CR-C | ws postgres_changes + PATCH playback | join ok; sem playback no payload | n/a | HOLD |

`probes_na_tabela: 22`. Residual CDCI/stems = 2 linhas (`esaurito`, ZWJ). A1 welcome OK.

---

## Lentes (≥5/7)

| ID | Resultado |
|----|-----------|
| CR1 welcome OK | HOLD — A1+A2 visíveis no Hub |
| CR2 stem bypass | FAIL — 8 frases novas |
| CR3 FOMO | FAIL — mesma classe Hub system |
| CR4 hitch | HOLD — 2º `qty_exceeds_stock` |
| CR5 convert | HOLD — sem PI / PI alheio |
| CR6 race | HOLD — end∥accept sem caixa |
| CR7 Mux | HOLD — REST 403; realtime sem playback |

---

## Anti-atrofia

Residual HOLD exactos (`esaurito` + ZWJ) = 2 / 22 ≈ 9% (< 50%). **Não** `ATROFIA_ABORT`.

---

## Saturação

Tabela ≥12 · A1 welcome OK · P0–P2 = **1** → **não** `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 22
VEREDICTO: FAIL_P2
```

**NÃO CORRIGIR.**
