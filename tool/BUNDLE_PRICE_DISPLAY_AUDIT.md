# Auditoria preços — V vs B (estilo Vinted)

**Estado:** RETESTE FAIL — C1 ciclo 065–069.

| ID | Resultado reteste |
|----|-------------------|
| R1 | V PASS · B legado PASS COM AVISO · novas PASS (R3) |
| R2 | PASS |
| R3 | PASS |
| R4 | **FAIL** 065 stock |
| R5 | **FAIL** 067 cronologia |
| R6 | PASS COM AVISO 068 |
| 061 | **FAIL** |
| 062 | PASS |

**Origem QA:** BUG-QA-064 / APP-049 PASS COM AVISO (2026-07-06) — valores com taxas nuns sítios, sem taxas noutros; vendedor deve ver sobretudo **valor a receber**; comprador vê breakdown completo quando relevante.

**Helper central:** `lib/utils/bundle_price_display.dart` — `BundlePriceDisplay.forChatHeader`, `forOrdersListBundle`, `forProposalCard`.

---

## Princípio (referência Vinted)

| Papel | Valor principal | Subtítulo / secundário |
|-------|-----------------|------------------------|
| **Vendedor** | **A receber** (itens negociados, após desconto conjunto; sem protecção comprador) | Sem taxas comprador no header |
| **Comprador** | Total negociado **ou** total pago pós-checkout | Breakdown «com envio e protecção: Y» em pré-pagamento; sheet checkout completo |

**Regra:** o mesmo número não deve significar coisas diferentes no header vs card vs encomendas sem legenda.

---

## Superfícies mapeadas

| # | Superfície | Ficheiro(s) | V hoje (pós-C1) | B hoje (pós-C1) | Alvo |
|---|------------|-------------|-----------------|-----------------|------|
| 1 | Header chat conjunto | `chat_page_widget.dart`, `bundle_price_display.dart` | **A receber 28,80 €** (sem subtítulo taxas) | **Total negociado 28,80 €** + subtítulo «com envio e protecção: 34,57 €» | ✓ |
| 2 | Card proposta | `bundle_proposal_chat_card.dart` | Total negociado (sem taxas) | idem | ✓ negociado; histórico cancelado com copy própria |
| 3 | Sheet Concluir compra | `bundle_accepted_checkout_sheet.dart` | N/A | breakdown 32→−3,20→28,80→34,57 | ✓ (060) |
| 4 | Ver conjunto | `ver_conjunto_page_widget.dart` | N/A | 34,57 total comprador | ✓ |
| 5 | Minhas encomendas card | `minhas_encomendas_widget.dart` | **A receber** (soma linhas) | **Total pago** / **A transferir** MB WAY + subtítulo | ✓ |
| 6 | Sticky pagamento MB WAY | `chat_page_widget.dart` | confirmar $ (valor receber implícito) | Concluir / Ver dados / Confirmo | ✓ fluxo |
| 7 | Card dados MB WAY | `chat_page_widget.dart`, `batata_bundle_actions.dart` | N/A | valor + botão; **sem** MB WAY/IBAN inline (v2 payload) | ✓ 062 |
| 8 | Timeline pós-pago | `chat_page_widget.dart` `_mergeBundleTimelineCards` | cards compra+envio no **fundo** | confirmar receção no card envio | ✓ 063 |
| 9 | Perfil público / marketplace | preço lista artigo | preço unitário artigo | preço unitário artigo | N/A checkout |

---

## Bugs ligados (061–064)

| ID | Resumo | Fix |
|----|--------|-----|
| BUG-QA-061 | Nova proposta após cancelar reutilizava contexto antigo | `supersedeStaleOperationalBundlesForNewProposal` + mensagem sempre `insert` + `proposal_ts`; card histórico «Reserva cancelada» |
| BUG-QA-062 | MB WAY visível no card antes de tap | Card só valor + CTA; dados só no sheet (`buildBundleDirectPaymentDetails`) |
| BUG-QA-063 | Etiqueta / confirmar receção não no fundo | Âncoras temporais `_computeInsertIndexForTime` + `_bundlePurchaseAnchorTime` (mensagens `reservation_payment_submitted` / `reservation_seller_confirmed_receipt` antes de `order.createdAt`); envio após `reservation_order_shipped` ou comprovativo; avaliação segue a ordem nativa das mensagens quando existe `created_at`; **threads legadas** sem `created_at` suficiente em comprovativo / envio / receção / avaliação → fallback `messages.length` (não inventamos ordem) |
| BUG-QA-064 | Inconsistência taxas V/B | `BundlePriceDisplay` + superfícies 1, 2, 5 |

