# FROZEN_REPORT — RED TEAM CEGO BW

## CONTAGEM

```
P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

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
AUDITOR: REDTEAM_BLIND_BW_DISPUTA_POS_BLBQ_v1
FROZEN_AT: 2026-09-06T11:05:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BW1, BW2, BW3, BW4, BW5, BW6, BW7, BW8]
VEREDICTO: FAIL_P2
```

Prefixo: `RTBW-20260906T1050`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2/S2 / anon. `service_role` só fixture (`setup_paid_order`) e observação.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (release +5,00 € só em concluido sem disputa, JWT do comprador, caminho feliz)
13. Refund excede captura — NÃO (`amount`/`amount_cents` no body ignorados; Edge devolveu 590¢)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito; 2× refund-order idempotente)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (list/GET prefixo B2 → vazio / NoSuchKey; object key com ／ → InvalidKey)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`batata_admin_resolve_dispute` não re-provado nesta ronda; release S2 = false)
25. RLS crítico quebrado — NÃO (B2 INSERT disputa 403)
26. Edge confia total do cliente — NÃO (`refund-order` ignora `amount` no body)
27. Regressão funcional (happy path partido) — NÃO (pago→enviado→concluido→disputa→pedido_devolucao→em_devolucao→devolucao_entregue→devolvida→refund)
28. Saturação atingida — SIM (vectores novos do prompt esgotados nesta superfície; último ciclo sem P0/P1)

--------------------------------------------------
MISSÃO
--------------------------------------------------

Depois do FSM BLBQ, ainda há desvio em devolução / disputa / dinheiro?

**Resposta:** o FSM pós-pago e o refund Stripe **agem**. Seller não marca `pedido_devolucao`. 2.ª disputa 409. B2 não insere disputa alheia. `devolvida` **não** relista stock com PI vivo; o restore acontece **uma vez** no `refund-order`. `amount` no body da Edge é ignorado. Release com disputa aberta = false.

Fica **P2** porque o guarda BLBQ de `proof_photos` (e o das replies) **aceita slash unicode `／` (U+FF0F) no path**, persistindo um URL de storage que concatena o prefixo da encomenda com um path alheio. Não há leitura do ficheiro B2 (storage `InvalidKey` / 404). Não é o exacto BQ (`?`/`#` / `../` / `fleaber.pt`).

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos BQ/BK **observados, não contados**:
- seller `pago`→`pedido_devolucao` → 403 `order_seller_cannot_mark_pedido_devolucao`
- reply signed URL + `／` **depois de `?token=`** → aceite, mas é a classe «needle/lixo na query» do path-only BLBQ
- `../` em `proof_photos` → PATCH 200 [] / INSERT n/a no pass 2 (guarda `..` no INSERT unicode+`..` não foi necessário: `%..%` cobriria `／..／`)
- `https://fleaber.pt/…` em `return_label_url` INSERT → 201 (allowlist NOP `fleaber.app`/`fleaber.pt`) — exacto, não contar

