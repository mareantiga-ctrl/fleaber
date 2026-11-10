# FROZEN_REPORT — RED TEAM CEGO CL

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 1
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 1

```
1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_CL_LIVE_POS_CDCI_v1
FROZEN_AT: 2026-09-06T12:26:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CL1, CL2, CL3, CL4, CL5, CL6, CL7, CL8]
probes_na_tabela: 47 (≥30)
VEREDICTO: FAIL_P2
prefix: RTCL-20260906T1318
staging: fxdknzrqjenzqcvnwqqq
```

Exactos CDCI **não contados** (HOLD): `last one` · `foi embora` · `🛑1 left` (colapsa a `1 left`) · `going going gone` (contém `gone`) · `playback_id` / `livekit_room_name` REST 403 · `mux_playback_id` REST 403 · resolve-mux unpublished `404 live_not_public` · sender_label `Sistema` em chat (não retestado como finding; residual CF/CDCI).

---

## Missão

FOMO multi-língua, staff falso, hitch/convert, playback fora do revoke exacto?

**Resposta:** o denylist CDCI cobre PT/EN compacto (`last one`, `foi embora`, `1 left`, `gone`) mas **não** IT/DE/FR nem sinonímia extra (`final call`, `quase a acabar`, `ultimo disponibile`, `nur noch einer`). 22/24 frases da matriz persistem como `kind=system` `sender_label=Sistema` e o **Hub público** (comprador e anónimo) vê as 22. Staff self-promote, hitch qty>stock, convert sem PI / PI alheio, end∥accept e Mux REST/Edge **não** passaram.

---

## Findings abertos

### CL-P2-01 — FOMO IT/DE/FR/extra persiste no system message e no Hub

- **Sev:** P2 · **Lente:** CL2 · **Actor:** seller JWT (`batata_live_system_message`)
- **Pré:** denylist CDCI em `batata_live_system_message` (PT/EN + fold hífen/espaço + `foi embora` / `last one` / `1 left` / `gone`). Sem convert pago nesta live.
- **Repro:**
  1. Live `status=live` `is_active=true` (seller Hub publicado)
  2. `POST /rest/v1/rpc/batata_live_system_message` com cada frase da matriz (seller JWT)
  3. `GET hub_live_messages_public?live_id=eq.{id}` (buyer JWT e anon)
- **Esperado:** `ok=false` `purchase_announce_via_broadcast_only`
- **Obtido:**
  - Residual CDCI: `last one` · `foi embora` → `ok=false` (**não contar**)
  - Extra colapso: `🛑1 left` · `going going gone` → `ok=false` (**não contar**)
  - **22 FAIL:** `ultimo pezzo` · `esaurito` · `già venduto` · `non c'è più` · `preso` · `e s a u r i t o` · `letztes Stück` · `ausverkauft` · `schon weg` · `kein Lager` · `verkauft` · `a u s v e r k a u f t` · `dernier article` · `épuisé` · `plus de stock` · `déjà pris` · `vendu` · `e p u i s e` · `final call` · `quase a acabar` · `ultimo disponibile` · `nur noch einer` → `200 {"ok": true}`
  - Service + seller: 22 rows `kind=system` `sender_label=Sistema`
  - Hub buyer **e** anon: as mesmas 22 rows (`confirm_hub_msgs.json`)
  - REST `live_messages` buyer: `200 []` (SELECT na tabela sujeito a RLS `lives`; o furo visível ao público é a view Hub)
  - Stock `available_qty` inalterado; zero orders pagas nesta live
  - Helper zero-perms na mesma frase IT: `not_allowed` (não é este finding)
- **Impacto:** o vendedor publica no directo, com etiqueta oficial Sistema, que o artigo «esaurito / ausverkauft / épuisé / final call» **sem** reserva aceite nem order paga. Espectadores no Hub vêem FOMO oficial. Não mexe stock nem caixa.
- **Prova:** `pass1.json` `persisted_new` · `confirm_hub_msgs.json`

Uma classe, 22 payloads — **conta 1**.

---

## HOLD (não contar)

