# RED TEAM CEGO E — ÓRBITA
**AUDITOR:** REDTEAM_BLIND_E_ORBITA_v1  
**FROZEN_AT:** 2026-08-30T18:14:00Z  
**Projecto:** staging `fxdknzrqjenzqcvnwqqq`  
**prefixo:** `RTE-20260830T1859`  
**production_touched:** false  
**fase4:** false  
**corrections_applied:** false  

Stripe: **TEST** (`cs_test_…` / `pi_3UADDl…`). Produção não tocada.

---

## Mapa de ataque (órbita)

| Zona | Superfície viva | Actor | Resultado |
|------|-----------------|-------|-----------|
| Hub views / handle | `hub_*`, `batata_resolve_handle`, FOMO | anon | Sem PII; unpublished fixture invisível; Hub não lista o unlist |
| Crons | `auto_feedback`, `expire_product_offers`, `livekit_egress_cleanup`, `release_wallet`, `tick_raffle` | anon / JWT | EXECUTE recusado (401/403) ou corpo `false`/`not_allowed` |
| Notificações | `user_notifications`, `notifications_view`, device tokens | buyer / buyer2 | Sem INSERT cruzado; sem tokens alheios |
| Bundle / saco | `seller_bundle_discounts`, `product_bundles`, Edge `bag_checkout` | buyer | Escrita hostil recusada; **saco ignora unlist** |
| Connect / banco | Edge GET/POST `create-connect-account`, `wallets.stripe_account_id`, IBAN | buyer | `user_id` spoof recusado; PATCH wallet sem mutação; IBAN não vaza |
| Soft states | `is_sold`, `list_on_marketplace`, `vacation_mode` | seller + buyer | Hold JWT bloqueia sold/unlist **novo**; **hold antigo + unlist + saco = Session + captura** |
| Return / deep link | `web_return_origin`, GET session_id | anon | Evil remoto recusado; localhost/127.0.0.1 na allowlist (Hub local) |
| Grafo | follows / favorites | JWT | Sem impersonação; burst sem DoS |
| Email / invite | `batata_find_user_id_by_email`, invite staff | buyer | Sem enumeração extra / invite recusado |

Flutter e Hub web **não** são fronteira: o gap está na Edge `create-payment-intent` (ramo `bag_checkout`).

---

## Finding P1 — E6-BAG-UNLIST-CAPTURE

**Título:** Produto retirado da vitrine (`list_on_marketplace=false`) ainda é cobrado no **saco**; o checkout de **um** artigo é bloqueado.

**Pré-condição**
1. Vendedor lista artigo (qty=2, 11,00 €).
2. Comprador cria hold JWT `reserva_pendente` (ainda listado).
3. Vendedor faz unlist (`list_on_marketplace=false`). O Hub deixa de o mostrar (`hub_products_public` → 0 linhas). `is_sold` continua `false`.

**Repro**
```
POST create-payment-intent  { order_id, buyer_id, shipping_method: mao }
  → 400 "Checkout blocked: product is not listed."

POST create-payment-intent  { bag_checkout: true, bag_lines: [{order_id}] }
  → 200 checkout.stripe.com  amount_total=1220
```

Cartão TEST `4242…` → captura.

**Estado final (BD staging)**

| Sítio | Antes | Depois |
|-------|--------|--------|
| Produto `4f1dfa03-a189-4dcb-a8e1-0630899a7f5b` | qty 2, listed true | qty **1**, listed **false**, is_sold false |
| Encomenda `25be8a2d-281a-4d43-80ab-1defa3619d9f` | `reserva_pendente`, amount_paid null | **`pago`**, `amount_paid_cents=1220`, PI `pi_3UADDlH7FWYUN3jh1xAUihvR`, refund null |
| Wallet vendedor | 55,53 € | 55,53 € (crédito só após concluído — esperado) |
| Stripe TEST | Session `cs_test_a1w6QyEc…` | **captura 12,20 €** (11,00 + protecção); sem refund |
| Hub / anon | — | Hub vazio para este SKU; tabela `products` anon 401 |

