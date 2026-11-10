# Fleaber â€” Lista mestre QA manual (app completa)

**Fonte de verdade Ãºnica** para QA manual. O agente deriva passos narrativos daqui â€” **nÃ£o pergunta** Â«queres testar X?Â»; se estÃ¡ no cÃ³digo, estÃ¡ na lista.

**Ã‚mbito:** toda a app funcional + UX, **incluindo** `NAV-*` (back, tabs, deep links) â€” automatizar sempre que for possÃ­vel.

**Regras:** `.cursor/rules/qa-manual-battery-format.mdc` Â· **Cobertura %:** `tool/QA_COVERAGE_AUDIT.md`

**Dispositivos:** **V** TCL Â· **B** Redmi Â· **PC** Chrome

**Legenda estado:** `PASS` · `PASS ATÉ API` · `FAIL` · `PASS COM AVISO` · `PENDENTE` · `SKIP` · `WONTFIX` · `N/A` · `BLOQUEADO`

**PASS ATÉ API:** produto actual correcto; só falta validar quando a **API externa** respectiva for integrada. **Não** conta em PASS COM AVISO nem em PENDENTE/FAIL. Lista de regressão: `tool/PASS_ATE_API_REGRESSION.md`.

**Legenda ligaÃ§Ã£o:** `â†’ ARCO-XX` = passo faz parte do arco denso Â· `â†”` = verificaÃ§Ã£o cross-superfÃ­cie obrigatÃ³ria

---

## Resumo (actualizado 2026-08-23 — auditor SEC-025 + AVISO ronda 2)

Contagem **recalculada ID a ID** nesta lista (170 únicos; 0 duplicados).  
APP: **132 PASS** · **2 PASS ATÉ API** · **0 AVISO** · **0 FAIL** · 0 PEND · 2 WONTFIX · 2 N/A · 0 BLOQ (=138).  
NAV **8 PASS** (=8) · SEC **20 PASS** + **3 AVISO** (=23).

| Métrica | Valor |
|---------|-------|
| **APP-ids (sem SEC, sem NAV)** | **139** |
| **PASS** | **132** |
| **PASS ATÉ API** | **2** (055, 071) |
| **PASS COM AVISO** | **0** |
| **FAIL** | **0** |
| **PENDENTE** | **0** |
| **SKIP / WONTFIX** | **2** (030, 044) |
| **N/A (retirado)** | **2** (062, 084) |
| **BLOQUEADO** | **0** |
| **NAV-*** | **8** · **8 PASS** |
| **APP-SEC-*** | **23** · **20 PASS** · **3 PASS COM AVISO** · **0 PENDENTE** |
| **Total linhas lista** | **170** (= 139 + 8 + 23) |
| **Placar global** | **160 PASS · 2 PASS ATÉ API · 3 AVISO · 0 PEND · 0 FAIL · 0 BLOQ · 2 WONTFIX · 2 N/A** |

**C27 (2026-08-23) fechada — auditor independente 3/3 PASS:** APP-253 · APP-254 · APP-214.  
**Hub H (2026-08-23) fechada — auditor independente:** Z1 · R1 · D1 · A0 · A2a×2 · C1 · C1b · A2 · C2 → **PASS**; D2 SKIP. **APP-200** reteste pós-fix catálogo → **PASS**. Pack: `battery_hub_h_2026-08-23_auditor_final.zip`. Ver `tool/QA_SCENARIO_COVERAGE.md`.  
**FAILs placar:** nenhum aberto (APP-065 · APP-095 PASS Maestro+prints 2026-08-23).  
**C26 (auditoria independente):** APP-061 · APP-072 · APP-SEC-016 → **PASS**. UX título disputa escalada → **corrigido** («Disputa em análise»; regressão aberta/análise/fechada em `battery_c26_2026-08-22/UX072_TITLE_FIX.md`). Placar **recontado ID a ID** (não por soma/subtração do placar antigo).  
**C25 encerrada:** 058, 069, 070, 093, 073, 146, SEC-003, SEC-027 → **PASS**; 071 → **PASS ATÉ API**.
**AVISO ronda 2 (auditor 2026-08-23):** APP-043 · APP-083 → **PASS**; APP-055 → **PASS ATÉ API** (regressão carrier). Pack: `battery_aviso_2026-08-23/audit_aviso_ronda2_auditor_20260823.zip`.
**AVISO live (2026-08-23):** APP-218 · SEC-020 → **PASS** (Oppo+Redmi; live `3997db80` reactivada sem create Mux — quota 10/10; ended+force-stop). Pack: `battery_aviso_live_2026-08-23/`.  
**SEC-025 (2026-08-23):** auditor independente → **PASS** (UI Aceitar/Recusar + Aceitar → BD `concluido`/`resolvida`; SQL `#11b`). Pack: `battery_aviso_sec025_2026-08-23/audit_sec025_pass_20260823.zip`. **Nota UX:** vários cartões «Disputa fechada» na thread `7b913a51` = resíduo de seeds QA repetidos (várias disputas seed + aceites na mesma thread); **não** reprova SEC-025 — revalidar só se disputa **nova** num chat limpo duplicar cards.  
**AVISO restantes (3):** SEC-008 · SEC-013 · SEC-019 (PS/FB).  
**Plano execução:** `tool/reports/battery_ps_face_real_DESIGN.md` — **Facebook Live real** + PS Reader + Hub (vídeo pedido API Meta). Sem Lab.

**SessÃ£o 2026-08-16 (evidÃªncia):** Web local + Maestro TCL â€” ver `tool/reports/web_e2e_continue_2026-08-16/SESSION.md`.  
**NÃ£o inventar PASS** na fila `MANUAL_QA_PENDING` (124-V, 214bâ€“e, 143â€“145) sem reteste humano/device correcto.  
**APP-053-V:** PASS 2026-08-16 (operador â€” Joao84 vÃª venda Seguro ~36,88 â‚¬).

### Bugs UX â€” estado (nÃ£o confundir com PASS de ciclo antigo)

| ID | Resumo | Estado QA |
|----|--------|-----------|
| 042, 059, 060, 062, 064 | Ciclo conjunto / MB WAY | **PASS** (histÃ³rico) |
| **058** | Disputa sem texto / guard | **PASS** (C25) |
| **061** | Msg/card nova por proposta / reservado | **PASS** (C26 estado `reservado`) |
| **063/067** | Timeline ordem | histórico / ver notas |
| **065** | Stock cancel/supersede | **FAIL CRÃTICO** |
| **072** | Disputa vendedor / Nova oferta UI | **PASS** (C26) |
| **068** | Hierarquia card encomendas | ver notas |
| **095** | Lembretes 2h/24h | **PASS** | Maestro TCL+Redmi 2026-08-23 |

