# FROZEN_REPORT — REDTEAM_BLIND_BQ_DISPUTA_POS_BFBK_v1

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 1
P2 aberto: SIM          → quantos: 2
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 3

AUDITOR: REDTEAM_BLIND_BQ_DISPUTA_POS_BFBK_v1
FROZEN_AT: 2026-09-02T18:22:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BQ1, BQ2, BQ3, BQ4, BQ5, BQ6, BQ7, BQ8]
VEREDICTO: FAIL_P1

Prefixo fixtures: `RTBQ-20260902T1905-`
Pasta: `tool/redteam_blind_bq_20260902T1905/`
Staging: `fxdknzrqjenzqcvnwqqq`
Stripe: TEST
Actors: anon · buyer JWT · seller JWT · buyer2 · seller2
service_role: só fixture / observação / cleanup

```
AUDITOR: REDTEAM_BLIND_BQ_DISPUTA_POS_BFBK_v1
production_touched: false · fase4: false · corrections_applied: false
```

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (fora de âmbito disputa)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (release mid-return `false`; Δwallet 0)
13. Refund excede captura — NÃO (`amount=1` / `999999` → 590¢ = captura)
14. Release+refund cria dinheiro líquido — NÃO (release mid-return false; refund concluido 403 shipped)
15. Payout duplica Transfer — NÃO (fora de âmbito)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (B/B2 refund-order 403; B2 disputa RLS; B2 reply RLS)
20. Cross-user dados sensíveis — SIM (BQ3-01: reply grava signed URL de B2 na disputa de B1; GET B1/anon/S1 200 binário)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (`order_seller_cannot_mark_pedido_devolucao`; seller `devolvida` cedo 403)
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`batata_finalize_stripe_order_refund` / gate 42501 JWT)
25. RLS crítico quebrado — NÃO (2.ª disputa 409; B2 INSERT/SELECT disputa `[]`/403)
26. Edge confia total do cliente — NÃO (`amount` no body ignorado; parcela 590¢)
27. Regressão funcional (happy path partido) — NÃO (enviado → concluido → disputa → `pedido_devolucao` 200)
28. Saturação atingida — SIM (8/8 lentes)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## VEREDICTO
--------------------------------------------------

**FAIL_P1.** Depois do fecho BFBK (seller sem `pedido_devolucao`; needle de prova **só no path** na tabela `order_disputes`), o bind **não foi aplicado às replies**. `batata_order_dispute_replies_guard_proof` ainda faz `position(needle in v_url)` no URL inteiro. B1 grava na própria disputa a signed URL da prova privada de B2, com o needle de B1 na query ou no fragmento `#`. GET com o token: **B1, S1 e anon** recebem o objecto (HTTP 200, corpo binário ~70 bytes = PNG). O vendedor de B1 **não** consegue o mesmo ficheiro via path autenticado (400).

Há dois P2 no mesmo poço de provas: (1) `proof_photos` na disputa aceita `../` e `%2e%2e` no path (needle próprio no prefixo; GET storage **não** resolve para o ficheiro de B2); (2) INSERT reply aceita `https://fleaber.pt/…` com needle (allowlist do insert-guard).

Exactos BK/AY **não contados** (fechados): seller `pago`→`pedido_devolucao` → `order_seller_cannot_mark_pedido_devolucao`; query-string wrap na tabela `order_disputes` → `dispute_proof_url_denied`. Fragmento `#` na **tabela** disputa também negado (path-only).

Anti-atrofia: 0 de 2 exactos redescobertos como finding. Classes novas = replies wrap + path não canonicalizado + host fleaber.pt. Não é `ATROFIA_ABORT`.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### BQ3-01 · P1 · BQ3 / BQ7 / BQ8 — replies: needle no URL inteiro (query + `#`) = prova alheia

**O que isto é:** o fecho BFBK amarra `proof_photos` / `return_label_url` da **disputa** ao path `order_disputes/{buyer}/{order}/` (strip `?` e `#`). As **respostas** (`order_dispute_replies`) ficaram com o guard antigo: o needle pode ir na query ou no fragmento, e o path real ser de outra encomenda / outro comprador. Com uma signed URL (token no `?`), quem abre a prova na disputa de B1 lê o ficheiro privado de B2.

**Actor:** buyer JWT (B1) · INSERT `order_dispute_replies` · GET storage `object/sign` (B1, S1, **anon**)

**Pré:** B2 tem disputa + PNG em `fleaber_private/order_disputes/{B2}/{oidB2}/p3-secret.png` e cria signed URL. B1 tem disputa própria em `concluido`.

**Repro**
1. B2: `POST /storage/v1/object/sign/fleaber_private/order_disputes/{B2}/{oidB2}/p3-secret.png`
2. B1: `POST order_dispute_replies` com `proof_photos=[signedB2 + "&x=" + needleB1]` **ou** `signedB2 + "#" + needleB1`
3. GET da signed URL sem JWT de B2