| Lente | Prova | Resultado |
|-------|--------|-----------|
| CL2 | `last one` / `foi embora` | `purchase_announce_via_broadcast_only` |
| CL2 | `🛑1 left` / `going going gone` | recusados (colapso `1 left` / `gone`) |
| CL1 | B1 buyer INSERT `seller_helpers` na loja V | RLS 403 |
| CL1 | B2 helper0 PATCH `can_manage_chat` | `200 []`; perms inalteradas |
| CL1 | helper chat PATCH `can_mark_items_sold` | `200 []` |
| CL2 | B3 helper0 RPC `ultimo pezzo` | `not_allowed` |
| CL1 | C2 `stripe_convert` sem PI | `403 permission denied for function` |
| CL1 | C3 reconcile PI live A → res live B | `403 convert_requires_paid_order` |
| CL4 | C1 hitch marketplace+live_only qty=1 | 2º accept `qty_exceeds_stock` |
| CL5 | C1b `requested_qty=5` item qty=1 | coerção a 1; accepted 1 |
| CL6 | C4 `end_live` ∥ accept | end ganhou; accept `live_ended` |
| CL6 | accept depois de ended | `live_ended` |
| CL3 | FOMO vs stock | `available_qty` inalterado |
| CL8 | FOMO → order paga | zero pago |
| CL7 | D3 `playback_id` / `livekit_room_name` unpublished | REST 403 (residual CDCI) |
| CL7 | D3 `mux_playback_id` / VOD / asset / stream_key / `mux_live_id` / `livekit_egress_id` | REST 403 |
| CL7 | D3 SELECT `*` unpublished | 403 |
| CL7 | D2 resolve-mux unpublished buyer/anon | `404 live_not_public` |
| CL7 | D1 realtime `postgres_changes` lives | join ok depois `Unable to subscribe` — payload sem playback |

**Não finding:** buyer `POST seller_helpers` com `seller_id=próprio` (201) — a policy permite convidar ajudantes na própria identidade, não na loja do vendedor alvo. Row de fixture desactivada no cleanup.

---

## TABELA DE PROVAS

