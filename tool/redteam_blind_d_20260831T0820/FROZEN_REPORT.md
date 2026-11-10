```
AUDITOR: REDTEAM_BLIND_D_COSTURA_v2
FROZEN_AT: 2026-08-31T07:35:00Z
production_touched: false
fase4: false
corrections_applied: false
```

# RED TEAM CEGO D v2 — logística / devolução / conjunto / auto-feedback

Prefixo fixtures: `RTD2-20260831T0820-`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · service_role só setup / observação / cleanup.

Atores: B1 `bfcbeeee-…7c96` · S1 `980f4fa1-…9588` · B2 `ab6ed674-…f1b6` · S2 `bdd06307-…f31e`.

---

## Mapa de ataque (costura D2)

| Zona | LIVE observado |
|------|----------------|
| Etiqueta / tracking | Sem colunas `tracking_*` / `carrier` / `shipping_label_url` em `orders` (PGRST204). «Etiqueta» Flutter = delay 2s + `PATCH enviado`. `return_label_url` em `order_disputes` é texto livre JWT. |
| Pós-pago FSM | `pago` → seller `enviado` (honesto). Buyer **não** marca `enviado`. Buyer **marca `entregue`** a partir de `pago` (atalho). `pago`→`concluido` carrier/null continua bloqueado. Seller **reabre** `concluido`→`enviado`. |
| Devolução | `pedido_devolucao` a partir de `pago` revertido. **`em_devolucao` e `devolucao_entregue` a partir de `pago` persistem sem disputa.** `devolvida` exige disputa não recusada (seller JWT). Stock restore + wallet buyer no trigger `devolvida`. |
| Partial refund | RPC `batata_process_partial_refund_dispute` buyer-only; exige oferta seller (`set_by` + percent). Forja buyer da oferta **não persiste** (percent/set_by ficam null). Oferta seller 50% → wallet split; **sem** `stripe_refund_id`. |
| Conjunto / saco | `bundle_id` mutável pós-pago (FK `product_bundles`). Mass `PATCH` por `bundle_id` (Flutter). Linha hitchada não paga **não** sobe a `concluido`. Saco partilha PI; refund linha A em `pago` deixa B intacta. |
| Auto-feedback | RPC JWT/anon `42501`. JWT **grava** `auto_feedback_processed_at` e `wallet_release_processed_at`. Cron DEFINER (service_role observação). `completed_at` backdate na transição **não** persiste (now()). |
| MB WAY | Seller `PATCH pago` off-platform: stock 3→2, `amount_paid_cents` null. `enviado`→`concluido`→release **Δwallet 0**. |
| Settle vs envio | `PATCH shipping_method` pós-pago → 403 `order_shipping_frozen_after_payment`. GET settle Session inventada → 400. |
| Identidade | B1 PATCH order B2 → `[]`. S2 PATCH order B1 → `[]`. Card JSON com `order_id` alheio → 400 `chat_system_card_order_chat_mismatch`. B2 release order B1 → `false`. |
| Edges `verify_jwt=false` | webhook sem sig 400; egress 401; OCR 401; meta 400; checkout POST sem metadata 400. |

Capturas TEST (harness `setup_paid_order` / `setup_paid_bag`, **não** actor): PI `pm_card_visa` 590¢ single; saco 1115¢ duas linhas.

---

## Findings P1

### RTD2-0820-D2-1-03 / D2-1-06 — P1 — Buyer `pago`→`entregue` salta o envio (e abre disputa)

**Actor:** B1 JWT.  
**Pré:** Order plataforma `pago` 590¢, `shipping_method=null` (não é mão). Seller nunca marcou `enviado`.  
**Request:** `PATCH {status:entregue}` depois `PATCH {status:concluido}` + RPC `batata_release_seller_wallet_for_order`. Variante: INSERT `order_disputes` reason=`danificado` ainda em `entregue`.  
**Antes (order `a0af17d1-…da38` / PI `pi_3UAPbeH7FWYUN3jh1t0fm9kg`):** `status=pago`.  
**Depois:** `entregue` → `concluido` (`completed_at` = now, não backdate). Release `true`. Wallet S1 **+5.00**. Disputa em `entregue` (order `671fd1c6-…1c0ea`) INSERT **201**.  
**Impacto:** O fecho v1 (`pago`→`concluido` carrier) não cobre o verbo `entregue`. Hold de envio + janela de disputa ficam do lado do comprador. Não é mint: captura Stripe 590¢ cobre o crédito 5.00 (taxa ~0,90).  
**Repro:** `setup_paid_order` → buyer `PATCH entregue` → `PATCH concluido` → RPC release; ou INSERT disputa em `entregue`.  
**Sev:** P1 (logística + payout sem `enviado`). Não P0: 1 captura : 1 crédito.

Não é a classe v1 `pago`→`concluido` (essa continua a falhar em carrier/null). É **atalho por `entregue`**.