**Porquê P1:** o comprador paga (Stripe net) e consome stock de um artigo que a loja pública e o checkout simples já tratam como morto. Não é mint de wallet; é venda de morto / órbita→caixa.

**Gap de código (observação, sem patch):** o ramo *single* da Edge consulta `list_on_marketplace`; o ramo *bag* só chama `batata_product_checkout_available` (bloqueia `is_sold`, **não** unlist). O hold JWT só corre no INSERT; unlist posterior não invalida o hold.

**Variante mesma classe (não paga):** saco misto (linha unlist + linha ainda listada) → Session `cs_test_a12obCpl…` **2144** cêntimos. Mesma falha, dois SKUs.

---

## P3 (não sobem sozinhos)

**E7 localhost / 127.0.0.1** — GET `create-connect-account?web_return_origin=http://localhost:9999` → 303 `http://localhost:9999/wallet`. Allowlist explícita para Hub local. **Não** é open redirect remoto (`evil.example`, `fleaber.pt.evil.com` recusados). Residual de desenho, não P1.

**E6 vacation_mode** — vendedor em férias ainda abre Session (não pago nesta ronda). UX / política, não captura nesta prova.

**FOMO** — anon vê `available_qty` exacto. Agregado de vitrine, sem PII.

---

## Lentes E — o que não passou a P0/P1

| # | Lente | Exercitada | Nova classe P0/P1 |
|---|--------|------------|---------------------|
| E1 | Vitrine | SIM (anon Hub + resolve + fixture unpublished) | NÃO |
| E2 | Cron | SIM (5 jobs × anon/buyer/seller) | NÃO |
| E3 | Push | SIM | NÃO |
| E4 | Saco / bundle | SIM (desconto 90% recusado; self-accept recusado; **unlist no saco = P1**) | SIM (via E6) |
| E5 | Connect | SIM | NÃO |
| E6 | Mortos | SIM | **SIM P1** |
| E7 | URL regresso | SIM | NÃO (localhost = P3) |
| E8 | Grafo | SIM | NÃO |
| E9 | Email / invite | SIM | NÃO |
| E10 | Órbita→caixa | SIM (pagar TEST) | **SIM** (mesmo P1) |

Último ciclo após a captura: misto saco (mesma classe), vacation P3, redirects. **Sem P0 novo.**

ANTI-OBJETIVO: não se redescobriu dual Session, `product_offers.amount`, buyer `pago`→`concluido`, disputa seller PATCH, INSERT `stripe_checkout_events`, storage 1442, OCR kick, tip/rifa sem permissão.

---

## Contabilidade fechada (fluxo P1)

```
qty produto     2 → 1
listed          true → false (antes da Session)
is_sold         false → false
order.status    reserva_pendente → pago
amount_paid     null → 1220 cêntimos
PI              pi_3UADDlH7FWYUN3jh1xAUihvR
refund          null
Δwallet seller  0,00 €
Stripe TEST     captura 12,20 € (não mint interno)
```

---

P0 encontrados: 0  
P1 encontrados: 1  
P3 encontrados: 2 (localhost allowlist; vacation Session)

Existe criação líquida de dinheiro: **NÃO** (Stripe TEST cobrou o comprador; wallet vendedor inalterada)  
Existe oversell válido: **NÃO** (1 consumo em qty 2; não 2 holds permanentes no mesmo SKU=1)  
Existe leak Hub/anon: **NÃO**  
Existe cron explorável: **NÃO**  
Existe cross-user: **NÃO**  
Existe cadeia órbita→caixa P0/P1: **SIM**

Anon Hub exercitado: **SIM**  
Cron/job exercitado: **SIM**  
Último ciclo nova classe P0/P1: **NÃO** (ciclo pós-captura = mesma classe + P3)  
ATROFIA (só redescobriu classes fechadas): **NÃO**  
SATURAÇÃO: **NÃO**  
PRODUÇÃO TOCADA: **NÃO**  
FASE 4: **NÃO**

VEREDICTO: **FAIL_P1**
