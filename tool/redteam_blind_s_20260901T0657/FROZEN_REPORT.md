# FROZEN_REPORT — REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1

```
AUDITOR: REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1
FROZEN_AT: 2026-09-01T06:14:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [S1, S2, S3, S4, S5, S6, S7, S8]
VEREDICTO: PASS_CEGO_SATURADO
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST só para ciclo review/multi-conta.  
Actors: anon · buyer JWT `bfcbeeee-…` (comprador) · seller JWT `980f4fa1-…` · buyer2 `28b2cffd-…` · seller2 `657afa6c-…` · signup `5bbe0ea5-…`.  
`service_role` só fixture / observação / rollback de convite e PII de teste. Prefixo `RTS-20260901T0657`.  
Provas: `pass1.json` … `pass4.json`. Repro: `dart run tool/redteam_blind_s_20260901T0657/pass1.dart` (+ pass2–4).

**Missão.** Consigo ler ou alterar dados de outro utilizador, passar-me por staff/admin, ou ligar duas contas para benefício financeiro?

**Resposta.** Não neste poço. Oito lentes até PII, admin RPC, storage path alheio, staff helper, reviews (tabela + view), pairing/OCR, encomendas/chat, wallet. O segundo elo recusa ou o trigger congela. Último ciclo sem classe nova P0/P1.

Não é ATROFIA_ABORT (não se parou em email→UUID / listagem `chat_media` / brute 6 dígitos / SELECT anónimo de profiles). Variantes: embed PostgREST, GraphQL, view `reviews_public_ratings`, convite staff anti-oracle, token OCR com `user_type=vendedor` sem loja, helper analytics vs encomendas, IDOR por UUID conhecido, path storage exacto, INSERT order/chat spoof.

--------------------------------------------------
## Findings P0/P1
--------------------------------------------------

Nenhum. Cadeias exercitadas abaixo (INFO / HOLD).

P2 documentado (não eleva o veredicto): signup / contas `user_type=vendedor` emitem `device_token` OCR **próprio**; ingest na live de outro seller → `not_allowed`. Comprador (`user_type=comprador`) → `not_seller`.

--------------------------------------------------
## Lentes (esperado vs obtido)
--------------------------------------------------

### S1 · Profiles PII

| Ataque | Obtido |
|--------|--------|
| Buyer GET `profiles?id=eq.seller` (phone/iban/legal) | **200 []** |
| GET `profiles?select=phone,iban` sem filtro | **1 linha** (próprio) |
| anon GET profiles | sem linhas (e 400 se pedir coluna `email` inexistente) |
| `profiles_directory_public` select * | whitelist (id, nome, handle, `user_type`, `phone_verified` bool) — **sem** phone/IBAN; unpublished buyer2 **ausente** |
| `batata_find_user_id_by_email` | **200 null** |
| `batata_seller_direct_payment_details` sem order | **200 []** |
| `batata_admin_list_profiles` | **400** `Acesso negado.` |
| embed `products.seller:profiles(phone,iban)` | **400** PGRST200 (sem FK) |
| GET `/auth/v1/admin/users` JWT | **403** `not_admin` |
| GraphQL `profilesCollection` | pg_graphql **não activo** |
| `hub_profiles_public` unpublished | **200 []** |
| `user_notifications` de outro | **0 linhas** |
| Convite staff ghost vs membro | ghost `ok:true`; re-convite membro **409** `already_member` (não enum global) |

### S2 · Admin / staff boundary

| Ataque | Obtido |
|--------|--------|
| `batata_is_admin` buyer/seller/anon/buyer2 | **false** |
| PATCH `user_type=admin` (buyer) | **200** representação; `user_type` permanece **comprador** |
| PATCH perfil de outro | **200 []** |
| INSERT profiles id alheio | **403** RLS |
| Signup `data.user_type=admin` | perfil **vendedor** (trigger), não admin |
| DELETE próprio perfil | **200 []** (0 linhas) — sem DELETE+INSERT admin |
| `batata_admin_resolve_dispute` | **400** só administradores |
| Kill switch / `live_director_*` | RPC/tabela **ausentes** no schema cache |
| INSERT `seller_helpers` na loja de outro | **403** RLS |
| Aceitar convite + alargar `permissions` | PATCH **200**; perms **congeladas** `can_view_analytics`; `can_manage_reservations` **false** |
| Helper muda `seller_id` para si | **200 []**; seller_id inalterado |
| `batata_staff_invite_helper_by_email` (não-vendedor) | **403** `not_allowed` |
| `batata_claim_handle` handle alheio | **400** `phone_not_verified` |

OpenAPI autenticado: RPCs admin visíveis na lista svc (188 funções); execução JWT recusada nas gated.

### S3 · Storage paths

Path real de outro user (seller JWT upload):  
`fleaber_private/chat_uploads/980f4fa1-…/RTS-20260901T0657-s3.jpg`

| Ataque | Obtido |
|--------|--------|
| List `product_photos/`, `chat_uploads/{seller}/`, `order_proofs/` (buyer2/anon) | **[]** |
| GET object path seller (buyer2 / anon / public URL) | **404** `NoSuchKey` (RLS esconde; owner **200**) |
| Signed URL buyer2 | sem token |
| Upload JPEG no prefixo `{seller}/` (private + catalog) | **403** RLS |
| Abrir chat com seller e voltar a GET o ficheiro | **404** (counterparty não abre o prefixo inteiro) |
| GET URL `proof_photos` de disputa alheia | **400** |

Táctica obrigatória (≥1 path de outro): **cumprida**. Leitura cruzada: **não**.

### S4 · Multi-conta

| Ataque | Obtido |
|--------|--------|
| Review 5★ a si (seller JWT, order alheia) | **403** `review_order_not_yours` |
| Dois UUIDs claim rifa | buyer1 `ok`; buyer2 `join_required` (não é o mesmo “eu” ligado) |
| Compra Stripe TEST buyer2→seller + review 5★ | **201** — duas contas distintas, compra real, **sem** detecção de ligação |
| Disputa dessa order concluída | **403** RLS |

Arquitectura: não há binding de contas (NIF/device). Não é furo RLS; não moveu caixa para o atacante sem compra paga.

### S5 · Reviews / reputação

| Ataque | Obtido |
|--------|--------|
| INSERT review `buyer_id` alheio | **403** `review_order_not_yours` |
| PATCH tabela `reviews` alheia | **200 []** |
| PATCH `reviews_public_ratings` (view `security_invoker=false`) | **200** representação; **stars/comment congelados** (trigger) — mutação real **não** |
| DELETE via view | **403** `review_delete_forbidden` |
| DELETE própria 1★ | **403** `review_delete_forbidden` (linha persiste) |
| Autor PATCH view 1★→5★ | representação continua **1★** |

`reviews_gerais` (security_invoker): buyer2 vê **a sua** review.

### S6 · Pairing / director / tokens

| Ataque | Obtido |
|--------|--------|
| Tokens no binário Flutter | só **anon key** staging; sem `service_role`; sem device_token hardcoded |
| GET `ps_pairing_sessions` | **0** |
| `batata_ps_create_pairing` helper analytics / live alheia | **not_allowed** / `live_not_found` |
| `batata_ps_claim_pairing` | **PGRST203** overload (duas assinaturas) — claim REST não escolhe função |
| Token OCR buyer2 na live do seller | **400** `not_allowed` |
| GET `seller_device_tokens` do seller | **0**; `select=*` vê **só o próprio** token |
| Conta nova / buyer2 (`user_type=vendedor`) mint token | **ok:true** (P2: token **próprio**; não cruza seller) |
| Buyer `comprador` mint token | **not_seller** |
| `live_director_sim_profiles` | tabela não exposta |

### S7 · Orders / chat cross-user

| Ataque | Obtido |
|--------|--------|
| GET orders de outro buyer / por UUID conhecido | **[]** |
| PATCH order alheia | **200 []** |
| GET chats / `chat_messages` thread alheia | **[]** (owner vê colunas `text`,`sender_id`,…) |
| PATCH `user_b` do chat | **200 []** |
| INSERT msg em chat alheio | **403** RLS |
| INSERT order `buyer_id` alheio | **403** `order_buyer_attribution_denied` |
| Wallet de outro | **[]** |
| Disputas (conta nova) | **0** |
| Helper analytics GET `orders?seller_id=` | só **as suas** (buyer_id=buyer2); 0 foreign |

### S8 · Identidade → autoridade → dinheiro

| Ataque | Obtido |
|--------|--------|
| `batata_credit_wallet_once` / debit JWT | **404** (GRANT/assinatura não exposta a authenticated) |
| `batata_refund_buyer_wallet_for_order` / `release` JWT alheio | **200 false** |
| Admin resolve → refund | bloqueado em S2 |
| OCR token → reserva na live de outro | bloqueado em S6 |

Δwallet desta ronda nos ataques: **0**. Stripe TEST só em ciclos e2e de review (compra legítima).

--------------------------------------------------
## HOLD / falsos positivos
--------------------------------------------------

- **RTS-S5-010 (pass2):** PATCH view **200** com `stars:5` — a review alvo **já era 5★** automática. Pass3 PATCH `stars=1` + comment HIJACK → BD continua 5★ / texto original.
- **RTS-S7-012 (pass2):** helper lia `n=1` order da loja — era **a própria** encomenda buyer2. Pass3 `foreign_n=0`.
- **RTS-S6-001 / S6-005:** mint OCR sem loja. Não cruza identidade; classificado **P2**, não P1.

--------------------------------------------------
## Resposta final
--------------------------------------------------

```
P0 encontrados: 0
P1 encontrados: 0
P2 encontrados: 1  (token OCR próprio se user_type=vendedor; ingest cruzado recusado)

Ler PII de outro: NÃO
Alterar perfil/review/order/chat de outro: NÃO (triggers / RLS)
Passar-me por admin: NÃO
Staff self-insert / alargar perms: NÃO
Ligar duas contas → caixa: NÃO (review 5★ exige compra paga Stripe TEST)
Path storage de outro legível: NÃO

Dois UUIDs reais: SIM
Storage path alheio exercitado: SIM
PATCH/INSERT user_id alheio: SIM (403 / [])
Flutter ≠ fronteira: SIM (REST/RPC/Edge/Storage)

ATROFIA: NÃO
SATURAÇÃO: SIM
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: PASS_CEGO_SATURADO
```

**PASS_CEGO_SATURADO:** 8 lentes, provas com dois UUIDs + path storage alheio + Stripe TEST no ciclo review, último ciclo (pass3–4) sem P0/P1 novo.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