Pass 1 = catálogo FSM. Não se usou como vitória: dual Session, bag unlist, seller PATCH `resolvida` clássico, `pago`→`concluido` sem enviado.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| BW1 | `pedido_devolucao` só buyer a partir de `concluido`+disputa. Sem disputa / a partir de `pago` = 403. 2.ª INSERT + race = 409 `dispute_already_exists_for_order`. Reopen após `PATCH resolvida` (0 rows, status ficou `aberta`) = 409. |
| BW2 | Saltos `entregue`/`concluido`/`devolvida`/`pago` mid-return bloqueados. Buyer `concluido` durante return = `order_concluido_denied_during_return`. Seller `enviado` mid-return = `order_shipped_at_immutable`. `devolvida` cedo (pedido/em_devolucao) = `order_devolvida_denied`. |
| BW3 | **P2** `／` no path INSERT `proof_photos` + replies. Host evil ／ = 400. `return_label_url` wrap evil / `fleaber.app/https://` / ／ = 403 `order_dispute_label_url_denied`. |
| BW4 | Edge `amount:1` / `999999` / `"100"` + array → refund **590¢**. Buyer `refund-order` 403. Parcial wallet pós-envio = `dispute_partial_refund_requires_stripe`. Seller RPC parcial = `not_allowed`. Race 2× refund após `devolvida` = idempotente, status permanece `devolvida`. Refund em `concluido`+disputa = `order_refund_blocked_shipped`. |
| BW5 | `devolvida` com PI vivo: qty 1→1 (sem restore). Após refund: qty 0→1 (uma unidade). Sem duplicado. |
| BW6 | Release concluido sem disputa = `true`, Δseller +5,00 €. Disputa **depois** do release = 403 RLS. Release **com** disputa aberta = `false`, Δseller 0. |
| BW7 | B2 INSERT (próprio id ou spoof B1) 403. S2 INSERT 403. anon 401. Storage list `order_disputes/B2/` como B1/S1 = `[]`. GET alheio = NoSuchKey. |
| BW8 | Unshipped refund: Δwallet 0/0 (anulação Stripe, não mint). Caixa release vs disputa coerente. Sem PI hostage novo. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura: **5,90 €** (`amount_paid_cents=590`).
- Wallets (pass 3, após refunds unshipped): buyer **61,10 €** · seller **85,33 €** (Δ 0 nestes refunds).
- Release feliz (order `31e7c4a4-…`, sem disputa): Δ seller **+5,00 €**.
- Stock chain `9ed78f68-…`: qty 0 (vendido) → 0 em `devolvida` sem refund → **1** após `refund-order` (`stock_units_applied` null).

--------------------------------------------------
FINDINGS
--------------------------------------------------

### RTBW-BW3-unicode-slash-proof-path · P2 · BW3

**Actor:** buyer JWT.

**Passos:**
1. Stripe TEST → `enviado` → `concluido`. Order `22a11820-28a2-4fc6-9730-a4f621b375a2`.
2. `POST order_disputes` com  
   `proof_photos=[https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_disputes/{B1}/{oid}/ok.png／order_disputes/{B2}/0000…b2b2/rtbw-secret.png]`  
   (`／` = U+FF0F, **no path, sem `?`/`#`**).
3. Mesma forma em `POST order_dispute_replies` (disputa `2f6bc541-…`).
4. Oráculo loot: GET URL guardada, GET object key com `／`, GET path NFKC (`／`→`/`), GET do ficheiro B2 com JWT B1/S1.

**Esperado:** `dispute_proof_url_denied` (path canónico ASCII, um prefixo `order_disputes/{buyer}/{order}/`).

**Obtido:** INSERT **201**, array persistido com `／` + prefixo B2 no mesmo string.  
Loot: **não**. Storage `InvalidKey` na key com `／`; path NFKC 404; GET B2 `NoSuchKey`. O URL não é um objecto válido.

**Não é exacto BQ:** o exacto é needle em `?`/`#` ou `../` ASCII. Aqui o `／` está no path. (O reply do pass 2 com `／` **depois de `?token=`** foi observado e **não contado**.)

**Severidade P2:** o guarda BLBQ (host storage + needle ASCII + sem `..`) não trata separador unicode; grava um URL morto que *parece* apontar a provas alheias. Sem leitura cross-user, sem Δwallet.

**Prova:** `pass2b.json` findings `BW3.insert_unicode_slash_in_path` (duplicado `insert_unicode_on_path_then_alien` = mesmo payload) + `BW3.reply_unicode_in_path`; `pass2c_loot.json`.

--------------------------------------------------
NÃO-FINDINGS RELEVANTES (vectores do prompt)
--------------------------------------------------

- 2.ª disputa / race → 409 `dispute_already_exists_for_order`
- B2 INSERT disputa → 403 RLS
- `devolvida` cedo → 403 `order_devolvida_denied`
- buyer `concluido` mid-return → 403 `order_concluido_denied_during_return`
- stock restore dup → +1 unidade no refund, não 2
- Edge `amount` no body → ignorado (590¢)
- `return_label_url` wrap evil / app/https / ／ → 403 `order_dispute_label_url_denied`
- storage list prefixo alheio → `[]` / NoSuchKey
- refund parcial wallet com PI vivo pós-envio → `dispute_partial_refund_requires_stripe`

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_bw_20260906T1050/` — `_rtbw.dart`, `pass1.dart`…`pass2c.dart`, `pass1.json`, `pass2.json`, `pass2b.json`, `pass2c_loot.json`, `pass3.json`, este relatório.