### RTD2-0820-D2-1-05 / D2-1-05b — P1 — Seller reabre `concluido`→`enviado` depois do payout e bloqueia disputa

**Actor:** S1 JWT.  
**Pré:** `pago` → seller `enviado` (honesto) → buyer `concluido` → release `true` (+5.00).  
**Request:** `PATCH {status:enviado}`. Depois buyer INSERT `order_disputes`.  
**Depois (order `be4363fe-…274fa`):** `status=enviado`, `wallet_release_processed_at` preenchido. Disputa **403** RLS (exige `concluido`/`entregue` **e** `wallet_release_processed_at is null`). B2 RPC release `false`.  
**Impacto:** Dinheiro já na wallet do vendedor; o comprador perde a janela de disputa. `completed_at` **não** é limpo na saída de `concluido` (LIVE).  
**Repro:** enviado→concluido→release→seller `PATCH enviado`→INSERT disputa.  
**Sev:** P1 (autoridade pós-caixa). Mass `PATCH enviado` por `bundle_id` reproduz o mesmo (saco A já libertado voltou a `enviado`).

### RTD2-0820-D2-2-02 — P1 — Buyer `pago`→`em_devolucao` (e `devolucao_entregue`) sem disputa

**Actor:** B1 JWT.  
**Pré:** order `pago` 590¢, sem `order_disputes`.  
**Request:** `PATCH em_devolucao`; depois `PATCH devolucao_entregue`.  
**Depois (order `3a556cb6-…8daf92`):** ambos os estados **persistem**. Seller `PATCH devolvida` **não** avança (fica `devolucao_entregue`; qty inalterada; Δwallet 0) — falta disputa.  
**Impacto:** FSM de devolução acessível sem disputa nem envio. Sem Δ sozinho; o fecho `devolvida` ainda exige disputa.  
**Repro:** `setup_paid_order` → `PATCH em_devolucao`.  
**Sev:** P1 (logística). Race `enviado`∥`em_devolucao`: ambos 200; estado final `enviado` (seller ganhou).

### RTD2-0820-D2-5-03 — P1 — JWT grava flags de payout (`auto_feedback_processed_at`, `wallet_release_processed_at`)

**Actor:** B1 JWT.  
**Pré:** order `concluido`, wallet ainda não libertada.  
**Request:** `PATCH {auto_feedback_processed_at: now()}` **ou** `PATCH {wallet_release_processed_at: now()}`.  
**Depois:**  
- `auto_feedback_processed_at` persiste; seller RPC release `false`; B2 `false`; `wallet_release` continua null; ΔS=0. Cron (processed_at NOT NULL) saltaria esta linha. Buyer **ainda pode** chamar release.  
- `wallet_release_processed_at` persiste **sem** crédito (order `7b3f4ea4-…e5df58c`). A RPC de release vê a flag e devolve `false` para todos — payout congelado.  
**Impacto:** Comprador retém o fundo de plataforma (captura Stripe já feita) e impede o cron/seller de libertar. Com a flag `wallet_release_*` o próprio buyer também já não liberta.  
**Repro:** concluido → PATCH `wallet_release_processed_at=now()` → RPC release `false`, Δwallet 0.  
**Sev:** P1 (DoS económico / hold permanente). Não P0: não cria saldo extra.

`completed_at=2020-01-01` na transição para `concluido` **não** persiste (forçado a now()). PATCH isolado de `completed_at` também revertido. `returned_at=2020-01-01` **persiste** (P2).

---

## Findings P2

### RTD2-0820-D2-9-02 — P2 — `bundle_id` gravável depois de `pago`

B1/S1 PATCH `bundle_id` em linhas de saco já capturadas → 200, FK aceite. Unpaid hitchada **não** vira `concluido` no mass PATCH. Order alheia B2/S2 **não** hitcha (`bundle_id` null). Sem Δ. Abre mass `enviado` no mesmo UUID (encadeia D2-1-05).

### RTD2-0820-D2-1-07 — P2 — `return_label_url` forjada

Buyer PATCH disputa `return_label_url=https://evil.example/label.pdf` → persistido. Sem Edge de etiqueta real; UI pode mostrar URL hostil. Sem Δ.

### RTD2-0820-D2-4 — P2 — confirmação 1 de N no saco (não oversell)

Saco 2 linhas, mesmo PI `pi_3UAPbmH7FWYUN3jh0YjT7eaT`. Buyer `concluido` só em A + release → S1 **+2.57**; B continua `pago` 780¢. **Não é mint.** Refund de A ainda em `pago` (pass2, PI `pi_3UAPf2H7FWYUN3jh1dYN76ry`): A `cancelado` + restock 2→3 + `re_3UAPf2…`; **B intacta** (`pago`, qty 2, stock_units=1). Independência de linha do saco aguenta-se.

### D2-3 oferta parcial 50% — P2 / by design

