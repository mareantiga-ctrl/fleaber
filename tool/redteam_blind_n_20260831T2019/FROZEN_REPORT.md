# FROZEN_REPORT — RED TEAM CEGO N (LIVE STREAM / MUX / LIVEKIT / RIFA / SACO)

```
AUDITOR: REDTEAM_BLIND_N_LIVE_STREAM_v1
FROZEN_AT: 2026-08-31T19:40:00Z
staging: fxdknzrqjenzqcvnwqqq
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [N1, N2, N3, N4, N5, N6, N7, N8]
VEREDICTO: FAIL_P0
prefixo_fixtures: RTN-20260831T2019-
```

**Não corrigido. Produção não tocada. Fase 4 não iniciada.**

O ficheiro `tool/prompts/REDTEAM_BLIND_N_LIVE_STREAM_v1.md` **não existia** no repo; a onda N foi executada no mesmo contrato das ondas M/L/K (staging, cegueira, não corrigir), poço **directo**: Mux, LiveKit, keys, rifa, saco da live, chat, gorjetas.

Provas: `tool/redteam_blind_n_20260831T2019/pass{1,2,3,4,5}.json`.

Anti-atrofia: Pass 1 **não** repetiu Hub paused items, `batata_resolve_handle`, listagem `chat_media`, CORS, dual Session, mint pós-payout, plain→JSON, invite enum, pairing ended. 0% dessas classes. `resolve-mux-playback` em rascunho foi só residual (agora 404 `live_not_public`).

---

## Veredicto

A fronteira **Mux/LiveKit Edge** e a **tabela `lives`** aguentam: GRANT revogado mesmo ao dono (403); comprador não cria Mux; complete/token cruzados 403; `stream_key` inject 403; token publisher não lista rooms/egress LiveKit; gorjeta pending ≠ captura; rifa mint/prize JWT 403.

Falham a **autoridade do saco da live** e um IDOR de `stop_egress`:

1. **P0** — qualquer JWT que faça INSERT em `live_reservation_requests` com `seller_id = auth.uid()` (mesmo **não** sendo dono do directo) passa o trigger como «vendedor», grava `status=accepted`, põe o artigo `reserved_full` / `available_qty=0`. O **dono real** do directo **não consegue recusar** (`not_allowed`). Unidade bloqueada; comprador legítimo fica só `pending`.
2. **P2** — `livekit-mux-publish` `step=stop_egress` aceita `egress_id` arbitrário (não o da live). Com IDs fixture devolveu HTTP 200; não se provou parar um egress LiveKit real de outro vendedor.

Não é a classe saturada (paused items / dual Session / mint payout / plain→JSON).

---

## Contabilidade (Stripe TEST)

Nenhuma captura. Nenhuma Transfer. Wallets lab **sem Δ** (`seller=10.00`, `buyer=46.35`) após `batata_create_live_tip_pending` (99 €, `stripe_session_id=null`) + GET settle com `cs` forjado (Stripe 400). Session ≠ captura.

---

## Findings

### RTN-n5.spoof.seller_id · N5 / N8 · P0

**Título:** Cliente escolhe `seller_id=próprio` no INSERT da reserva e fica com a unidade aceite na live de outro vendedor; o dono não recupera.

**Actor:** seller2 JWT (`b5a2a77d-9389-487a-ae8f-11a5b0d05cb4`), conta vendedor fresca. O predicado do trigger é `NEW.seller_id = auth.uid()` — **não** cruza com `lives.seller_id` / `vendedor_id`.

**Passos**
1. Fixture: live do vendedor lab (`980f4fa1-…`), artigo `quantity=1`, `status=live`.
2. S2 `POST live_reservation_requests` com `live_id` da live A, `live_item_id` do artigo A, **`seller_id=<S2>`**, `buyer_id=<S2>`, `status=accepted`.
3. Stock RPC: `available_qty=0`, `reserved_accepted_qty=1`.
4. S2 `batata_process_live_reservation_request` `accept` → `ok=true`, `item_status=reserved_full`.
5. Dono real `process` `reject` → **`not_allowed`**.
6. Comprador lab INSERT saco → só `pending` (`pending_bag_qty=1`).
7. `batata_live_reservation_stripe_convert` JWT → 403 (função revogada). `create-payment-intent` neste body → 400 metadata. **Sem encomenda grátis / sem Δwallet.**

**Esperado:** `seller_id` imposto pelo dono da live; não-dono → `pending` + `buyer_id=JWT`; dono da live pode recusar.

**Obtido (pass4):** row `bb15b97a-…` `status=accepted`, `seller_id=S2`, live `4e436f88-…`, item `db432fdf-…`, stock `available_qty=0`.

**Obtido (pass5, reprodução):** row `1ab5f635-…` live `2ef2f36a-…` item `048472fd-…` `accepted`; dono `reject` `not_allowed`; stock `available_qty=0` `reserved_accepted_qty=1` `pending_bag_qty=1`.

**Controlo:** o mesmo INSERT com `seller_id` = dono real da live (pass3, S2) **é coerido para `pending`** (`01677f6a-…`). O buraco é o **spoof de `seller_id`**, não o INSERT pending genérico.

**Prova:** `pass4.json` `n5.spoof` + `n5.stock.after` + `n5.proc.s2`; `pass5.json` `spoof` + `owner.reject` + `stock`.

