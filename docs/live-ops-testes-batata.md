# Testes — Live ops (BATATA)

**Como usar:** marca **Estado** com ✅ OK · ❌ falhou · ⬜ por testar.  
**Regra:** quando um teste ficar ✅, apaga-o desta tabela e regista uma linha no **Histórico**.  
**Última actualização código:** 2026-06-03 (fix checkout settle + realtime vendedor + filtros cancelados + barra stock)

---

## 0. Antes de repetir os testes (obrigatório)

**Backlog automação (V0/V1/V2):** [live-ops-automacao-batata.md](./live-ops-automacao-batata.md)

Faz **nesta ordem** — sem isto, os testes 6 e 7 podem falhar outra vez com código antigo:

0. **V0 automático:** `flutter test` · configurar `tool/live_ops_staging.env` · `dart run tool/live_ops_staging_check.dart` — ver [live-ops-automacao-seed.md](./live-ops-automacao-seed.md).

1. **Supabase SQL Editor:** executar o ficheiro completo  
   `supabase/sql/live_ops_hotfix_batata.sql`  
   (idempotente; inclui `batata_update_live_item` com recompute, reconcile multi-reserva, etc.)

2. **Supabase:** redeploy da edge function  
   `create-payment-intent`  
   (metadata saco compacta: `bag_order_ids`, … — não `bag_orders_json` grande)

3. **App:** nova **build/instalação** (APK ou run release) — obrigatório após alterações em:
   - `lib/utils/live_in_stream_checkout.dart` (`afterStripeBrowserClosed`)
   - `lib/widgets/live_vendor_studio_panel.dart` (realtime `seller_id`, barra stock, filtros fila)
   - `supabase/functions/create-payment-intent/index.ts`

4. **Live nova** (recomendado) ou mesma live: anota o `live_id` para os logs.

---

## Testes em aberto (repetir agora)

| # | O quê validar | Estado | Passos | Critério de sucesso |
|---|----------------|--------|--------|---------------------|
| 3 | Stock em artigo **vendido** | ⬜ | 1) Vende 1 un. na live (ou marca vendido). 2) No painel vendedora, artigo activo → **Stock** ou editar qty (+5). 3) Barra do rodapé (Mostrar / vendido / …) deve estar **clicável**. | Badge deixa de ser só «Vendido» se há qty disponível; stock actualiza; barra responde. |
| 4 | Comprador **cancela** reserva | ⬜ | 1) Comprador reserva no saco. 2) Comprador cancela (remove do saco). 3) Painel vendedora → fila / Pagamentos. | **Sem** botões Aceitar/Recusar para essa linha; aparece em **Cancelados pelo comprador** (secção Pagamentos), não em Pendentes/No saco. |
| 6 | Saco **2+ referências** → Stripe | ⬜ | 1) Comprador: 2 refs diferentes no saco, aceites ou pendentes pagáveis. 2) Checkout saco → **Pagar**. | Abre browser **Stripe** (um único pagamento). Se falhar: SnackBar com erro (não ficar parado em silêncio). |
| 7 | **1 referência** paga → vendedora vê € | ⬜ | 1) 1 ref no saco → pagar no checkout live. 2) Concluir Stripe e **fechar** o browser (volta ao directo). 3) Vendedora: aba **Pagamentos** + carteira/resumo. 4) Opcional: SQL abaixo. | Comprador: artigo vendido. Vendedora: valor em €, linha em Pagamentos, reserva **não** fica Aceitar/Recusar. Logs: `paid_count` > 0 ou `legacy_orders_scanned` > 0. |

---

## Verificação rápida (SQL — opcional após teste 7)

Substitui `LIVE_ID` e corre no SQL Editor:

```sql
-- Encomendas recentes desta live / vendedor
select id, status, live_id, live_item_id, product_id, price_total, created_at
from orders
where live_id = 'LIVE_ID'
   or (seller_id = '69104e91-6a00-40d9-a7c9-b1571422ae43' and created_at > now() - interval '2 hours')
order by created_at desc
limit 15;

-- Reservas
select id, status, notes, live_item_id, updated_at
from live_reservation_requests
where live_id = 'LIVE_ID'
order by updated_at desc
limit 15;
```

Esperado após pagamento OK: `orders.status = pago`, `live_id` preenchido; reserva `converted` ou notes com `stripe_paid:`.

---

## Logs vendedora (`live_vendor_studio_logs`)

Após abrir o painel e após um pagamento, procura `payments.refresh`:

| Campo no `detail` | Significado |
|-------------------|-------------|
| `paid_count` / `paid_value_eur` | Carteira live (deve subir após #7) |
| `orders_with_live_id` | Encomendas com `live_id` nesta live |
| `catalog_product_ids` | Catálogo usado no fallback (deve ser ≥ 1) |
| `legacy_orders_scanned` | Encomendas `pago` por `product_id` sem `live_id` |
| `pago_with_live_id` | Quantas dessas têm status pago |

Em `reservation.load`: `stale_reconciled` > 0 pode aparecer se havia pagamento antigo por reconciliar.

---

## Histórico (já validado por ti — não repetir salvo regressão)

| Data | Teste | Resultado |
|------|--------|-----------|
| 2026-06-03 | **#1** Portes / total no checkout live | ✅ OK |
| 2026-06-03 | **#2** Chat vendedora com username | ✅ OK |
| 2026-06-03 | **#8** Abrir painel reconcilia sessão antiga | ✅ OK |
| 2026-06-03 | Deploy SQL + edge (uma vez) | ✅ SIM (repetir **build app** após último pull) |
| 2026-05-28 | A4 multi-Stripe UI checkout · B3 reservar vitrine | ✅ OK |
| 2026-06-03 | Regressão conhecida (antes do fix settle) | ❌ #6 Stripe saco · ❌ #7 € vendedora · ❌ #3 stock · ❌ #4 cancelados — **re-testar tabela acima** |

---

## O que mudou no código (para saberes o que estás a testar)

- Fechar browser Stripe → `afterStripeBrowserClosed` (settle edge + reconcile reservas).
- Painel vendedora: realtime encomendas por **`seller_id`** (não só `live_id`).
- Fila: cancelados (`bag_removed`) excluídos de Pendentes / No saco.
- Barra rodapé: acções **sempre** clicáveis em artigo vendido (stock).
- Edge saco: metadata Stripe compacta (limite 500 chars).
- Testes automáticos Dart: `test/live_reservation_queue_service_test.dart` (helpers reserva; **não** substitui estes testes manuais).