| 069 | Header B compras legadas (thread antiga) | subtítulo taxas só com bundle meta activo | sem meta → só «Total pago» | **WONTFIX** v1 — subtítulo só quando `_focusedBundleMeta` tem totais; compras antigas mostram valor pago sem breakdown (evita números inventados) |

| 070 | Header cai em 1 artigo após recusa; Nova oferta/Contrapropor usavam sheet artigo único | `fetchLatestBundleMetaForChat` + header com `cancelled`; `showBundleOfferAmountSheet`; `onUpdated` → `_loadBundleOrdersForChat` |
| 071 | Bloco filhos expandido sem destaque | Borda teal 1,2px (`FleaberColors.teal`) no container `#F4F7F8` em minhas encomendas |
| 066R | Contraproposta mantinha card antigo ativo até reabrir chat | `BundleProposalChatCard.onUpdated` assíncrono + refresh de thread/stream/cache; se API responder «já foi respondido», refrescar antes do aviso final |
| 066R-backend | V contrapropor falhava com RLS 42501 (insert bloqueado) e deixava bundle cancelado | Policy `product_bundles_insert_seller`; persist **antes** de cancelar proposta anterior; `chatIdOverride` na contraproposta; log RLS + snackbar humano |

--- (após APK 061–064)

**Compra Jarra/Vaso:** ciclo **fechado** (passos 4–7 PASS). **Não** repetir MB WAY só para 064.

## Arquitectura da bateria (2 fases)

| Fase | Testes | Pré-requisito | Artigos novos? |
|------|--------|---------------|----------------|
| **A** | R6 → R1 → R2 → R5 | APK nos 2 telemóveis | **Não** — compra Jarra fechada + compra antiga 26,06 € |
| **B** | R3 → 061 → R4 | Fase A concluída | **Sim** — 2 artigos novos (Jarra=0, Vaso=1 não chega para conjunto) |

### Ledger fase B (criar na PASSO 0′)

| Nome | Preço | Stock |
|------|-------|-------|
| **Caneca Retro X** | **12,00 €** | **2** |
| **Tigela Ceramica Y** | **8,00 €** | **2** |

Conjunto: **Caneca ×2** + **Tigela ×1** = **3 unidades** (mesma matemática Jarra/Vaso)

| Linha | Valor |
|-------|-------|
| Subtotal | **32,00 €** |
| Desconto 10 % | **−3,20 €** |
| Artigos | **28,80 €** |
| Protecção | **2,27 €** |
| Envio | **3,50 €** |
| **Total Seguro** | **34,57 €** |
| **MB WAY** | **32,30 €** |

**061** encaixa em B: proposta → V aceita → V cancela → **nova** proposta (msg nova; antiga «Reserva cancelada»).

**R4** continua em B: V aceita de novo → B sheet MB WAY → card só botão (parar antes de «Confirmo pagamento»).

### Bateria transversal R1–R6 (uma passagem V + B)

| # | Superfície | V esperado | B esperado |
|---|------------|------------|------------|
| R1 | Header chat (Jarra fechada + thread antiga) | **A receber** 28,80 € | negociado + subtítulo taxas coerente |
| R2 | Minhas encomendas | a receber | total pago |
| R3 | Ver conjunto / sheet (compra **nova**) | N/A | 32→−3,20→28,80→34,57 |
| R4 | Card MB WAY (compra nova, pré-pagamento) | N/A | só botão; dados após tap |
| R5 | Timeline pós-envio | etiqueta no **fundo** | confirmar receção no **fundo** |
| R6 | Compra antiga 26,06 € | card agregado | idem B |

**061:** teste isolado — cancelar reserva → nova proposta → msg **nova** no chat.

Marcar R1–R6 PASS/FAIL na lista mestre. Regra: `.cursor/rules/qa-price-display-uniformity.mdc`.

---

## Lembrete agendado

| ID | Quando | Acção |
|----|--------|-------|
| APP-095 / BUG-QA-095 | **2 h** e **24 h** após aceite reserva actual | Verificar lembretes chat (utilizador) |