---

## Arcos densos (execuÃ§Ã£o â€” cada arco = mÃ¡ximo de IDs por mÃ­nimo de passos)

| Arco | Nome | IDs incluÃ­dos | Estado |
|------|------|---------------|--------|
| **ARCO-P1** | Marketplace P+Q fim-a-fim | APP-120, APP-020, APP-040â€“057, APP-080â€“086, APP-110â€“112, APP-400 | **PAUSA** |
| **ARCO-L1** | Live prep â†’ directo â†’ reserva | APP-200â€“218, APP-250â€“265, M01â€“M21 | PENDENTE |
| **ARCO-H1** | Hub seller + pÃºblico + â†” app | APP-300â€“318, APP-401â€“405 | **ACTIVO** |
| **ARCO-MSG** | Sweep estados encomenda | APP-060â€“073 | PENDENTE |
| **ARCO-PROF** | Perfil + social + wallet | APP-110â€“135, APP-140â€“145 | PENDENTE |

---

# SecÃ§Ã£o 0 â€” AutenticaÃ§Ã£o e arranque

| ID | FunÃ§Ã£o (cÃ³digo) | Estado | Arco | Notas |
|----|-----------------|--------|------|-------|
| APP-001 | Login `LoginWidget` | PASS | â€” | Fase 0 antiga |
| APP-002 | Registo `RegistoWidget` | **PASS** | C22 | E2E Redmi: Cadastre-se → conta nova → home «Início» + BD auth/profile + login OK (`c22_app002_verify.json`, `c22_app002_home_after_registo.png`). |
| APP-003 | Recuperar senha `EsqueciSenhaWidget` | **PASS** | C22 | E2E no TCL: link abre redefinição, nova senha guardada, login com nova senha OK. Fix aplicado para evitar loop pós-login (`NovaSenha` ↔ login). |
| APP-004 | SessÃ£o mantÃ©m apÃ³s reopen | PASS | â€” | implÃ­cito sessÃµes QA |

---

# SecÃ§Ã£o 1 â€” Home e descoberta

| ID | FunÃ§Ã£o (cÃ³digo) | Estado | Arco | â†” |
|----|-----------------|--------|------|---|
| APP-010 | Tab **Diretos** feed live `home_page_widget` | **PASS** | ARCO-L1 | Web 2026-08-16 Â· AO VIVO + GRAVADO |
| APP-011 | Tab **Marketplace** feed `home_page_widget` | PASS | ARCO-P1 | |
| APP-012 | Pesquisa marketplace | PASS | CORRIDA 8 | 2026-07-27 |
| APP-013 | Sino notificaÃ§Ãµes | **PASS** | CORRIDA 16 | Sino com ponto vermelho â†’ tab NotificaÃ§Ãµes com lista; ADB tap C16 |
| APP-014 | FAB **Criar** sheet `fleaber_create_sheet` | **PASS** | â€” | Android TCL Maestro A001 2026-08-16 Â· Web sheet cinza (limitaÃ§Ã£o Web, nÃ£o regressÃ£o Android) |
| APP-015 | Criar â†’ Novo anÃºncio | PASS | ARCO-P1 | APP-020 |
| APP-016 | Criar â†’ Novo directo | **PASS** | ARCO-L1 | A001 â†’ prep Â«Artigos do directoÂ» TCL |

---

# SecÃ§Ã£o 2 â€” AnÃºncios e estados de artigo

| ID | FunÃ§Ã£o (cÃ³digo) | Estado | Arco | Notas |
|----|-----------------|--------|------|-------|
| APP-020 | Criar anÃºncio `seller_product_form` | PASS | ARCO-P1 | SÃ©rie P |
| APP-021 | Editar preÃ§o/tÃ­tulo | **PASS** | CORRIDA 8 | 2026-08-17 TCL+Redmi+BD: Â«C8 TaÃ§a CerÃ¢mica UÂ» **8,50 â‚¬** Â· qty 2 Â· listed |
| APP-022 | Editar imagens | **PASS** | CORRIDA 8 | 2026-08-17 2 fotos BD Â· V+B vÃªem 2Âª (anime) apÃ³s fix decode PNG; reteste B ecrÃ£ preto â†’ OK |
| APP-023 | Ocultar do marketplace | PASS | â€” | ex-050 |
| APP-024 | Republicar | PASS | â€” | ex-052 |
| APP-025 | Eliminar anÃºncio | PASS | â€” | ex-053 |
| APP-026 | Stock multi-qty feed+detalhe | **PASS** | CORRIDA 8 / C21 | C8 qty 2 BD «C8 Taça»; APP-027 pós-venda PASS; ex-BUG-027 nunca reproduzido pós-fix |
| APP-027 | Stock multi-qty feed+detalhe pÃ³s-venda | **PASS** | â€” | P/Q qty 2 |
| APP-028 | Descontos conjuntos `descontos_conjuntos` | **PASS** | ARCO-P1 / C21 | 10% activo; APP-041 totais **26,06 €**; arco conjuntos C21 fechado |

---

# SecÃ§Ã£o 3 â€” Detalhe produto e checkout individual

| ID | FunÃ§Ã£o (cÃ³digo) | Estado | Arco | Notas |
|----|-----------------|--------|------|-------|
| APP-030 | Comprar **Stripe protegido** `product_details` | WONTFIX | â€” | sandbox nÃ£o regressa app |
| APP-031 | Comprar **MB WAY/directo** | **PASS** | ARCO-P1 | 2026-08-23 bateria AVISO: sticky apos prova = «Prova enviada — aguarda…»; sem CTA Confirmo (`aviso031_no_confirmo_check.png`) |
| APP-032 | Envio **em mÃ£o** â‚¬0 | **PASS** | CORRIDA 8 | 2026-08-17 B checkout mÃ£o 0 â‚¬ + MB WAY â†’ reserva; V Pedido de Reserva 8,50 â‚¬; BD `f8a144da` `reserva_pendente` `Entrega em MÃ£o (â‚¬0.00)` |
| APP-033 | **Fazer proposta** preÃ§o `price_offer` | PASS | â€” | sÃ©rie A |
| APP-034 | Favoritar produto | **PASS** | CORRIDA 8 | 2026-08-17 B Redmi: coraÃ§Ã£o no detalhe Â· lista Favoritos Â«C8 TaÃ§a CerÃ¢mica UÂ» 8,50 â‚¬ Â· BD `favorites` 1 linha |
| APP-035 | Mensagem vendedor desde detalhe | **PASS** | CORRIDA 8 | 2026-08-17 B Contactar â†’ chat C8 8,50 â‚¬ |