| # | ID | Payload | HTTP/BD | HOLD\|FAIL |
|---|----|---------|---------|------------|
| 1 | p1.fomo.residual.last_one | `last one` | 200 `purchase_announce_via_broadcast_only` | HOLD |
| 2 | p1.fomo.residual.foi_embora | `foi embora` | 200 `purchase_announce_via_broadcast_only` | HOLD |
| 3 | p1.fomo.matrix.it_ultimo_pezzo | `ultimo pezzo` | 200 `ok:true` + Hub system Sistema | FAIL |
| 4 | p1.fomo.matrix.it_esaurito | `esaurito` | 200 `ok:true` + Hub system Sistema | FAIL |
| 5 | p1.fomo.matrix.it_gia_venduto | `già venduto` | 200 `ok:true` + Hub system Sistema | FAIL |
| 6 | p1.fomo.matrix.it_non_ce_piu | `non c'è più` | 200 `ok:true` + Hub system Sistema | FAIL |
| 7 | p1.fomo.matrix.it_preso | `preso` | 200 `ok:true` + Hub system Sistema | FAIL |
| 8 | p1.fomo.matrix.it_esaurito_spaced | `e s a u r i t o` | 200 `ok:true` + Hub system Sistema | FAIL |
| 9 | p1.fomo.matrix.de_letztes_stuck | `letztes Stück` | 200 `ok:true` + Hub system Sistema | FAIL |
| 10 | p1.fomo.matrix.de_ausverkauft | `ausverkauft` | 200 `ok:true` + Hub system Sistema | FAIL |
| 11 | p1.fomo.matrix.de_schon_weg | `schon weg` | 200 `ok:true` + Hub system Sistema | FAIL |
| 12 | p1.fomo.matrix.de_kein_lager | `kein Lager` | 200 `ok:true` + Hub system Sistema | FAIL |
| 13 | p1.fomo.matrix.de_verkauft | `verkauft` | 200 `ok:true` + Hub system Sistema | FAIL |
| 14 | p1.fomo.matrix.de_ausverkauft_spaced | `a u s v e r k a u f t` | 200 `ok:true` + Hub system Sistema | FAIL |
| 15 | p1.fomo.matrix.fr_dernier_article | `dernier article` | 200 `ok:true` + Hub system Sistema | FAIL |
| 16 | p1.fomo.matrix.fr_epuise | `épuisé` | 200 `ok:true` + Hub system Sistema | FAIL |
| 17 | p1.fomo.matrix.fr_plus_de_stock | `plus de stock` | 200 `ok:true` + Hub system Sistema | FAIL |
| 18 | p1.fomo.matrix.fr_deja_pris | `déjà pris` | 200 `ok:true` + Hub system Sistema | FAIL |
| 19 | p1.fomo.matrix.fr_vendu | `vendu` | 200 `ok:true` + Hub system Sistema | FAIL |
| 20 | p1.fomo.matrix.fr_epuise_spaced | `e p u i s e` | 200 `ok:true` + Hub system Sistema | FAIL |
| 21 | p1.fomo.matrix.ex_stop_1left | `🛑1 left` | 200 `purchase_announce_via_broadcast_only` | HOLD |
| 22 | p1.fomo.matrix.ex_going_going_gone | `going going gone` | 200 `purchase_announce_via_broadcast_only` | HOLD |
| 23 | p1.fomo.matrix.ex_final_call | `final call` | 200 `ok:true` + Hub system Sistema | FAIL |
| 24 | p1.fomo.matrix.ex_quase_acabar | `quase a acabar` | 200 `ok:true` + Hub system Sistema | FAIL |
| 25 | p1.fomo.matrix.ex_ultimo_disponibile | `ultimo disponibile` | 200 `ok:true` + Hub system Sistema | FAIL |
| 26 | p1.fomo.matrix.ex_nur_noch_einer | `nur noch einer` | 200 `ok:true` + Hub system Sistema | FAIL |
| 27 | p2.B1.buyer.insert.helper | POST seller_helpers loja V | 403 RLS | HOLD |
| 28 | p2.B2.helper.self_escalate | PATCH helper0 `can_manage_chat` | 200 `[]` perms iguais | HOLD |
| 29 | p2.B3.helper0.fomo | helper0 RPC `ultimo pezzo` | 200 `not_allowed` | HOLD |
| 30 | p2.C1.hitch.qty_stock | hitch marketplace+live_only qty=1 | 2º `qty_exceeds_stock` | HOLD |
| 31 | p2.C1b.qty.over_stock | requested_qty=5 item qty=1 | accepted qty **1** | HOLD |
| 32 | p2.C2.convert.nopi | stripe_convert sem PI | 403 permission denied | HOLD |
| 33 | p2.C3.convert.pi_alheio | reconcile PI liveA → res liveB | 403 `convert_requires_paid_order` | HOLD |
| 34 | p2.C4.end_parallel_accept | end_live ∥ PATCH accepted | accept `live_ended`; live ended | HOLD |
| 35 | p3.D1.realtime.playback | ws postgres_changes lives + PATCH playback | subscribe error; sem playback no payload | HOLD |
| 36 | p3.D2.resolve.buyer.unpub | resolve-mux-playback unpublished buyer | 404 `live_not_public` | HOLD |
| 37 | p3.D2.resolve.anon.unpub | resolve-mux-playback unpublished anon | 404 `live_not_public` | HOLD |
| 38 | p3.D3.buyer.playback_id | GET lives `playback_id` unpublished | 403 | HOLD |
| 39 | p3.D3.buyer.livekit_room_name | GET lives `livekit_room_name` unpublished | 403 | HOLD |
| 40 | p3.D3.buyer.mux_live_id | GET lives `mux_live_id` unpublished | 403 | HOLD |
| 41 | p3.D3.buyer.livekit_egress_id | GET lives `livekit_egress_id` unpublished | 403 | HOLD |
| 42 | p3.D3.buyer.mux_stream_key | GET lives `mux_stream_key` unpublished | 403 | HOLD |
| 43 | p3.D3.buyer.stream_key | GET lives `stream_key` unpublished | 403 | HOLD |
| 44 | p3.D3.buyer.mux_playback_id | GET lives `mux_playback_id` unpublished | 403 | HOLD |
| 45 | p3.D3.buyer.mux_vod_playback_id | GET lives `mux_vod_playback_id` unpublished | 403 | HOLD |
| 46 | p3.D3.buyer.mux_asset_id | GET lives `mux_asset_id` unpublished | 403 | HOLD |
| 47 | p3.D3.wildcard.leak | GET lives `select=*` unpublished | 403 | HOLD |

