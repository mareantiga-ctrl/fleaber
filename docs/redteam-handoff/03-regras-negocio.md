# 03 — Regras de negócio e cálculos

Valores e fórmulas **canónicas no código**. O C3 deve verificar se o cliente consegue alterar totais sem o servidor rejeitar.

## 1. Protecção do comprador (Seguro Fleaber)

Ficheiro: `lib/utils/fee_calculator.dart`

- Taxa fixa: **0,65 €**
- Percentagem: **5%** sobre a base definida no calculator
- Aparece no breakdown do comprador; o vendedor vê sobretudo o valor a receber (sem taxa de protecção misturada como «Total» ambíguo — ver QA preços)

## 2. Portes / envio

| Método | Comportamento |
|--------|----------------|
| Entrega em mão | 0,00 € |
| DPD (carrier) legado | 3,50 € fixos em caminhos antigos |
| DPD tarifas «Célia» | Tabela `dpd_shipping_rates` + `lib/utils/dpd_shipping_rates.dart` por peso/escalão e modalidade Shop-to-Shop / Shop-to-Home |
| Pickup | Escolha ponto MyPudo (CP → localidade) |

Fail-closed: método desconhecido → erro (não inventar portes).

Subcontas DPD (código): Shop-to-Shop `03546101`, Shop-to-Home `03546102`.

## 3. Preços e descontos

- Preço anúncio em `products`
- Bundles / conjuntos: `product_bundles`, `seller_bundle_discounts`, UI `lib/pages/bundle/`
- Propostas / ofertas: `product_offers` + cards no chat
- **Regra de auditoria:** o Edge `create-payment-intent` deve recalcular / validar montantes; cliente não é fonte de verdade

## 4. Reservas e stock

- Reservas live: `live_reservation_requests` (+ fontes Fleaber / Facebook / helper)
- Stock atómico: hardening `sec_fase2_oversell_*` + RPCs
- Comentários PS Face: contrato «quero REF» / «cancela REF» (parser C2/PS — ver regras `ps-face-reserve-contract`)
- Race conditions e oversell = cenários prioritários C3

## 5. Pagamentos

| Modo | Uso |
|------|-----|
| Stripe TEST | Desenvolvimento / Red Team seguro |
| Stripe LIVE | Bloqueado por flags `OPS_STRIPE_LIVE_*` e `MONEY_GO` |
| MB WAY / métodos locais | Via PaymentIntent / fluxos existentes |
| Tips em directo | `create-live-tip-checkout` |

Hold de fundos / libertação: migrations `financial_protection_*`, colunas `orders.funds_hold_until`, etc.

## 6. Carteira do vendedor

Estados típicos: **Disponível / Pendente / Retido**  
Isolamento por `fleaber_user_id` ↔ conta Connect.  
Comprador **não** precisa de Connect para comprar.

## 7. Devoluções e reembolsos

- Edge `refund-order` (seller-only / regras documentadas no hardening)
- RPCs `batata_process_partial_refund_dispute`, `batata_refund_buyer_wallet_for_order`, …
- JWT **não** fabrica saldo; percentagens de disputa só com autoridade seller/admin conforme SQL 3C+
- Quarentena: scripts antigos que reabrem GRANT wallet — **não reaplicar**

## 8. Apresentação de preços (Vinted-like)

- **Vendedor:** valor principal ≈ a receber  
- **Comprador:** negociado + envio + protecção  
- Nunca o mesmo label «Total» com bases diferentes sem legenda

## 9. Onde validar no código

| Tema | Ficheiro |
|------|----------|
| Fees / protecção / portes | `lib/utils/fee_calculator.dart` |
| Tarifas DPD | `lib/utils/dpd_shipping_rates.dart` |
| Payment Intent | `supabase/functions/create-payment-intent/` |
| Refund | `supabase/functions/refund-order/` |
| Autoridade financeira | `docs/SCHEMA_SOURCE_OF_TRUTH.md` |