---

# SecÃ§Ã£o 4 â€” Conjuntos (bundle)

| ID | FunÃ§Ã£o (cÃ³digo) | Estado | Arco | Notas |
|----|-----------------|--------|------|-------|
| APP-040 | Montar conjunto `criar_conjunto` | PASS | ARCO-P1 | P+Q |
| APP-041 | Ver conjunto totais `ver_conjunto` | PASS | â€” | **26,06 â‚¬** |
| APP-042 | Proposta preÃ§o conjunto | **PASS** | â€” | via APP-083 ciclo 2 (3 artigos) |
| APP-043 | Vendedor aceita proposta | **PASS** | â€” | 2026-08-23 AVISO ronda 2: chat conjunto `3b0cbd8d` (não reserva `c138a678`); thread B «Conjunto · 2 artigos» + cards «Conjunto comprado»/«Artigos enviados» sem duplicados visíveis. Prints `aviso083_*`. |
| APP-044 | Comprar conjunto Stripe `payBundleNow` | WONTFIX | â€” | sandbox |
| APP-045 | Chat comprador card conjunto | PASS | â€” | |
| APP-046 | Chat vendedor etiqueta/envio | PASS | â€” | BUG-036 fechado |
| APP-047 | **Conjunto multi-qty** (2Ã—P + 1Ã—Q) | **PASS** | â€” | steppers + stock final P=0 Q=1 |

---

# SecÃ§Ã£o 5 â€” Encomendas e pÃ³s-venda

| ID | FunÃ§Ã£o (cÃ³digo) | Estado | Arco | â†” |
|----|-----------------|--------|------|---|
| APP-050 | Minhas encomendas comprador | PASS | ARCO-P1 | |
| APP-051 | Encomendas vendedor | PASS | ARCO-P1 | |
| APP-052 | Agrupamento `bundle_id` conjunto | PASS | ARCO-P1 | |
| APP-053 | â‹® **Cancelar** encomenda | **PASS** | CORRIDA 8 | 2026-08-17 V â‹® Cancelar Â«V0 bag prod aÂ» â†’ UI Cancelado + BD `ba2eb26b` `cancelado` Â· **nÃ£o** tocou na paga C5 `ce4fba72` |
| APP-054 | â‹® **Vender outro igual** | **PASS** | CORRIDA 8 | 2026-08-17 V â‹® tigela cerÃ¢mica Y â†’ Â«Artigo recolocadoÂ» Â· BD produto novo `256c14d0` listed `REF-â€¦/2` |
| APP-055 | Envio + **descarregar etiqueta** | **PASS ATÉ API** | â€” | 2026-08-23 auditor: stub OK (CTA → enviado). Sem wizard intermédio no produto actual — não inventar UX só para teste histórico. Regressão obrigatória com **API transportadora** (etiqueta real → morada/QR → entrega carrier → tracking → BD → V/B). Ver `PASS_ATE_API_REGRESSION.md`. Prints `aviso055_*`. |
| APP-056 | Comprador **confirmar receÃ§Ã£o** | **PASS** | ARCO-P1 | 2026-08-23: eco V «O comprador confirmou a receção…» (`aviso056_seller_timeline.png`); seed `744091ae…` |
| APP-057 | **Feedback/avaliaÃ§Ã£o** pÃ³s-venda | **PASS** | â€” | compra 3 artigos 2026-07-06 |
| APP-058 | Pedido **devolução/disputa** | **PASS** | ARCO-MSG | C25 2026-08-22: Regression 5 € (`e04a0fde…`). Guard UI: vazio bloqueia, `abc` (3/6) bloqueia, `abcdef` sem erro + fecho sem submeter. BD 0 disputas. Prints `c25_a3_p1`/`p3`/`p4_valid_closed`. Undo acidental: `c25_undo_dispute_order.dart`. |

### Sweep estados `orders.status` (render encomendas + chat)

| ID | Estado BD | Estado QA | Arco |
|----|-----------|-----------|------|
| APP-060 | reserva_pendente | **PASS** | CORRIDA 17 | Â«Pedido de ReservaÂ» laranja + Ã­cone relÃ³gio; BD 2Ã—reserva_pendente confirmado |
| APP-061 | reservado | **PASS** | C26 | 2026-08-22: V aceita `reserva_pendente` `f8a144da…` → BD `reservado` + `reservation_expires_at`. UI «Aceitar e Enviar Dados». Prints `c26_061_*`. |
| APP-062 | pendente | N/A (retirado) | C19 | Estado legado: nÃ£o Ã© produzido pelos fluxos atuais da app; mantido apenas como compatibilidade de leitura. |
| APP-063 | aguarda_confirmacao â†’ pago MB WAY conjunto | **PASS** | C5 / C17 / C21 | APP-214d/e + APP-064; C17 label «Pagamento em Verificação»; nota «053–055 UX» era imprecisa |
| APP-064 | pago | **PASS** | ARCO-P1 | conjunto MB WAY 2026-07-06 |
| APP-065 | enviado | **PASS** | ARCO-MSG | 2026-08-23: card Conjunto fechado «Artigo Enviado» (BUG-038). Prints `app065_conjunto_visible` + `app065_user_expanded_now`; BD bundle `b2563d6c` 2×enviado. |
| APP-066 | entregue | PASS | â€” | via APP-056 |
| APP-067 | concluido | **PASS** | â€” | compra 3 artigos 2026-07-06 |
| APP-068 | cancelado | **PASS** | CORRIDA 17 | Â«CanceladoÂ» vermelho + Ã­cone Ã—; BD 8Ã—cancelado confirmado |
| APP-069 | pedido_devolucao | **PASS** | C25 | 2026-08-22 E2E Regression 5 € (`e04a0fde…`): B abre disputa → BD `pedido_devolucao` + disputa `aberta` (`03fa9312…`). Print `c25_b1_dispute_opened_buyer.png`. |
| APP-070 | em_devolucao | **PASS** | C25 | 2026-08-22 E2E: B aceita proposta return → BD `em_devolucao` + etiqueta. Fix botões pós-aceite (`BUG_C25_BUYER_OFFER_BUTTONS`). Prints `c25_b3_*`. |
| APP-071 | devolucao_entregue | **PASS ATÉ API** | C25 | Stub actual OK («Descarregar etiqueta» → `devolucao_entregue`). Regressão obrigatória quando existir **API transportadora** (descarregar ≠ entrega real; estado enviado = evento carrier). Ver `PASS_ATE_API_REGRESSION.md` + `BUG_C25_RETURN_LABEL_CHROME.md`. |
| APP-072 | disputa_devolucao_vendedor | **PASS** | C26 | 2026-08-22 E2E: V «Abrir problema com a devolução» → BD `disputa_devolucao_vendedor` + disputa `escalada_fleaber` + `seller_return_issue_at`. Order C25 rewind branch `e04a0fde…`. Prints `c26_072_*`. |
| APP-073 | devolvida | **PASS** | C25 | 2026-08-22: V confirma devolução OK → BD `devolvida` + disputa `resolvida` + `wallet_refund_processed_at`. Prints `c25_b5_*`. |

