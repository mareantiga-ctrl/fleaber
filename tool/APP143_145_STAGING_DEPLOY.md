# APP-143 · 144 · 145 — checklist staging (SQL + deploy)

**Data:** 2026-08-23  
**Projecto staging:** `fxdknzrqjenzqcvnwqqq` (SQL Editor ou CLI)  
**Estado QA:** **BLOQUEADO** até corrida E2E humana — isto só desbloqueia **infra**; não marca PASS sozinho.

---

## O que estes testes pedem (negócio)

| ID | O quê |
|----|--------|
| **APP-143** | V anula venda **Seguro Fleaber** (cartão) → refund Stripe automático; saldo/retido V **não** sobe |
| **APP-144** | V anula venda **MB WAY já paga** → **sem** Stripe; V/B combinam; carteira Fleaber inalterada |
| **APP-145** | Pós-cancel Seguro: V **sem** crédito «venda»; B vê mensagem de reembolso iniciado no chat |

**Código app já existe:** `lib/order_cancel_apply.dart` + `lib/utils/fleaber_stripe_refund.dart` + mensagem chat em `minhas_encomendas_widget.dart`. O bloqueio é **staging** (colunas/triggers/edge não garantidos + falta E2E).

---

## 1. SQL — correr por ordem no SQL Editor

Marca ☑️ à medida que corres. Ficheiros **idempotentes** (re-correr é seguro).

| # | Ficheiro | Para quê | ☑️ |
|---|----------|----------|----|
| A | `supabase/sql/orders_stripe_refund_batata.sql` | Colunas `stripe_*` + índices (refund Seguro) | ☐ |
| B | `supabase/sql/orders_rls_batata.sql` | V consegue `UPDATE status=cancelado` (RLS) | ☐ |
| C | `supabase/sql/order_cancel_stock_restore_batata.sql` | Trigger repõe stock ao cancelar pago/enviado | ☐ |
| D | `supabase/sql/sec_wallet_buyer_purchase_ledger_batata.sql` | Ledger «compra» no histórico B ao `pago` | ☐ |
| E | `supabase/sql/sec_wallet_buyer_refund_ledger_batata.sql` | Ledger «reembolso» espelho ao `cancelado` (sem mexer saldo Stripe) | ☐ |

**Já deves ter (SEC / wallet):** `sec_025_wallet_party_guard_batata.sql` + `#11b` — não repetir salvo dúvida.

**Verificação rápida pós-SQL:**

```sql
-- colunas Stripe
select column_name from information_schema.columns
where table_schema='public' and table_name='orders'
  and column_name like 'stripe_%';

-- trigger stock cancel
select tgname from pg_trigger t
join pg_class c on c.oid=t.tgrelid
where c.relname='orders' and tgname like '%cancel%';

-- trigger wallet ledger
select tgname from pg_trigger t
join pg_class c on c.oid=t.tgrelid
where c.relname='orders' and tgname like '%wallet%';
```

---

## 2. Edge function — deploy (SEC-011)

A função **`refund-order`** já está no repo: `supabase/functions/refund-order/index.ts`.

**Requisitos:**
- Só o **vendedor** da encomenda pode chamar (403 se buyer).
- Rate-limit 30/h por user.
- Só actua em `payment_method` Seguro Fleaber / Stripe (MB WAY → `skipped: true` — relevante para **APP-144**).

**Deploy staging** (PowerShell, na raiz do repo, com Supabase CLI autenticada):

```powershell
npx supabase functions deploy refund-order --project-ref fxdknzrqjenzqcvnwqqq
```

**Secrets obrigatórios** (Dashboard → Project Settings → Edge Functions → Secrets, ou CLI):

| Secret | Uso |
|--------|-----|
| `STRIPE_SECRET_KEY` | Refund Stripe (test key em staging) |
| `SUPABASE_URL` | Já costuma existir |
| `SUPABASE_SERVICE_ROLE_KEY` | Já costuma existir |

Sem `STRIPE_SECRET_KEY` a edge responde 500 — **APP-143** não passa.

**Smoke (opcional, service role ou JWT vendedor):**

```powershell
# POST .../functions/v1/refund-order  body: {"order_id":"<uuid>"}
# Esperado Seguro pago: ok + refund_id
# Esperado MB WAY: ok + skipped:true
# Esperado buyer JWT: 403 Sem permissão
```

---

## 3. O que **não** precisas de SQL extra

| ID | Nota |
|----|------|
| **APP-144** | Fluxo MB WAY **não** chama refund Stripe (`orderIsSeguroFleaberPayment` = false). Só validar cancel + carteira + chat. |
| **APP-145** | Mensagem B já no código quando refund OK; ledger B vem do trigger (passo E). Validar que **V** não ganha linha `venda` / saldo sobe. |

---

## 4. Depois de SQL + deploy — E2E (para PASS)

**Não marcar PASS** só por deploy. Sequência mínima:

### APP-143 (+ 145 no mesmo fio)

1. Compra **nova** Seguro Fleaber (sandbox) — artigo barato, ou reutilizar encomenda `pago` de teste **sem** refund prévio.
2. **V (TCL/Oppo):** Minhas encomendas → ⋮ **Anular venda** → confirmar.
3. **Esperado UI/BD:**
   - `orders.status = cancelado`
   - `stripe_refund_id` preenchido
   - Saldo V **inalterado** (sem crédito «venda»)
4. **B:** chat com «Reembolso Stripe iniciado…» (APP-145).
5. Prints + snapshot BD + (ideal) evento Stripe dashboard test.

### APP-144

1. Compra **MB WAY** já `pago` (fluxo APP-031/064).
2. V anula venda.
3. **Esperado:** cancelado; **sem** `stripe_refund_id`; refund-order skipped se chamado; carteira Fleaber B/V sem movimentos errados; chat sem texto Stripe.

---

## 5. Referências

- Lista mestre: APP-143–145 (BLOQUEADO)
- Segurança: `docs/SECURITY_SQL_APPLY_LIST.md` — linha SEC-011 (`refund-order`)
- Pack excluídos: `tool/reports/auditor_excluidos_2026-08-23/`

**Quando tiveres E2E:** responde no chat com prints + IDs encomenda; actualizamos master para PASS (143 primeiro, depois 145, depois 144 ou no mesmo arco se combinares).