**Severidade:** P0 — autoridade de vendedor forjada + stock da live alheia consumido de forma persistida; classe em qualquer directo `live`/broadcasting. Não houve segunda venda paga (convert JWT fechado).

---

### RTN-n2.stop.idor · N4 · P2

**Título:** `stop_egress` aceita `egress_id` que não pertence à live do JWT.

**Actor:** vendedor dono da live A.

**Passos:** `POST livekit-mux-publish` `{step:stop_egress, live_id:<A>, egress_id:EG_RTN_B_20260831T2019}`.

**Esperado:** 403 se o egress não é da live A.

**Obtido:** 200 `stopped=EG_RTN_B_20260831T2019`, `active_egress_stopped=0`. A row B de fixture manteve o id (não era egress LiveKit real). Token publisher **não** lista egress (401 LiveKit). Sem prova de derrubar um stream alheio **real**.

**Prova:** `pass1.json` `n2.stop.foreign`.  
**Severidade:** P2 (IDOR de API; impacto = DoS de egress se o id for conhecido).

---

## Retractado

| ID tentado | Motivo |
|------------|--------|
| RTN-n1.device.tokens (P0, pass2) | `select=*` devolve rows com `seller_id` = **próprio** JWT (`bfcbeeee-…`), só `token_hash` (não há `device_token_plain`). Lab seller `n=0`. Pass3 filtro por colunas inválidas deu 400, não leak. |
| RTN-n7.tips.cross (P1, pass3) | A row `05c8b5e0-…` tem `seller_id=comprador lab` — gorjeta **recebida** pelo JWT. Filtro `seller_id≠me AND buyer_id≠me` → `[]`. |
| RTN-n5.bag.s2.accept (P1, pass3) | `seller_id` era o dono real → trigger coeriu `accepted`→`pending`. |
| RTN-n5.qty.rest (P2, pass3) | FOMO já devolve `available_qty`; REST `quantity` no player autenticado não é leak além do FOMO. |
| RTN-n7.tip.pending.cs | RPC devolve UUID mas grava `stripe_session_id=null` (ignora o `cs` do cliente). |

---

## Holds (fronteira aguentou)

| Lente | Ataque | Resultado |
|-------|--------|-----------|
| N1 | anon/buyer/S2/dono `GET lives` (incl. stream_key) | 401/403 permission denied |
| N1 | Hub `hub_lives_public` / discovery | sem `stream_key` / `mux_live_id` / egress |
| N1 | FOMO | agregados; sem keys |
| N2 | buyer/S2 PATCH/INSERT `lives`; buyer complete-mux; S2 complete-mux | 403 |
| N2 | buyer `create-mux-live` | 403 authz (antes da API Mux) |
| N2 | dono PATCH `mux_live_id` via REST | 403 (tabela `lives` revogada) |
| N3 | `resolve-mux-playback` draft | 404 `live_not_public` (residual M fechado neste freeze) |
| N4 | buyer/S2 LiveKit `step=token` | 403 |
| N4 | inject `stream_key` no egress | 403 |
| N4 | token dono → ListRooms / ListEgress / DeleteRoom B | 401 LiveKit |
| N5 | buyer `batata_update_live_item` / mark sold / ensure_draft / PATCH item | not_found / not_allowed / 0 rows |
| N5 | buyer queue-for-live | not_allowed |
| N6 | buyer create/draw/close raffle; S2 cancel | not_allowed |
| N6 | `batata_award_live_raffle_tickets` / `create_raffle_prize_order` | 403 execute |
| N6 | INSERT winners/entries; PATCH tickets | RLS / 0 rows |
| N6 | join ×2 | `duplicate=true`, tickets 1→1 |
| N7 | buyer `batata_live_system_message` / INSERT `kind=system` ou chat | not_allowed / RLS |
| N7 | OCR sem `x-device-token` | 401 |
| N7 | settle tip `cs` forjado | 400 Stripe; Δwallet 0 |
| N8 | convert Stripe JWT | 403 função |

---

## Tácticas cumpridas

1. Anon + JWT comprador + S2 + dono em lives/Hub/FOMO/rifa/saco.  
2. Edges Mux/LiveKit/tip/OCR/PI com body hostil (sem create Mux real — quota).  
3. Stream keys: tabela + views + inject egress.  
4. Rifa: join, mint RPC, prize, REST entries.  
5. Saco: INSERT pending vs spoof accepted; stock RPC; reject do dono.  
6. Session gorjeta ≠ captura.  
7. Flutter ≠ fronteira (REST + RPC + Edge).

**Lacuna honesta:** não se pagou Stripe TEST numa reserva spoofed (convert JWT fechado; PI sem metadata). O P0 é stock/autoridade, não mint de carteira.

---

## Fixtures deixadas em staging

- Auth `rtn-20260831t2019-{b2,s2}@fleaber.test`.  
- Lives RTN marcadas `ended` onde os scripts chamaram `endLives`.  
- Reservas spoof `bb15b97a-…` (pass4) e `1ab5f635-…` (pass5) `accepted` em lives já terminadas; saco pending do comprador lab.  
- Tip pending `7e3899bf-…` 99 € **não pago**.

Não foi feito levantamento Connect nem captura. **Não tocar produção.**