---

# SecÃ§Ã£o 6 â€” Chat DM (cards `FLEABER_JSON_V1` + texto)

| ID | `kind` / tipo | Estado | Arco |
|----|---------------|--------|------|
| APP-080 | Texto livre compradorâ†”vendedor | **PASS** | CORRIDA 8 | 2026-08-17 Â«ola C8 testeÂ» B+V+BD msg 654 |
| APP-081 | `price_offer` | PASS | â€” | sÃ©rie A |
| APP-082 | `price_offer_outcome` | PASS | â€” | aceite/recusa A |
| APP-083 | `bundle_proposal` | **PASS** | â€” | 2026-08-23 AVISO ronda 2: chat `3b0cbd8d` bundle `b2563d6c`; header «Conjunto · 2 artigos» Total pago 26,53 €; timeline limpa. BD total conjunto 21,15 € (base V). Prints `aviso083_*`. |
| APP-084 | `bundle_proposal` outcome | N/A (retirado) | C21 | Tipo `bundle_proposal_outcome` nunca foi implementado na app. Aceite/recusa do conjunto actualiza o **mesmo** card `bundle_proposal` (headline «Compra em conjunto aceite» / «Pedido de conjunto recusado») — já coberto por APP-083 + APP-043 + arco conjuntos. Teste invalidado; seed C21 era artefacto artificial. |
| APP-085 | Card compra paga (inject) | **PASS** | C27 | 2026-08-23: pagamento real E2E APP-214 — order `744091ae…`/`9b65a63d…` pago + chat pós-pagamento (BD `c27_post_user_pay.json`) |
| APP-086 | Card enviado (inject) | **PASS** | ARCO-P1 | 2026-08-23: timeline «Artigos enviados!» sem card azul carrinha (`aviso086_timeline_bottom.png`); BUG-037 residual nao visto |
| APP-087 | `reservation_request` | **PASS** | CORRIDA 18 | Card + sticky + botÃµes Aceitar/Recusar visÃ­veis; thread C8 TaÃ§a |
| APP-088 | `reservation_accepted` | **PASS** | CORRIDA 12 | Directo + saco: Â«Ficaste com C12â€¦ 5 dias para pagarÂ». Card no Mensagens = ciclo com encomenda (C5). Sem inject. |
| APP-089 | `reservation_payment_submitted` | **PASS** | CORRIDA 18 | Â«O comprador confirmou o pagamentoÂ» visÃ­vel; payment_details + confirmaÃ§Ã£o |
| APP-090 | `reservation_order_shipped` | **PASS** | CORRIDA 18 | Card visual confirmado em chat (Redmi, 2026-08-19) + BD 4Ã— msgs |
| APP-091 | `reservation_order_completed` | **PASS** | CORRIDA 18 | Card visual confirmado em chat (Redmi, 2026-08-19) + BD 5Ã— msgs |
| APP-092 | `cancel_request` + outcome | **PASS** | CORRIDA 18 | cancel_request (Claudia) + outcome Â«vendedor anulouÂ» (V0 bag) visÃ­veis |
| APP-093 | `order_dispute_opened` | **PASS** | C25 | 2026-08-22: card chat «Disputa aberta» (motivo Artigo Danificado, descrição, turno Vendedor, prazo 25 ago.). Print `c25_b1_dispute_opened_buyer.png` + BD. |
| APP-094 | `chat_image` | **PASS** | CORRIDA 8 | 2026-08-17 B+V: foto no chat C8 Â· BD msg 655 `kind=chat_image` |
| APP-095 | Lembrete pagamento/envio | **PASS** | ARCO-P1 | Maestro 2026-08-23: pos-aceite sem lembrete imediato; BD reservado |

---

# SecÃ§Ã£o 7 â€” Perfil, conta, social

| ID | FunÃ§Ã£o (cÃ³digo) | Estado | Arco |
|----|-----------------|--------|------|
| APP-110 | Perfil prÃ³prio menu `perfil_widget` | **PASS** | ARCO-PROF | Web 2026-08-16 Maria |
| APP-111 | Perfil pÃºblico tab **Diretos** | **PASS** | ARCO-PROF | TCL 2026-08-16 Em directo + anteriores |
| APP-112 | Perfil pÃºblico tab **Marketplace** | PASS | ARCO-P1 |
| APP-113 | Perfil pÃºblico tab **OpiniÃµes** | **PASS** | CORRIDA 9 | 2026-08-17 B: 3 opiniÃµes (5/4/5) Â· BD 3 reviews `3188f08c`/`f6cf073f`/`f8df9e3d` Â· JSON `evidence/c9_gpt_audit_evidence.json` |
| APP-114 | **Seguir** / A Seguir `follows` | **PASS** | CORRIDA 9 | 2026-08-17 B Seguir Maria â†’ Â«A SeguirÂ» Â· 13 seguidores Â· BD `follows` `2842b66b` (buyerâ†’seller) Â· 13 linhas `following_id` Â· JSON `evidence/c9_gpt_audit_evidence.json` |
| APP-115 | Lista conversas `lista_conversas` | **PASS** | â€” | TCL smoke 2026-08-16 tab Mensagens |
| APP-120 | DefiniÃ§Ãµes: **MB WAY + IBAN + pagamentos externos** | **PASS** | â€” | print 14:35 |
| APP-121 | DefiniÃ§Ãµes: morada envio | **PASS** | CORRIDA 8 | 2026-08-17 V: secÃ§Ã£o visÃ­vel + BD `shipping_line1` preenchida, cidade `hvhfhbcg`, CP 2600, PT Â· **Ã¢mbito:** mostrar morada guardada. Gravar+reabrir+etiqueta/checkout = APP-055 (nÃ£o repetido nesta corrida) |
| APP-122 | Modo fÃ©rias `modo_ferias` | **PASS** | â€” | Web 2026-08-16 toggle Desligado |
| APP-123 | GestÃ£o referÃªncias live | **PASS** | ARCO-L1 | Web 2026-08-16 FX* Ativo |
| APP-124 | Resultados directos `live_sales_sessions` | **PASS** | ARCO-L1 | C6 17 Ago: lista 2 un./13,50 â‚¬; resumo Vendas 1 linha 13,50 â‚¬ Pago (nÃ£o 10+13,50) |
| APP-125 | Favoritos lista | **PASS** | ARCO-PROF | Web empty-state OK |
| APP-126 | FleaHub sheet seller `hub_seller_sheet` | **PASS** | ARCO-H1 | Ver/Copiar/Partilhar/Ocultar |
| APP-127 | Equipa/colaboradores | **PASS** | CORRIDA 9 | 2026-08-18 ciclo completo V TCL + B Redmi: convite `QA C9 helper` â†’ BD `pending` â†’ B aceita â†’ V Â«Ãšltima actividadeÂ» + log `helper_invitation_accepted` â†’ permissÃµes 7 ligadas/resto off â†’ V remove â†’ log `helper_removed` 13:02 + BD `seller_helpers` = 0 |
| APP-128 | Acesso helper | **PASS** | CORRIDA 9 | 2026-08-18 B Redmi apÃ³s aceitar: Â«Acesso de colaboradorÂ» a trabalhar para Maria Demo FleaHub, papel QA C9 helper, Permitido (7) / Sem acesso (12) coerente com o convite. Copy dono jÃ¡ corrigido no TCL. ApÃ³s remover, B volta a nÃ£o ter loja aceite (BD 0 helpers) |

