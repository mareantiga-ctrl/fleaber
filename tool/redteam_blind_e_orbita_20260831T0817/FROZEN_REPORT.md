# RED TEAM CEGO E — ÓRBITA
AUDITOR: REDTEAM_BLIND_E_ORBITA_v1  
FROZEN_AT: 2026-08-31T08:40:00+01:00  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · service_role só setup/observação/cleanup.  
production_touched: false  
fase4: false  
corrections_applied: false  

Prefixo fixtures: `RTE-20260831T0817-`  
Provas: `tool/redteam_blind_e_orbita_20260831T0817/out/pass1.json` … `pass5.json`

--------------------------------------------------
MAPA DE ATAQUE (órbita)
--------------------------------------------------

| Zona | Superfície live | Actor | Resultado desta ronda |
|------|-----------------|-------|------------------------|
| Hub views / handle | `hub_*` + `hub_*_discovery_public` + `batata_resolve_handle` | anon, 2 buyers | Anon lê vitrine. **P2:** `is_live=true` mete unpublished na discovery. **P2:** lives `ended` de seller unpublished na discovery. Sem colunas phone/iban/email nas views. |
| Crons / jobs | `batata_generate_auto_feedback`, `batata_expire_product_offers`, `batata_release_seller_wallet_for_order`, `livekit-egress-cleanup` | anon, buyer JWT | EXECUTE negado nos jobs de cron. Release alien → `false`. Egress sem secret → 401. **Não explorável.** Inventário SQL: pg_cron auto-feedback 1/min, expire offers */15. REST não lista `cron.job`. |
| Notificações | `user_notifications`, `notifications_view`, `seller_device_tokens` | buyer2, anon | SELECT/INSERT alheio bloqueado. View vazia para não-seller. Tokens anon → `[]`. |
| Bundle / saco | `product_bundles`, `batata_product_bundles_catalog_subtotal` | buyer | Totais hostis **recomputados** (25€, discount 0). **P2:** saco aceita unlisted+sold no `product_ids` / subtotal. Hold/checkout dessas linhas **bloqueado**. |
| Connect / banco | `create-connect-account`, `wallets`, `batata_seller_direct_payment_details` | buyer, buyer2, GET origens | `user_id` spoof 400. IBAN sem encomenda vazio. Wallet alheia vazia. `attacker.fleaber.pt` **não** 303. `https://fleaber.pt` → `/wallet`. |
| Soft states | `list_on_marketplace`, `is_sold` + `create-payment-intent` | buyer + seller | Hold novo em unlist/sold → `order_hold_product_*`. Checkout novo após unlist → `product is not listed`. Após sold → `product is marked sold`. Hub products não mostra sold. |
| Return / deep link | `web_return_origin`, `checkout_return` | GET/POST | Origens hostis não redireccionam. GET settle Session unpaid → 402, **não** liquida. Browser Stripe «link incomplete» (captura da Session pré-unlist **NÃO COMPROVADA**). |
| Social | `follows`, `favorites` | buyer2, anon | Anon follow 401. Follow-as-other bloqueado. Favorites unique ~1. Burst follows 0 extra. Sem tabela `blocks`. |
| Invite / email | `batata_staff_invite_helper_by_email`, `batata_find_user_id_by_email` | seller, buyer | JWT email→UUID = `null`. **P3:** invite `invite_unavailable` vs 200+UUID se o email existe (≤10/h). |

--------------------------------------------------
LENTES E — o que foi corrido
--------------------------------------------------
E1 vitrine · E2 cron · E3 push · E4 saco · E5 Connect · E6 mortos · E7 URL · E8 grafo · E9 invite · E10 cadeia.  
Último ciclo (pass5): settle GET + estado final Session stale — **sem classe nova P0/P1**.

Tácticas: anon Hub 1× · cron disparo hostil 1× · Stripe TEST Session emitida (captura browser falhou) · conta fechada nos fluxos · race unlist∥hold · 2 buyers + anon na mesma view · unlist/sold checkout · burst follows/favorites.

--------------------------------------------------
FINDINGS PROVADOS
--------------------------------------------------

### P2 · E1-ISLIVE-DISCOVERY
**Classe:** vitrine pública / publish bypass.  
**O quê:** JWT autentica, `PATCH profiles.is_live=true` **sem** `hub_published` e **sem** directo real → a linha aparece em `hub_profiles_discovery_public` para **anon** (`full_name`, `location`, `handle`, `id`). Reproduzido no seller2 unpublished e no buyer2 (`RTE-20260831T0817-buyer2-pii`, location `Portugal`).  
**Não é:** PATCH cruzado (`buyer2` → perfil seller = `[]`).  
**Porquê P2:** qualquer conta injecta-se no directório Hub público (spam + PII de quem não publicou vitrine). `is_live` não está selado ao estado real do directo.  
**Repro:** `PATCH profiles {is_live:true}` com JWT próprio; `GET hub_profiles_discovery_public?id=eq.<uid>` como anon.  
**Prova:** `out/pass1.json` E1-ISLIVE-DISCOVERY; `out/pass2.json` E1-BUYER-ISLIVE-DISCOVERY.

