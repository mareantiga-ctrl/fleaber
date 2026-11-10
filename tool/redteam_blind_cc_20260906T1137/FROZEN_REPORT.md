# FROZEN_REPORT — RED TEAM CEGO CC

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
AUDITOR: REDTEAM_BLIND_CC_DISPUTA_POS_BRBW_v1
FROZEN_AT: 2026-09-06T11:48:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CC1, CC2, CC3, CC4, CC5, CC6, CC7, CC8]
VEREDICTO: FAIL_P2
```

Prefixo: `RTCC-20260906T1137`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2/S2 / anon. `service_role` só fixture (`setup_paid_order`) e observação.

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `102b5540-7f30-4f7e-89ed-37bb2288b526` · S2 `3f15db96-1088-4ca5-916d-0d5571ea08e5`

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
20. Cross-user dados sensíveis — NÃO (list/GET prefixo B2 → `[]` / NoSuchKey; URL persistido → 400 InvalidRequest / FST_ERR_BAD_URL)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (release S2 = false)
25. RLS crítico quebrado — NÃO (B2 INSERT disputa 403)
26. Edge confia total do cliente — NÃO (`refund-order` ignora `amount` no body)
27. Regressão funcional (happy path partido) — NÃO (pago→enviado→concluido→disputa→pedido_devolucao→em_devolucao→devolucao_entregue→devolvida→refund)
28. Saturação atingida — SIM (vectores novos do prompt esgotados nesta superfície; último ciclo sem P0/P1)

--------------------------------------------------
MISSÃO
--------------------------------------------------

Ainda desvio devolução / prova alheia depois do path canónico BRBW?

**Resposta:** o FSM pós-pago e o refund Stripe **agem**. Seller não marca `pedido_devolucao`. 2.ª disputa 409. B2 não insere disputa alheia. `devolvida` **não** relista stock com PI vivo; o restore acontece **uma vez** no `refund-order`. `amount` no body da Edge é ignorado. Release com disputa aberta = false.

Fica **P2** porque `batata_storage_url_path_canonical` só reescreve `／` `．` `%c0%ae` `%c0%af` `%2e` **e o guarda continua a aceitar** qualquer string que, depois dessa reescrita, ainda contenha o prefixo `order_disputes/{buyer}/{order}/` e não tenha `..` ASCII. Bidi (U+202E/202D/2067/200E), overlong `%c1%9c` / `%e0%80%af`, slashes unicode (U+2215/2044/29F8/FF3C), `%5c`, `%252e%252e%252f` e U+2024 **persistem** em `proof_photos` (replies + INSERT) e, no label, RLO + `%c1%9c` no path de storage. **Loot: não** (storage 400 / NoSuchKey). Não é o exacto BW (`／`) nem o exacto BQ (`?`/`#`).

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos BW/BQ **observados, não contados**:
- seller `pago`→`pedido_devolucao` → 403 `order_seller_cannot_mark_pedido_devolucao`
- reply signed URL + needle **depois de `?` / `#`** → 201 (classe BQ path-only)
- `／` (U+FF0F) no path → **ainda 201**, persistido (BRBW converte para `/` no *check* mas o needle continua a bater; o valor guardado não é reescrito)
- `%c0%af` overlong `/` → **ainda 201**, persistido (mesma razão)
- `return_label_url` host `evil.example` + needle → 403 `order_dispute_label_url_denied`
- `fleaber.app/https://evil` + needle → 403

Pass 1 = catálogo FSM. Não se usou como vitória: dual Session, bag unlist, seller PATCH `resolvida` clássico, `pago`→`concluido` sem enviado.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| CC1 | `pedido_devolucao` só buyer a partir de `concluido`+disputa. Sem disputa / a partir de `pago` = 403. 2.ª INSERT + race = 409 `dispute_already_exists_for_order`. Reopen após `PATCH resolvida` (0 rows, status ficou `aberta`) = 409. |
| CC2 | Saltos `entregue`/`concluido`/`devolvida`/`pago` mid-return bloqueados. Buyer `concluido` durante return = `order_concluido_denied_during_return`. Seller `enviado` mid-return = `order_shipped_at_immutable`. `devolvida` cedo (pedido/em_devolucao) = `order_devolvida_denied`. |
| CC3 | **P2** canonicalizer incompleto: bidi / `%c1%9c` / `%e0%80%af` / U+2215 / U+2044 / U+29F8 / U+FF3C / `%5c` / `%252e%252e%252f` / U+2024 persistem no path. Label wrap evil host = 403. Label RLO/`%c1%9c` no URL de storage = 201. |
| CC4 | Edge `amount:1` / `999999` / `"100"` + array → refund **590¢**. Buyer `refund-order` 403. Parcial wallet pós-envio = `dispute_partial_refund_requires_stripe`. Seller RPC parcial = `not_allowed`. Race 2× refund após `devolvida` = idempotente, status permanece `devolvida`. |
| CC5 | `devolvida` com PI vivo: qty 1→1 (sem restore). Após refund: qty 0→1 (uma unidade). Sem duplicado. |
| CC6 | Release concluido sem disputa = `true`, Δseller +5,00 €. Disputa **depois** do release = 403 RLS. Release **com** disputa aberta = `false`, Δseller 0. |
| CC7 | B2 INSERT (próprio id ou spoof B1) 403. S2 INSERT 403. anon 401. Storage list `order_disputes/B2/` como B1/S1 = `[]`. GET alheio = NoSuchKey. S2 release = false. |
| CC8 | Unshipped refund: Δwallet 0/0 (anulação Stripe, não mint). Caixa release vs disputa coerente. Sem PI hostage novo. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura: **5,90 €** (`amount_paid_cents=590`).
- Wallets (pass 3, após refunds unshipped): buyer **61,10 €** · seller **68,33 €** (Δ 0 nestes refunds).
- Release feliz (order `6ffb4d59-…`, sem disputa): Δ seller **+5,00 €** → seller **73,33 €**.
- Stock chain `ea79f9da-…`: qty 0 (vendido) → 0 em `devolvida` sem refund → **1** após `refund-order` (`stock_units_applied` null).