---

# SecÃ§Ã£o 8 â€” Wallet

| ID | FunÃ§Ã£o | Estado | Arco |
|----|--------|--------|------|
| APP-140 | Ver saldo `wallet_page` | **PASS** | CORRIDA 9 | 2026-08-17 UI=BD 62,62 â‚¬ + retido 456,88 â‚¬. **2026-08-18 pÃ³s-levantamento:** TCL **61,62 â‚¬** + retido 456,88 â‚¬ = BD `wallets.balance` 61.62 (`c9_remaining_snapshot.json`, print `c9_142_pass.png`) |
| APP-141 | HistÃ³rico movimentos | **PASS** | CORRIDA 9 | 2026-08-17 tx `9a4271d9` compra Â«Camisola Nike Preta MÂ» **âˆ’36,88 â‚¬**. **2026-08-18** tx `722ef6c7` tipo `levantamento` **âˆ’1,00 â‚¬** 14:42 Â· UI=BD |
| APP-142 | Pedido levantamento | **PASS** | CORRIDA 9 | 2026-08-18 TCL: Transferir **1,00 â‚¬** sandbox â†’ sucesso. UI 61,62 â‚¬ + linha Â«Levantamento para conta bancÃ¡ria âˆ’1,00 â‚¬Â». BD `wallets.balance` 61.62 Â· tx `722ef6c7` Â· Stripe Connect `acct_1U5mYbQeUNx8ar08` Â· print `tool/reports/battery_c9_2026-08-18/screenshots/c9_142_pass.png` |
| APP-143 | Cancel Seguro Fleaber → **refund Stripe auto** (cartão); V saldo/retido **não** sobe | **PASS** | ARCO-PROF | 2026-08-24 TCL: encomenda `0f632c04` 12,20 € → `cancelado` + `stripe_refund_id=re_3U7WN8…`; saldo V 76,99 inalterado. Pack: `battery_143_145_2026-08-24` |
| APP-144 | Cancel MB WAY pago → **sem** Stripe; V/B combinam; carteira Fleaber inalterada | **PASS** | ARCO-PROF | 2026-08-24 TCL: `70517197` 22 € MB WAY → `cancelado`; `stripe_refund_id=null`; saldos V/B inalterados; chat «anulou a venda» **sem** Stripe |
| APP-145 | Após cancel Seguro: V **não** tem crédito «venda»; B vê msg reembolso iniciado | **PASS** | ARCO-PROF | 2026-08-24 Redmi: chat `24142887` «Reembolso Stripe iniciado…»; ledger B compra−12,20 + reembolso+12,20; V sem crédito venda |
| APP-146 | Disputa → `devolvida` → crédito carteira comprador | **PASS** | C25 | Auditoria: 1.º reembolso +5 sem abate etiqueta (FAIL vs UI). Fix SQL `c25_refund_deduct_return_label_fee_batata.sql` + reprocess: reembolso **+1,50 €** (5−3,50). Prova `bd/c25_app146_*.json`. |

---

# SecÃ§Ã£o 9 â€” Live (vendedor + comprador)