`probes_na_tabela: 47`. Matriz FOMO 24/24 corrida. Residual CDCI = 2 linhas.

---

## Invariantes A–L (poço live)

| ID | Resultado |
|----|-----------|
| A Stripe cobra contrato | NÃO COMPROVADO neste poço (sem Session TEST) |
| B Cliente não define preço/qty | HOLD qty (requested_qty=5 → 1) |
| C Release/refund ≤ fundos | NÃO COMPROVADO (fora do poço) |
| D Uma unidade ≠ duas vendas | HOLD hitch 2º `qty_exceeds_stock` |
| E JWT não cria saldo/PI | HOLD convert/reconcile |
| F Off-platform ≠ saldo | HOLD FOMO é mensagem, não caixa |
| G Refund ≤ captura | NÃO COMPROVADO |
| H Parties coerentes | HOLD reconcile PI live errada |
| I Uma intenção payout ≤ 1 Transfer | N/A |
| J Intenções distintas | N/A |
| K Catálogo posterior ≠ contrato | HOLD |
| L Offer/bundle/reserva só com autoridade | HOLD end∥accept; helper perms; helper0 FOMO |

---

## Checklist 28

1. P0 aberto encontrado: NÃO
2. Quantos P0: 0
3. P1 aberto encontrado: NÃO
4. Quantos P1: 0
5. Buyer manipula preço autoritativo: NÃO COMPROVADO
6. Buyer manipula qty autoritativa: NÃO (coerção a 1)
7. Seller falsifica pagamento plataforma: NÃO
8. JWT cria saldo/fundos: NÃO
9. Refund excede captura: NÃO COMPROVADO
10. Release+refund cria dinheiro líquido: NÃO
11. Payout duplica Transfer indevidamente: NÃO
12. Stock=1 duas vendas válidas: NÃO
13. Stock=1 duas capturas líquidas permanentes: NÃO COMPROVADO
14. Bypass capacidade/reserva: NÃO (hitch/end HOLD)
15. Cross-user financeiro: NÃO
16. Cross-user dados sensíveis: NÃO (playback/Mux HOLD)
17. Buyer assume seller/admin: NÃO (B1 INSERT helper loja V 403; B2 perms intactas)
18. Seller assume buyer/admin: NÃO
19. Reviews forjadas/duplicadas: NÃO
20. RPC SECURITY DEFINER perigoso executável: NÃO (convert sem GRANT; broadcast não exercitado além C2/C3)
21. RLS crítico quebrado: NÃO (FOMO é denylist de copy, não RLS de caixa)
22. Edge confia autoridade do cliente no total: NÃO
23. Conclusão crítica NÃO COMPROVADA: NÃO (convert sem PI comprovadamente bloqueado)
24. Regressão funcional (código alterado por ti): NÃO
25. Último passe nova classe P0/P1: NÃO
26. Saturação: SIM (matriz 24/24; poços B/C/D; lentes 8/8)
27. Produção tocada: NÃO
28. Fase 4 iniciada: NÃO

Poços CL exercitados: A FOMO matriz 24=SIM · B staff=SIM · C hitch/convert/race=SIM · D Mux/realtime=SIM  
Lentes 8/8: CL1 convert · CL2 FOMO · CL3 stock · CL4 hitch · CL5 qty · CL6 race · CL7 Mux · CL8 caixa  
ATROFIA (só redescobriu exactos CDCI): NÃO — classe nova IT/DE/FR/extra

VEREDICTO: **FAIL_P2**

**NÃO CORRIGIR.**

---

## Artefactos

- `tool/redteam_blind_cl_20260906T1318/pass1.json` — matriz FOMO 24 + residual
- `tool/redteam_blind_cl_20260906T1318/pass2.json` — B1–B3 staff · C1–C4 hitch/convert/race
- `tool/redteam_blind_cl_20260906T1318/pass3.json` — D1 realtime · D2 resolve-mux · D3 irmãs
- `tool/redteam_blind_cl_20260906T1318/confirm_hub_msgs.json` — 22 rows Hub `kind=system`
- Lives de fixture `RTCL-20260906T1318*` → `status=ended` `is_active=false` (cleanup)
