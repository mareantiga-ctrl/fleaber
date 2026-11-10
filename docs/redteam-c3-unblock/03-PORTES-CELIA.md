# B2 — Testes de portes vs regra Célia

## Regra comercial aprovada (código)

`kFleaberDpdShippingRatesLive = true` em `lib/utils/dpd_shipping_rates.dart`.

| Modalidade | ≤3 kg | 3–6 kg | 6–10 kg |
|------------|-------|--------|---------|
| Shop2Shop (Pickup) | **2,99 €** | 3,49 € | 4,99 € |
| Shop2Home | **4,49 €** | 5,99 € | 8,99 € |

- Checkout DPD **exige** peso ou escalão (fail-closed).
- **3,50 €** = legado (encomendas antigas / `kFleaberCarrierShippingEur`), **não** cotação live.

## Diagnóstico dos testes antigos

| Teste | Falha original | Causa |
|-------|----------------|-------|
| `fee_calculator_test` labels canónicos | `FormatException` carrier sem quote | Esperava 3,50; app Célia |
| `live_checkout_fees_test` transportadora 3,50 | `FormatException` peso | Esperava 3,50; app exige band/kg |

**Não é bug de app escondido por testes** — a app já aplica Célia; os testes estavam desactualizados.

## Correção

Actualizados em `test/fee_calculator_test.dart` e `test/live_checkout_fees_test.dart` para Célia + fail-closed.

Prova:

- `01-fee-tests-BEFORE.txt` — 4 falhas (legado 3,50)
- `02-fee-tests-AFTER.txt` — All tests passed