| ID | FunÃ§Ã£o (cÃ³digo) | Estado | Arco | â†” |
|----|-----------------|--------|------|---|
| APP-200 | Preparar directo `preparar_directo` | **PASS** | Hub H / A0-PREP | 2026-08-23: 1 C27 ON → catálogo 1 artigo (reteste humano + allow-list pref regressão). |
| APP-201 | Linhagem refs prep | **PASS** | C22 | Manual E2E confirmado: criar intervalo em «Sem catálogo», guardar e validar persistência no prep. |
| APP-202 | Criar directo `criar_directo` | **PASS** | CORRIDA 11 | TCL Novo directo â†’ Iniciar Â· Mux real Â· Chrome viu o vÃ­deo |
| APP-203 | Studio vendedor ops `live_stream_vendor` | **PASS** | CORRIDA 11 | Retest: C11 na vitrine Â· 1 reserva Â· 3 disp. = BD |
| APP-204 | +Stock no live | **PASS** | CORRIDA 13 | TCL C13 2â†’4 disp. = BD `quantity` 4 Â· Hub 9,00 â‚¬ |
| APP-204b | Marcar como esgotado (manual, sem venda na app) | **PASS** | ARCO-L1 / C6 | Copy Â«EsgotadoÂ»; Â«VendidosÂ» = vendas Fleaber. Reteste visual na prÃ³xima live. |
| APP-205 | PreÃ§o pendente item | **PASS** | CORRIDA 14 | TCL 0â‚¬ â†’ 11â‚¬ = BD Â· Hub saco Â«PreÃ§o a definir pela vendedoraÂ» Â· depois 11,00 â‚¬ |
| APP-210 | Player comprador `fleaber_live_player` | **PASS** | CORRIDA 11 | Chrome Hub live: vÃ­deo da cÃ¢mara TCL + chat |
| APP-211 | Reservar artigo live | **PASS** | CORRIDA 11 | C11 Produto A 7,50 â‚¬ Ã—1 pending Â· BD+saco |
| APP-212 | Aceitar reserva vendedor | **PASS** | CORRIDA 12 | TCL Aceitar C12 Â· BD `aaf7bc85` `accepted` Â· overlay 4 disp. Â· 1 reserva |
| APP-213 | Adicionar ao saco | **PASS** | CORRIDA 11 | Hub saco Â«2 artigos Â· 2 unidadesÂ» = BD |
| APP-214 | Saco checkout pagar (pai — Stripe na app) | **PASS** | C27 reteste pós-fix | 2026-08-23: encomenda `9b65a63d…` — UI/Stripe/BD/wallet **15,88 €**; reserva `f56d03d1…` converted. Histórico `0f632c04…` 12,20 € = pré-fix. |
| APP-214a | Saco: pagamento directo ao vendedor | **PASS** | ARCO-L1 / C5 | 2026-08-17 Â· BD `payment_method` directo |
| APP-214b | V aceita reserva antes dos dados MB WAY | **PASS** | ARCO-L1 / C5 | 2026-08-17 reteste Â· BD `accepted` |
| APP-214c | B vÃª Â«Ver dados de pagamentoÂ» apÃ³s aceite | **PASS** | ARCO-L1 / C5 | 2026-08-17 |
| APP-214d | B envia prova â†’ encomenda `aguarda_confirmacao` | **PASS** | ARCO-L1 / C5 | 2026-08-17 reteste Â· BD `aguarda_confirmacao` |
| APP-214e | V vÃª pedido para confirmar dinheiro | **PASS** | ARCO-L1 / C5 | 2026-08-17 |
| APP-215 | Cancelar reserva saco | **PASS** | CORRIDA 12 | Chrome Gerir reservas â†’ Cancelar Â· BD `123ececc` `rejected` + `bag_removed` Â· saco 1/1 |
| APP-216 | Rifa live | PASS (nota 216b) | ARCO-L1 | M12 |
| APP-217 | Gorjeta tip | PASS | C21 | Fluxo técnico completo validado em BD (`c21_app217_tip_flow.json`) + confirmação visual no player Redmi da linha de gorjeta de 2€ (`c21_app217_tip_line_final_confirmed.png`). |
| APP-218 | Chat pÃºblico live humanizado | **PASS** | CORRIDA 14 / C15 | 2026-08-23 AVISO live: B Redmi «ola AVISO218 teste humano» → V Oppo tab Chat. Prints `aviso218c_buyer_msg_visible` + `aviso218b_seller_chat_proof`. BD `live_messages` kind=chat. Live `3997db80` ended. |

### Reservas `live_reservation_requests.status`

| ID | Status | Estado |
|----|--------|--------|
| APP-250 | pending | **PASS** | CORRIDA 11 | 2 reservas pending (C11 + V0) sobrevivem ao live ended |
| APP-251 | accepted | **PASS** | CORRIDA 12 | C12 aceite no saco + BD `accepted` |
| APP-252 | rejected | **PASS** | CORRIDA 12 | TCL Recusar Â· `d770bd44` `rejected` (sem `bag_removed`) |
| APP-253 | expired | **PASS** | C27 | 2026-08-23: reserva A `40250c32…` pending→accepted→**expired** via RPC `expire` (sem cron). Stock libertado. `bd/c27_after_expire_253.json`. |
| APP-254 | converted | **PASS** | C27 | 2026-08-23: ligação via `notes` `stripe_paid:{order_id}` (FKs null esperados). Reteste pós-fix: `f56d03d1…`/`a5f0b7f6…` → converted. Auditor independente: PASS. |

---

# SecÃ§Ã£o 10 â€” Hub / FleaHub

| ID | FunÃ§Ã£o | Estado | Arco | â†” |
|----|--------|--------|------|---|
| APP-300 | Activar/publicar FleaHub | **PASS** | CORRIDA 10 | 2026-08-18 TCL sheet: publicado, `fleaber.pt/fleahub-demo-ux`, Ver/Copiar/Partilhar, Ocultar Â· BD `hub_published=true` handle `fleahub-demo-ux` |
| APP-301 | Link pÃºblico handle | **PASS** | CORRIDA 10 | Chrome hash URL + views `hub_*` com chave anÃ³nima (sem JWT de utilizador): perfil Maria, 31 produtos, 3 reviews. Tab nova mostra Â«SeguirÂ» (sem sessÃ£o da Maria) |
| APP-302 | Hub perfil pÃºblico `hub_profile_page` | **PASS** | CORRIDA 10 | TCL Ver + Chrome: seller verificada, 4,7, Marketplace visÃ­vel (amostra). NÃ£o Ã© teste de sync completa |
| APP-303 | Hub marketplace grid | **PASS** | CORRIDA 10 | Grelha TCL/Chrome: tigela 8,00 â‚¬ Â· C8 TaÃ§a 8,50 â‚¬ Â· travessa 12 â‚¬ Â· caneca 12 â‚¬. BD: **31** listados (o Â«8Â» da 1Âª snapshot era sÃ³ os 30 mais recentes). Fotos mÃ¡s = ficheiros no anÃºncio, nÃ£o bug Hub |
| APP-304 | Hub secÃ§Ã£o Gravados | **PASS** | ARCO-H1 | **PASS C6** (card GRAVADO). C10 sÃ³ passou pela secÃ§Ã£o (scroll); nÃ£o revalidou VOD |
| APP-305 | Hub entrar no directo | **PASS** | CORRIDA 11 | Chrome perfil â†’ Â«Entrar no directoÂ» Â· â†” APP-210 |
| APP-306 | Hub saco/reservas comprador | **PASS** | CORRIDA 11 | Saco Hub = BD 2 unidades Â· â†” APP-213 |
| APP-307 | Hub avaliaÃ§Ãµes | **PASS** | CORRIDA 10 | Chrome 3 opiniÃµes 5/4/5 Â«UX demo FleaHubÂ» = BD 3 reviews `target_id` Maria |
| APP-308 | Hub oculto vs publicado | **PASS** | ARCO-H1 | C6: UI + BD `hub_published` publicadoâ†’ocultoâ†’publicado Â· C10 nÃ£o repetiu o ciclo (jÃ¡ publicado) |

---

# SecÃ§Ã£o 11 â€” Cross-superfÃ­cie (obrigatÃ³rio em cada arco)