**Esperado:** `dispute_proof_url_denied` (needle só no path, como na disputa).

**Obtido**
- INSERT query wrap: `201` reply `3c61355c-108e-43e0-a2e4-473f1b3b1155` (disputa B1 `896b6bb5-…`, order `8ec9fc97-…`)
- INSERT fragment wrap: `201` reply `327d5539-bac1-4254-a865-bd8748dba197`
- INSERT authenticated wrap (path B2 + `#`/`?` needle B1), pass2: `201` replies `72b0f9d1-…` e `8077bb21-…`
- GET signed: B1 / anon / S1 → **200**, corpo `binary:70b` (PNG; `utf8.decode` falha — é binário, não JSON)
- GET autenticado do mesmo path B2 com JWT B1/S1 → **400** `Object not found` / RLS (pass2)

**Porquê P1 e não P0:** não há Δwallet nem refund extra. Há caminho REST para **anexar e servir** prova privada de outro tenant no fio de disputa de B1 (S1/staff vê; anon com o token também). Classe única (query e `#` = o mesmo `position(needle in v_url)`).

**Não é o exacto AY/BK** (query wrap na tabela `order_disputes` — 400 `dispute_proof_url_denied`).

---

### BQ3-02 · P2 · BQ3 — `proof_photos` da disputa aceita `../` e `%2e%2e` (sem loot)

**O que isto é:** o guard path-only exige o needle no path, mas **não canonicaliza** `.` / `..`. B1 grava um URL cujo prefixo é a própria pasta e depois sobe com `../` até à pasta de B2.

**Actor:** buyer JWT PATCH `order_disputes.proof_photos`

**Repro:** `PATCH proof_photos=[…/order_disputes/{B1}/{oidB1}/ok.png/../../../order_disputes/{B2}/{oidB2}/rtbq-secret.png]` e a variante `%2e%2e`.

**Esperado:** denied / path normalizado.

**Obtido:** `200` com o URL `../` gravado (disputa `296fcdd8-…`). GET storage do path literal e do path B2 com JWT B1/S1 → **400**, sem PNG. B2 GET do próprio ficheiro autenticado → 200.

**Porquê P2:** metadata hostil sem leitura do objecto alheio. Um cliente que normalize `../` no browser poderia tentar o path B2; o RLS autenticado recusa. Classe única (`../` ≡ `%2e%2e`).

---

### BQ3-03 · P2 · BQ3 — INSERT reply aceita `https://fleaber.pt/…` com needle

**O que isto é:** o insert-guard de replies permite hosts `fleaber.pt` / `fleaber.app` além do storage. Com o needle no path do site, a prova deixa de ser um objecto `fleaber_private`.

**Actor:** buyer JWT INSERT `order_dispute_replies`

**Repro:** `POST proof_photos=["https://fleaber.pt/order_disputes/{B1}/{oid}/ phishing.png"]`

**Obtido:** `201` reply `6b5325b2-fef1-4167-83f3-b2aa1861baf3`. `javascript:` no INSERT → 403 `dispute_proof_url_denied`. PATCH replies → `200 []` (sem policy UPDATE).

**Porquê P2:** phishing / prova fora do bucket; sem loot Stripe/stock.

--------------------------------------------------
## BLOQUEADOS (prova que BFBK / defesa segura)
--------------------------------------------------