### P2 · E1-DISCOVERY-ENDED-UNPUB
**Classe:** leak Hub/anon (lives discovery ≠ profiles discovery).  
**O quê:** `hub_lives_discovery_public` **não** exige `hub_published`. Live `ended` criada no seller2 unpublished (`mux_playback_id=rte0817fakeplay`, `seller_name`) é legível por anon por `id` e por `seller_id`. Recheck pass3.  
**Porquê P2:** quem faz um directo in-app sem publicar FleaHub fica na landing de descoberta (nome + playback) depois de `ended`. A vitrine de perfis já filtra unpublished excepto `is_live`; a de lives não.  
**Repro:** live `status=ended` em perfil `hub_published=false`; `GET hub_lives_discovery_public?id=eq.<live>`.  
**Prova:** pass1 E1-DISCOVERY-ENDED-UNPUB; pass3 E1-DISCOVERY-ENDED-UNPUB-RECHECK. Live `53d40ca4-8bb5-40b6-8fea-9355bb848aba`.

### P2 · E4-BUNDLE-DEAD-SKU
**Classe:** saco / integridade de quote (não captura).  
**O quê:** buyer INSERT `product_bundles` com `product_ids=[listed, unlisted]` → 201, `subtotal_eur=33` (11+22). Com sold → `subtotal_eur=44`. Seller pode `accepted`.  
**Estado final económico:** `POST orders` da linha unlist → `order_hold_product_not_listed` (400). Checkout das linhas mortas não arranca.  
**Porquê P2:** o saco **mente** (SKU morto no conjunto + total). Não há Δwallet nem Session nessa linha.  
**Prova:** pass1 E4-BUNDLE-UNLISTED / E4-BUNDLE-SOLD; E10-BUNDLE-UNLIST-HOLD hold_http 400.

### P3 · E4-CATALOG-ORACLE
RPC `batata_product_bundles_catalog_subtotal([unlisted,sold])` como buyer → `55.00` (22+33). Oráculo de preço de SKUs não listados se o UUID for conhecido.  
**Prova:** pass2 E4-CATALOG-ORACLE.

### P3 · E9-INVITE-EMAIL-ORACLE
`batata_staff_invite_helper_by_email`: email inexistente → 400 `invite_unavailable`; email do buyer registado → **200 UUID** do convite. Enumeração de contas (rate 10/h, não o 2/h de magic).  
**Prova:** pass1 E9-INVITE-EMAIL-ORACLE. Efeito colateral: convite helper pending no buyer (fixture).

--------------------------------------------------
NÃO COMPROVADO / FECHADO NESTA RONDA
--------------------------------------------------
- **E6 mortos que vendem (P1):** unlist-then-hold 400; checkout após unlist 400 `product is not listed`; após sold 400 `product is marked sold`. Race unlist∥hold criou order `pendente` (hold ganhou enquanto ainda listed) — **não** é morto-que-vende; replay checkout bloqueado.
- **Session Stripe pré-unlist:** emitida `cs_test_a1Vr38ME…` com produto ainda listed; depois unlist, `create-payment-intent` 400; GET `checkout_return=success` → **402**, order `reserva_pendente`, `amount_paid_cents=null`. Browser Checkout: «This link is incomplete». **Captura líquida NÃO COMPROVADA** (sem `STRIPE_SECRET_KEY` local / URL hosted incompleta).
- **E2 cron:** JWT/anon sem EXECUTE em auto-feedback / expire-offers. `p_now=2099` 403. Release alien `false`. Egress 401.
- **E3 push alheio:** INSERT/SELECT cruzado falhou.
- **E5 Connect/IBAN cruzado:** falhou.
- **E7 open redirect:** `attacker.fleaber.pt` não 303; `fleaber.pt` → `https://fleaber.pt/wallet`.
- **E8 follow-as-other / fav-as-other / burst DoS:** não.
- Dual Session / offer amount / disputa seller PATCH / pairing OCR: **não atacados** (ANTI-OBJETIVO).

--------------------------------------------------
CONTA (fluxos que tocaram dinheiro)
--------------------------------------------------
- Session TEST criada (order `0da5b981-…`, product `fd9dd752-…` já unlistado): **não paga**.  
- Δwallet: não medido em captura (não houve PI succeeded).  
- Oversell permanente: não.

--------------------------------------------------
```
AUDITOR: REDTEAM_BLIND_E_ORBITA_v1
FROZEN_AT: 2026-08-31T08:40:00+01:00
production_touched: false
fase4: false
corrections_applied: false
```

P0 encontrados: 0
P1 encontrados: 0
P2 encontrados: 3
P3 encontrados: 2

Existe criação líquida de dinheiro: NÃO
Existe oversell válido: NÃO
Existe leak Hub/anon: SIM
Existe cron explorável: NÃO
Existe cross-user: NÃO
Existe cadeia órbita→caixa P0/P1: NÃO

Anon Hub exercitado: SIM
Cron/job exercitado: SIM
Último ciclo nova classe P0/P1: NÃO
ATROFIA (só redescobriu classes fechadas): NÃO
SATURAÇÃO: SIM
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: PASS_CEGO_SATURADO
```

P2/P3 de órbita **novos** (discovery `is_live`, lives unpublished, saco SKU morto, oráculos) — não são as classes do ANTI-OBJETIVO. Sem P0/P1 após ≥4 lentes + anon Hub + cron tentado + último ciclo sem classe nova P0/P1.