| ID | VerificaÃ§Ã£o | Estado | Arco |
|----|-------------|--------|------|
| APP-400 | Compra marketplace â†’ aparece encomendas B+V | PASS | ARCO-P1 |
| APP-401 | AnÃºncio marketplace â†’ aparece Hub loja | **PASS** | CORRIDA 10 | Amostra: C8 TaÃ§a 8,50 â‚¬ + tigela Y 8,00 â‚¬ no Hub e na BD (`list_on_marketplace`). NÃ£o cobre criar anÃºncio novo nesta corrida nem APP-405 |
| APP-402 | Stock apÃ³s venda â†’ feed + perfil + Hub | PASS | C21 | Hotfix staging aplicado (`c20_app402_no_double_count_paid_batata.sql`) + reteste controlado BD passou (5â†’2â†’3; cancelamento â†’5) + confirmação UX final no Hub live (Redmi): total inicial 3, vendidos 2, disponível agora 3 (`c21_app402_hub_live_final_confirmed.png`). |
| APP-403 | Live item â†’ marketplace origem coerente | PASS | C19 | Assert reforÃ§ado sem truncagem: 160 `live_items` marketplace_product auditados, 160/160 com `product_id` encontrado e 0 mismatch de `ref_code` (`c19_contraditorio_403_raw.json`). |
| APP-404 | Reserva live â†’ DM + encomendas | **PASS** | CORRIDA 12 | Reserva aceite = saco + chat do directo. Mensagens/Encomendas no ciclo **pago** (C5 APP-400). 0 encomendas C12 antes de pagar = correcto |
| APP-405 | Ocultar anÃºncio â†’ some InÃ­cio+perfil+Hub | PASS | ex-051 |

### Mapa Corrida 5 â€” o que se testou vs IDs desta lista (2026-08-17)

A Corrida 5 **nÃ£o substitui** o significado dos IDs abaixo. Sem este mapa, a cobertura ficava falsa.

| O que a Corrida 5 fez | ID correcto nesta lista | IDs que **nÃ£o** foram cobertos por esse passo |
|------------------------|-------------------------|-----------------------------------------------|
| Comprador vÃª a encomenda **paga** (13,50 â‚¬) | APP-064 (estado `pago`) + APP-400 | APP-060 continua a ser sÃ³ `reserva_pendente` |
| Vendedor vÃª a **mesma** encomenda | APP-400 | APP-061 continua a ser sÃ³ estado `reservado` |
| Stock apÃ³s venda paga (disp./vendidos/reservas) | APP-402 (stock pÃ³s-venda) | APP-404 continua a ser Â«reserva live â†’ DM + encomendasÂ» |
| Pagamento directo no saco (passos aâ€“e) | APP-214a â€¦ APP-214e | APP-214 (pai) = Stripe na app → **PASS** C27 reteste |

APP-060 / APP-061 / APP-404 **mantÃªm** o texto original da lista. NÃ£o foram Â«reutilizadosÂ».

---

# SecÃ§Ã£o 12 â€” Legal / info (smoke)

| ID | FunÃ§Ã£o | Estado |
|----|--------|--------|
| APP-500 | Como funciona | **PASS** | CORRIDA 9 | 2026-08-17 TCL: documento Â«Como funciona o FleaberÂ» |
| APP-501 | FAQ | **PASS** | CORRIDA 9 | 2026-08-17 TCL: Â«Perguntas FrequentesÂ» acordeÃ£o |
| APP-502 | InformaÃ§Ã£o legal hub | **PASS** | CORRIDA 9 | 2026-08-18 TCL: menu + destinos abertos um a um â€” how, FAQ, Sobre, Privacidade, Termos, Reembolsos, Cookies, **EliminaÃ§Ã£o de conta e dados**, landing FleaHub |

---

# SecÃ§Ã£o SEC â€” SeguranÃ§a (retest pÃ³s-hardening)

> **C23 2026-08-20:** bateria API auto corrida (`tool/c23_sec_auto_battery.dart`) — ver `tool/reports/battery_c23_sec_2026-08-20/`.  
> AVISOs = falta happy-path UI / PS Reader / residual documentado.  
> Passos UI: `tool/SECURITY_QA_RETEST.md` · Inventário: `docs/SECURITY_AUDIT_INVENTORY.md`

| ID | FunÃ§Ã£o | Estado | Liga a | Notas |
|----|--------|--------|--------|-------|
| APP-SEC-001 | Bloquear auto-admin `user_type` | **PASS** (API C23 2026-08-20) | APP-002, admin | ataque PATCH bloqueado |
| APP-SEC-002 | Guard estados encomenda (pago/enviado/concluído) | **PASS** (API C23) | chat MB WAY, rifa, disputa | 4 ataques buyer bloqueados |
| APP-SEC-003 | Lives sem stream keys no SELECT | **PASS** | Home Diretos, criar directo | API C23 + UX B C24 + **seller UI C25** (`c25_c2_seller_create_live.png`): Artigos do directo / FleaHub — sem keys/RTMP/tokens no ecrã. |
| APP-SEC-004 | RPC stripe_convert só servidor | **PASS** (API C23) | checkout live smoke | RPC negada ao cliente |
| APP-SEC-008 | PS pairing rate-limit (6 dígitos residual) | **PASS COM AVISO** (API C23) | PS Reader PC | RPC claim revogada; PS real não |
| APP-SEC-009 | Prémio rifa via draw (RPC directa revogada) | **PASS** (API C23) | rifa catálogo | RPC directa 404 |
| APP-SEC-010 | Tickets rifa via join/share | **PASS** (API C23) | rifa live | award RPC 404; join UI não |
| APP-SEC-013 | Claim FB scoped + identidade `fb:{id}` | **PASS COM AVISO** | Hub + PS Face | Captura DOM PASS; ingest PS pode gravar `fb:`; claim OAuth **provisório até GATE 1** (DOM↔provider_id); faltam contas QA A/B + testes A≠B + homónimos controlados |
| APP-SEC-012 | Lookup email rate-limit (helpers) | **PASS** (API C24) | equipa / helpers | rate_limited após 31 lookups |
| APP-SEC-014 | Helper não alarga permissions ao aceitar | **PASS** (API C23) | equipa / convites | escalate finances bloqueado |
| APP-SEC-016 | Resolve Mux playback rate-limit + VOD no-overwrite | **PASS** | C26 | Edge resolve 200 VOD `3d4ecb60…` (`c26_sec016_scan.json`). UI player Gravados: badge **GRAVADO**, sem stream keys (`c26_sec016_vod_player_b.png`). |
| APP-SEC-017 | Create Mux live quota 10/dia | **PASS** (API C23 + UI C11–C27) | Criar directo | C23: sem auth 401; UI: lives reais criadas/terminadas C11–C27 (ex. `bf03d449…` ended) |
| APP-SEC-019 | CORS Hub + extensão PS | **PASS COM AVISO** (API C23) | Hub PC, PS | OPTIONS evil≠espelha; PS não |
| APP-SEC-020 | Chat sistema / FOMO rate-limit | **PASS** (API C23 + UI 2026-08-23) | saco live | C23 broadcast revogado; UI FOMO «Última unidade de C27 Produto B» no chat B+V (`sec020_buyer_live_chat`, seller Chat). Live `3997db80` ended. |
| APP-SEC-021 | Recompact/recompute ownership | **PASS** (API C23 + UI C12/C27) | saco + studio | C23 outsider `not_allowed`; UI: C12 aceitar/recusar/cancelar saco + C27 reconcile_bag |
| APP-SEC-022 | `app_logs` só autenticado | **PASS** (API C23 retest auditor) | smoke logs | anon permission denied; schema via service |
| APP-SEC-023 | Studio logs sem spoof seller | **PASS** (API C23 retest auditor) | ARCO-L1 studio | buyer spoof RLS 403; seller INSERT OK |
| APP-SEC-024 | Chat/viewers SELECT scoped | **PASS** (API C23 retest auditor) | player live + studio | service 2 viewers; buyer só vê self |
| APP-SEC-027 | Storage chat_media policies | **PASS** | chat foto C25 | API C24 + UI C25: foto enviada no chat B→V (prints `c25_c1_*`). |
| APP-SEC-025 | Wallet/disputa só participantes | **PASS** (API C23 + UI 2026-08-23) | reembolso parcial chat | Auditor indep. 2026-08-23: Aceitar/Recusar UI; Aceitar → `concluido` + disputa `resolvida` + wallet; SQL `#11b`. Prints `sec025_retest_*`. Cards duplicados = lixo QA thread reutilizada (ver nota cabeçalho). |
| APP-SEC-011 | Refund Stripe sÃ³ vendedor | PASS (staging QA) | anular venda Seguro Fleaber | SEC-011 |
| APP-SEC-034 | Tip GET settle + gorjeta mobile Stripe | PASS (V+B 2026-08-09) | gorjeta live | SEC-034 |
| APP-SEC-005 | Webhook/return + Confirmar compra mobile | PASS Chrome+Redmi (2026-08-09) | checkout Stripe | SEC-005 |