| Lente | Prova | Resultado |
|-------|--------|-----------|
| BQ1 | Seller `pago`→`pedido_devolucao` (exacto BK, não contar) | 403 `order_seller_cannot_mark_pedido_devolucao` |
| BQ1 | Buyer `pedido_devolucao` desde `pago` (com/sem disputa) | 403 `order_pedido_devolucao_denied` |
| BQ1 | Buyer `pedido_devolucao` desde `concluido` + disputa | 200, status `pedido_devolucao` |
| BQ2 | Seller `devolvida` / `em_devolucao` desde `pago` | 403 `order_devolvida_denied` / `order_em_devolucao_requires_pedido` |
| BQ2 | Buyer `devolvida` | 403 `order_buyer_cannot_mark_devolvida` |
| BQ2 | Buyer `concluido` a meio de `pedido_devolucao` | 403 `order_concluido_denied_during_return` |
| BQ2 | Seller `devolvida` a saltar FSM; `enviado` durante return | 403 `order_devolvida_denied` / `order_shipped_at_immutable` |
| BQ3 | Query wrap na **tabela** disputa (exacto AY) | 400 `dispute_proof_url_denied` |
| BQ3 | Fragment `#` wrap na **tabela** disputa / label | 400 `dispute_proof_url_denied` / `order_dispute_label_url_denied` |
| BQ3 | INSERT reply `javascript:` + needle | 403 `dispute_proof_url_denied` |
| BQ3 | PATCH reply proof_photos | 200 `[]` (RLS, sem UPDATE) |
| BQ4 | `refund-order` `amount=1` / `999999` | ignora body; 590¢ = `amount_paid_cents` |
| BQ4 | Buyer / B2 / anon `refund-order` | 403 / 403 / 401 |
| BQ4 | JWT `batata_finalize_stripe_order_refund` / gate | 42501 |
| BQ4 | Refund em `concluido` + disputa aberta | 403 `order_refund_blocked_shipped` |
| BQ5 | Race 2× `refund-order` | Δqty = 1; 2.º `already_refunded` |
| BQ5 | `devolvida` com PI vivo, sem refund | qty intacta (0→0); refund depois Δ=+1, status permanece `devolvida` |
| BQ6 | Release durante `pedido_devolucao` | `200 false`; `wallet_release_processed_at` vazio; Δseller 0 |
| BQ6 | Release em `pago` | `200 false` |
| BQ7 | B2 INSERT disputa (spoof `buyer_id` ou próprio) | 403 RLS |
| BQ7 | 2.ª disputa / race em `concluido` | 409 `dispute_already_exists_for_order`; count=1 |
| BQ7 | B2 SELECT disputa B1 | 200 `[]` |
| BQ7 | B2 reply na disputa B1 | 403 RLS |
| BQ8 | Carteiras B1/S1/B2/S2 | 61.1 / 16.0 / 0 / 0 inalterados |

Disputa em `pago`: INSERT RLS exige `concluido`/`entregue` — não é finding (produto). O teste pass1 «refund com disputa aberta» em order ainda `pago` **não conta**: não havia disputa; o refund de `pago` sem envio é o caminho seller-legítimo (Edge `already_refunded` no 1.º call = persist do `stripe_refund_id` antes do finalize).

--------------------------------------------------
## LENTES
--------------------------------------------------

| # | Lente | Cobertura |
|---|--------|-----------|
| BQ1 | pedido_devolucao | SIM — seller exacto BK bloqueado; buyer só `concluido`/`entregue` + disputa |
| BQ2 | hops FSM | SIM — devolvida cedo, skip, mid-return `concluido`, enviado durante return |
| BQ3 | provas | SIM — `#`/query na tabela vs replies; `../`; signed URL; fleaber.pt; javascript |
| BQ4 | refund | SIM — amount hostil, actor cruzado, disputa+concluido, RPC JWT |
| BQ5 | stock | SIM — race 2× refund; devolvida sem refund; refund em devolvida Δ=1 |
| BQ6 | release | SIM — mid-return e pago; Δwallet 0 |
| BQ7 | 2.º actor | SIM — B2 disputa/reply/select/refund; 2.ª disputa; S2 |
| BQ8 | caixa | SIM — wallets antes/depois 0; Stripe refund 590¢ nas orders de prova |

--------------------------------------------------
## PROVAS
--------------------------------------------------

- `tool/redteam_blind_bq_20260902T1905/pass1.json`
- `tool/redteam_blind_bq_20260902T1905/pass2.json`
- `tool/redteam_blind_bq_20260902T1905/pass3.json`
- Probes: `pass1.dart` `pass2.dart` `pass3.dart` `_rtbq.dart`

Actors: B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `9689195d-b210-4f50-b7aa-4f1d24a617e5` · S2 `de13db92-4f7a-47b9-b6bb-24b80fd898a2`

Signed wrap (P1): order B2 `80777372-5606-4b42-a4dc-236edd0474c4` · object `…/p3-secret.png` · disputa B1 `896b6bb5-d4b6-450b-bbab-4563bb85728c` · replies `3c61355c-…` / `327d5539-…`

PI TEST (não produção): `pi_3UBIfZH7FWYUN3jh0vUM0TvH`, `pi_3UBIfdH7FWYUN3jh15bUjCDk`, e os `setup_paid_order` de pass1/pass2.

--------------------------------------------------
## LIMITAÇÕES
--------------------------------------------------

- Não se leram reports BK / BE / AY (cegueira do prompt). Código/SQL/Edge actual sim.
- GET signed devolveu corpo binário; o detector `contains('PNG')` no pass3 foi falso negativo — o tamanho `binary:70b` coincide com o PNG de 1×1 enviado.
- Token signed foi criado por B2 no laboratório (atacante precisa de uma signed URL vazada ou de conluio). O efeito novo é **plantar** essa URL no fio de B1, onde o bind da disputa já a recusaria.
- `crash_inject` de refund não foi o poço BQ (já saturado noutros auditores); amount do cliente é ignorado.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
