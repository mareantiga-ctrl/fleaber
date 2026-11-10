# B4 / B5 — Contas e dados TEST

Scripts em `tool/c3_test_seed/` — **não executar em PROD**.

## Contas planeadas (só TEST)

| Alias | Papel | Email padrão |
|-------|-------|--------------|
| Buyer A | Comprador | `c3.buyer.a@fleaber.test` |
| Buyer B | Comprador | `c3.buyer.b@fleaber.test` |
| Seller A | Vendedor | `c3.seller.a@fleaber.test` |
| Seller B | Vendedor | `c3.seller.b@fleaber.test` |

Passwords: gerar no CredMan / ficheiro local do operador C3 — **nunca** no git/ZIP/chat permanente.

Admin/`service_role`: **não** entregar ao C3 se sessões normais chegarem.

## Dados fictícios (tag `C3_TEST`)

- Anúncios / produtos / stock
- Reservas normais + confiança
- Mensagens entre A↔B
- Compras simuladas (Stripe TEST)
- Encomendas em estados: pending / paid / shipped / delivered / cancelled / refund_sim
- Sem telefones reais; emails `*.fleaber.test`

## Limpeza

`tool/c3_test_seed/90_cleanup_c3_test.sql` — apaga **apenas** linhas com `metadata->>'c3_test'='1'` / emails `@fleaber.test`.

Não corre automaticamente.