Seller PATCH oferta 50% persiste. RPC `true`. B1 **+2.95** · S1 **+2.05** · soma 5.00 (taxa 0,90 na plataforma). `stripe_refund_id` null — residual Stripe = captura ainda held, não segundo crédito. Forja buyer da oferta **não** grava percent/set_by; RPC `dispute_refund_offer_required`. B2 RPC `42501 not_allowed`.

### D2-6 MB WAY — sem mint

Seller `pago` MB WAY: stock 3→2. Release após `concluido` → **Δ 0** (`amount_paid_cents` null). Card `reservation_order_shipped` INSERT 201 no chat próprio (alinhado ao FSM).

---

## Races

| X ∥ Y | Resultado |
|-------|-----------|
| seller `enviado` ∥ buyer `em_devolucao` (status `pago`) | Ambos HTTP 200; estado final **`enviado`**. Um estado, não dois efeitos económicos. |

## Stripe TEST (amostra)

| PI | Resultado |
|----|-----------|
| `pi_3UAPbeH7FWYUN3jh1t0fm9kg` | pago → entregue → concluido → release +5.00 (P1 D2-1-03) |
| `pi_3UAPbgH7FWYUN3jh0cKQXoTN` | pago → (salto devolução) → race enviado → concluido → disputa → devolvida; B1 wallet +5.90; stock 0→1; sem refund Stripe |
| `pi_3UAPbmH7FWYUN3jh0YjT7eaT` | saco A+B; confirm A release +2.57; mass enviado |
| `pi_3UAPf2H7FWYUN3jh1dYN76ry` | saco; refund A 335¢; B intacta |
| `pi_3UAPezH7FWYUN3jh1uzpMqCW` | enviado→concluido→release +5.00→reopen enviado; disputa 403 (P1 D2-1-05b) |
| `pi_3UAPf8H7FWYUN3jh1phKaCzn` | disputa + oferta 50% → wallet 2.95 / 2.05; Stripe residual |
| `pi_3UAPhqH7FWYUN3jh0vPIgYwX` | concluido; PATCH `wallet_release_processed_at`; refund-order 403 `order_refund_blocked_status` |

Webhooks hostis: não exploráveis sem assinatura.

## Contabilidade

SESSION ≠ captura ≠ net. Créditos wallet observados nas linhas P1/P2 **cabem** nas capturas TEST correspondentes (5.00 sobre 5.90; 2.57 sobre 3.35). Refund saco A = 335¢ Stripe, B não duplicada.

**Nota de observação (não finding, não actor):** no pass 1 chamou-se `batata_generate_auto_feedback(p_now=2099)` com **service_role** (observação). A função DEFINER processou dezenas de `concluido` antigos (RPC devolveu `115`). JWT/anon da mesma RPC = 401/403. O Δ wallet S1 agregado da sessão (~147) **não** é mint do atacante JWT — inclui esse cron. Não repetido nos passes 2/3/3b.

## Lacunas

- Sem `STRIPE_SECRET_KEY` local: não se inspecionou Transfer Connect / net dashboard além dos IDs de PI/refund devolvidos pelas Edges.  
- Conjunto **aceite UI** (N orders `reservado` via `fulfillAcceptedBundle`) não foi pago ponta-a-ponta; o saco + hitch `bundle_id` cobre a superfície mass PATCH.  
- Reason `nao_recebido` falha check constraint; `danificado` é o caminho válido.

## Anti-atrofia

Findings **não** são a lista v1 (dual Session, hold pending, tip/rifa, `pago`→`concluido` directo, shipping null→mão, seller fecha disputa, UPDATE card JSON, offer amount / bag unlist). `pago`→`concluido` carrier **continua bloqueado**; o P1 é o verbo **`entregue`**. `refund-order` após `concluido`/`enviado` = **403** (gate LIVE).

Lentes D2 exercitadas: D2-1, D2-2, D2-3, D2-4, D2-5, D2-6, D2-7, D2-8, D2-9, D2-10.  
Último ciclo (pass 3b): flags `wallet_release_*` / `returned_at` / label URL / refund-order 403 — **sem classe nova** P0/P1 (flags = mesma classe D2-5-03).

---

```
P0 encontrados: 0
P1 encontrados: 4
P2 encontrados: 5

Existe criação líquida de dinheiro: NÃO
Existe oversell válido: NÃO
Existe bypass de identidade: NÃO
Existe cross-user: NÃO
Existe race P0/P1: NÃO
Existe cadeia costura→caixa P0/P1: SIM
Existe falha logística/devolução explorável: SIM
Existe bundle/multi-pedido P0/P1: NÃO

Dois buyers + dois sellers: SIM
Fluxo pós-pago (envio ou devolução): SIM
Último ciclo nova classe P0/P1: NÃO
ATROFIA: NÃO
SATURAÇÃO: SIM
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: FAIL_P1
```
