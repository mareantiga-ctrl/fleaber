# Seed / env — automação live ops V0

## Ficheiros

| Ficheiro | Uso |
|----------|-----|
| `tool/live_ops_staging_env.example` | Modelo de variáveis |
| `tool/live_ops_staging.env` | **Local, não commitar** — copiar do example |
| `supabase/sql/live_ops_test_seed.sql` | Verificação pós-deploy SQL (não cria users) |

## Configurar `tool/live_ops_staging.env`

1. Copiar:
   ```bash
   copy tool\live_ops_staging_env.example tool\live_ops_staging.env
   ```
2. Preencher URL e chaves do projeto Supabase (Dashboard → Settings → API).
3. **Seller e buyer** devem existir em `auth.users` e `profiles`:
   - Usa contas de teste dedicadas, ou
   - Os teus UUIDs reais de staging (ex. vendedor `69104e91-…` se for o mesmo projeto).
4. Emails/passwords = credenciais Supabase Auth dessas contas.

## Ordem antes do script

1. `live_ops_hotfix_batata.sql` no SQL Editor  
2. Edge `create-payment-intent` redeploy  
3. `dart run tool/live_ops_staging_check.dart`

## O que o script faz

- Apaga lives antigas com título `LIVE_OPS_V0_TEST` do vendedor de teste.
- Cria dados temporários e corre:
  - **V0.3c** — `batata_live_bag_remove_request` (#4)
  - **V0.3a** — `batata_live_reconcile_stripe_order` (#7)
  - **V0.3d** — `batata_update_live_item` em item `sold` (#3)
  - **V0.3e** — POST edge saco 2 linhas (#6)

Não substitui pagamento Stripe real nem teste de APK.

## Unitários (sem Supabase)

```bash
flutter test test/fee_calculator_test.dart test/order_status_test.dart test/live_reservation_queue_service_test.dart test/live_checkout_fees_test.dart test/widget_test.dart
```

Ou tudo:

```bash
flutter test
```