---

# SecÃ§Ã£o NAV â€” IncluÃ­da nas corridas (automatizar quando possÃ­vel)

Back Android, tabs, deep links, Hubâ†”app, sheets. **Conta para o plano de corridas**; IDs abaixo entram na automaÃ§Ã£o Maestro/ADB. NÃ£o excluir.

| ID | FunÃ§Ã£o | Estado | Notas |
|----|--------|--------|-------|
| NAV-001 | Tabs fundo (InÃ­cio / Diretos / Marketplace / Mensagens / Perfil) | **PASS** | CORRIDA 15 | Maestro: Mensagensâ†’Perfilâ†’InÃ­cio COMPLETED; screenshots c15_nav001_* |
| NAV-002 | 1Ã— Back Android em ecrÃ£ empilhado | **PASS** | CORRIDA 15 | Maestro: Mensagens â†’ Back â†’ InÃ­cio; 1 toque suficiente |
| NAV-003 | Deep links app (`fleaber://â€¦`) | **PASS** | CORRIDA 16 | `/wallet` `/criarSheet` `/criarDirecto` nav OK; quota Mux = ambiente staging, não falha de deep link |
| NAV-004 | Visitar FleaHub e voltar (Z1) | **PASS** | CORRIDA 10 | 18 Ago reteste: 1 voltar do Hub cai no Perfil (Modo pessoal, O meu Saldo). Folha fecha antes; nÃ£o salta para o InÃ­cio |
| NAV-005 | Sheet Criar abrir / fechar | **PASS** | CORRIDA 15 | Maestro: sheet Criar abriu (Novo AnÃºncio + Novo Direto); Back fechou; screenshot c15_nav005_* |
| NAV-006 | Saco abrir / fechar / back | **PASS** | CORRIDA 11 | Fecha o saco; fica Â«Ver saco e pagarÂ» |
| NAV-007 | Entrar / sair player live ou gravado | **PASS** | CORRIDA 11 | Saiu do player para o perfil Hub |
| NAV-008 | Login / logout sessÃ£o | **PASS** | CORRIDA 16 | clearState+autologin OK via Maestro; Â«Terminar SessÃ£oÂ» confirmado manualmente pelo utilizador |

---

## Auditoria cÃ³digo â†’ lista (confirmaÃ§Ã£o)

Varrimento `lib/index.dart`, `nav.dart`, `perfil_widget`, `chat_page_widget`, `MESSAGE_BATTERY.md`, `product_details`, `home_page`, Hub routes:

| Ãrea cÃ³digo | Coberto na lista? |
|-------------|-------------------|
| Todas as rotas `index.dart` (exc. Maestro/debug) | **Sim** |
| Checkout 2 modos pagamento + mÃ£o | **Sim** APP-030â€“032 |
| `external_payments` conta | **Sim** APP-120 (setup arco, nÃ£o pergunta) |
| 14 estados `orders.status` | **Sim** APP-060â€“073 |
| 5 estados reserva live | **Sim** APP-250â€“254 |
| 15+ kinds chat JSON | **Sim** APP-080â€“095 |
| Perfil menu 15+ entradas | **Sim** APP-110â€“128 |
| Live prep+studio+player | **Sim** APP-200â€“218 |
| Hub pÃºblico+seller | **Sim** APP-300â€“308 |
| Cross-surface | **Sim** APP-400â€“405 |
| Admin `admin_page` | **N/A** staging restrito |
| `lives_web_dashboard` | **N/A** web staff |

**Gaps intencionais:** Maestro harness pages, admin sem conta. **NAV entra nas corridas** (NAV-001â€“008).

---

## PrÃ³ximo executÃ¡vel

**ACTIVO** â€” **ARCO-H1** Hub (`tool/reports/hub_h_manual_qa_battery.md`).

Retestes marketplace (072, 067, 071): `tool/B1_NEXT_C1_BATCH.md` â€” sÃ³ quando a bateria passar pelo sÃ­tio.

**Fila seguranÃ§a (nÃ£o esquecer):** `tool/SECURITY_QA_RETEST.md` Â· SQL: `docs/SECURITY_SQL_APPLY_LIST.md` â€” APP-SEC-001â€¦004, 008â€“014, 016â€“017, 019â€“025, 027, 034.