--------------------------------------------------
FINDINGS
--------------------------------------------------

### RTCC-CC3-canonical-path-incomplete · P2 · CC3

**Actor:** buyer JWT.

**Passos:**
1. Stripe TEST → `enviado` → `concluido`. Order `c45783a5-050b-4b3c-b9d5-24b381d52e0b`. Disputa `d602bb00-0875-481f-8fa5-6285f8cc26e2`.
2. `POST order_dispute_replies` com `proof_photos` = signed storage do prefixo B1/OID + **separador não coberto pelo canónico BRBW** + prefixo B2 `order_disputes/{B2}/0000…c2c2/rtcc-secret.png`.
3. Confirmação por `POST order_disputes` (INSERT, não só reply): RLO, `%c1%9c`, U+2215.
4. Label: `return_label_url` com RLO ou `%c1%9c` **depois** do path de storage (needle intacto) → 201. Host `evil.example`+needle → 403.
5. Oráculo loot: GET URL guardada, GET NFKC/stripped, GET object B2 com JWT B1/S1.

**Separadores que persistiram (201), todos a mesma classe:**

| Vector | Onde | Reply id / disputa |
|--------|------|--------------------|
| U+202E RLO | replies + INSERT `proof_photos` + INSERT label | `cc6d3ad4-…` / INSERT `6f1ee249-…` / label `71733498-…` |
| U+202D LRO | replies | `545b74f5-…` |
| U+2067 RLI | replies | `2a5bdcac-…` |
| U+200E LRM | replies | `bbc42849-…` |
| `%c1%9c` overlong `\` | replies + INSERT + label | `d5f3ad8a-…` / INSERT `6cb73188-…` / label `50950ac7-…` |
| `%e0%80%af` overlong 3-byte `/` | replies | `73270424-…` |
| U+2215 ∕ | replies + INSERT | `28f5e18d-…` / INSERT `d886ff3d-…` |
| U+2044 ⁄ | replies | `8268e358-…` |
| U+29F8 ⧸ | replies | `858f5655-…` |
| U+FF3C ＼ | replies | `1cab2d4f-…` |
| `%5c` | replies | `f1f00605-…` |
| `%252e%252e%252f` | replies | (double-encode `../`) |
| U+2024×2 ․․ | replies | `9e40dc8d-…` |

**Esperado:** `dispute_proof_url_denied` / `order_dispute_label_url_denied` (path canónico ASCII, um prefixo, sem controlos bidi, sem overlong fora da lista BRBW).

**Obtido:** INSERT/reply **201**, array persistido com o separador + prefixo B2 no mesmo string.  
Loot: **não**. GET signed sem `token` → 400 `InvalidRequest`; `%c1%9c` / `%e0%80%af` → 400 `FST_ERR_BAD_URL`; GET B2 `NoSuchKey`. O URL não é um objecto válido.

**Não é exacto BW/BQ:** o exacto é `／` no path, needle em `?`/`#`, ou seller `pedido_devolucao`. Aqui os separadores são **bidi / `%c1%9c` / slashes unicode ≠ FF0F / overlong 3-byte / double-encode**. (O `／` e o `%c0%af` **ainda** persistem — observados, **não contados**.)

**Severidade P2:** o guarda BRBW não trata estes separadores; grava um URL morto que *parece* apontar a provas alheias. Sem leitura cross-user, sem Δwallet. Uma classe, vários oráculos — **não** inflacionar P2 por variante.

**Prova:** `pass2.json` findings `CC3.bidi_rlo_path`, `CC3.c1_9c_backslash`, `CC3.insert_c1_9c`, `CC3.insert_label_bidi`, `CC3.insert_label_c19c` + notas `*.loot`.

--------------------------------------------------
NÃO-FINDINGS RELEVANTES (vectores do prompt)
--------------------------------------------------

- 2.ª disputa / race → 409 `dispute_already_exists_for_order`
- B2 INSERT disputa → 403 RLS
- `devolvida` cedo → 403 `order_devolvida_denied`
- buyer `concluido` mid-return → 403 `order_concluido_denied_during_return`
- stock restore dup → +1 unidade no refund, não 2
- Edge `amount` no body → ignorado (590¢)
- `return_label_url` wrap evil host / `fleaber.app/https` → 403 `order_dispute_label_url_denied`
- storage list prefixo alheio → `[]` / NoSuchKey
- refund parcial wallet com PI vivo pós-envio → `dispute_partial_refund_requires_stripe`

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_cc_20260906T1137/` — `_rtcc.dart`, `pass1.dart`, `pass2.dart`, `pass3.dart`, `pass1.json`, `pass2.json`, `pass3.json`, `pass1_ids.json`, este relatório.
