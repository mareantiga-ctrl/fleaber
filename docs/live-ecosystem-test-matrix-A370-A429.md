# Matriz expandida — A370 a A429

**Área:** Helpers · equipa · permissões · erros · multi-device · sync · arquitectura  
**Versão:** 1.0 · **2026-06-14**  
**Estado:** Fichas expandidas — **sem implementação de testes**.

Substitui a tabela compacta A370–A429 em `live-ecosystem-test-matrix.md`.

**Nota:** A377–A389 e A401–A419 estavam vazios no índice compacto; preenchidos nesta expansão com testes alinhados à faixa (helpers/permissões e erros/recuperação/multi-device).

---

## A370 — Convidar helper

| Campo | Valor |
|-------|-------|
| **ID** | A370 |
| **Nome** | Seller convida colaborador por e-mail |
| **Pré-condições** | Seller autenticado; conta helper já registada com e-mail conhecido; seller **não** em modo colaborador |
| **Passos** | 1. Perfil → Equipa / Colaboradores 2. «Adicionar colaborador» 3. Preencher e-mail + nome + permissões default 4. Confirmar |
| **Resultado esperado** | Row `seller_helpers` com `invitation_status=pending`, `active=false`; snack «Convite pendente»; helper vê banner convite (A371) |
| **Componentes afectados** | `seller_helpers_page_widget.dart`, `seller_staff_service.dart`, `staff_helper_events` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Integration |
| **Dados necessários** | seller JWT, helper email, `batata_find_user_id_by_email` |
| **Validar BD** | `select invitation_status, active, permissions from seller_helpers where seller_id=$sid and helper_user_id=$hid` → pending |
| **Validar UI** | Card pendente na lista equipa; banner `HelperPendingInvitesBanner` no helper |
| **Risco de regressão** | Médio — onboarding equipa |
| **Dependências** | — |

---

## A371 — Helper aceita convite

| Campo | Valor |
|-------|-------|
| **ID** | A371 |
| **Nome** | Colaborador aceita convite pendente |
| **Pré-condições** | A370; helper logado; convite `pending` |
| **Passos** | 1. Helper abre banner ou `HelperInvitationPage` 2. Tocar Aceitar 3. Ver contexto loja |
| **Resultado esperado** | `invitation_status=accepted`, `active=true`; `SellerStaffContext` muda para loja assistida; `StaffActionLog` `helper_invitation_accepted` |
| **Componentes afectados** | `helper_invitation_page_widget.dart`, `SellerStaffContext.acceptInvitation`, `account_context_badge.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Integration |
| **Dados necessários** | `seller_helpers.id` pending |
| **Validar BD** | `invitation_status='accepted'`, `responded_at` not null |
| **Validar UI** | Badge «Loja assistida»; atalho «Acesso de colaborador» activo |
| **Risco de regressão** | Médio |
| **Dependências** | A370 |

---

## A372 — Helper live ops HLS + panel

| Campo | Valor |
|-------|-------|
| **ID** | A372 |
| **Nome** | Painel operacional helper sobre HLS (sem câmara) |
| **Pré-condições** | A371; live `status=live`; helper com `can_view_live_dashboard=true` |
| **Passos** | 1. Helper → Acesso colaborador → Directo activo 2. Abrir `HelperLiveOpsPage` 3. Ver vídeo + painel studio |
| **Resultado esperado** | `LiveHlsViewer` reproduz stream; `LiveVendorStudioPanel` visível; **sem** botão emitir/câmara; orientação portrait |
| **Componentes afectados** | `helper_live_ops_page_widget.dart`, `live_hls_viewer.dart`, `live_vendor_studio_panel.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | `live_id` activo, Mux HLS URL |
| **Validar BD** | `lives.status='live'`, `is_active=true` |
| **Validar UI** | Label «Modo colaborador»; painel catálogo/reservas; HLS a carregar |
| **Risco de regressão** | Alto — operação live delegada |
| **Dependências** | A371; A054 (publish seller) |

---

## A373 — Helper accept reserva permitido

| Campo | Valor |
|-------|-------|
| **ID** | A373 |
| **Nome** | Helper com `can_manage_reservations` aceita reserva |
| **Pré-condições** | A372; reserva `pending`; helper `can_manage_reservations=true` (default) |
| **Passos** | 1. Buyer reserva artigo 2. Helper no painel operações 3. Tocar Aceitar |
| **Resultado esperado** | Reserva `accepted`; KPI vendedor actualiza; comprador vê estado aceite; log `live_vendor_studio_logs` |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, `live_reservation_queue_service.dart`, `SellerStaffGate` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Bot |
| **Dados necessários** | `live_reservation_requests` pending, helper JWT |
| **Validar BD** | `status='accepted'`; `staff_action_log` ou studio log event |
| **Validar UI** | Botão Aceitar activo; card verde comprador (A081) |
| **Risco de regressão** | Crítico — delegação vendas |
| **Dependências** | A372; A081 |

---

## A374 — Helper **não** termina directo

| Campo | Valor |
|-------|-------|
| **ID** | A374 |
| **Nome** | `can_end_live=false` — sem CTA terminar |
| **Pré-condições** | Helper activo; permissão `can_end_live=false` (default helper) |
| **Passos** | 1. Helper no painel live ops 2. Procurar «Terminar directo» / encerrar 3. Tentar via menu se existir |
| **Resultado esperado** | CTA terminar **ausente** ou desactivado; live permanece `status=live`; seller owner ainda pode terminar |
| **Componentes afectados** | `helper_live_ops_page_widget.dart`, `SellerStaffPermissions.canEndLive`, studio panel guards |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | helper com default perms |
| **Validar BD** | `lives.status` inalterado após tentativa helper |
| **Validar UI** | Sem botão crítico terminar; snack se bypass UI |
| **Risco de regressão** | Alto — acção irreversível |
| **Dependências** | A372; A380 |

---

## A375 — canManageReservations false → bloqueado

| Campo | Valor |
|-------|-------|
| **ID** | A375 |
| **Nome** | Helper sem permissão reservas — aceitar bloqueado |
| **Pré-condições** | Helper `can_manage_reservations=false`; live activa; reserva pending |
| **Passos** | 1. Seller edita helper → desliga «Gerir reservas» 2. Helper refresh/reopen painel 3. Tentar Aceitar |
| **Resultado esperado** | `SellerStaffGate` / RPC `batata_staff_has_permission` bloqueia; botão Aceitar oculto ou `_DeniedPanel`; **sem** mudança BD reserva |
| **Componentes afectados** | `seller_staff_gate.dart`, `live_vendor_studio_panel.dart`, `batata_staff_has_permission` (SQL) |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Integration |
| **Dados necessários** | helper row permissions JSON sem `can_manage_reservations` |
| **Validar BD** | reserva permanece `pending` |
| **Validar UI** | Mensagem «Não tens permissão para: Gerir reservas» |
| **Risco de regressão** | Crítico — overlap A098 |
| **Dependências** | A373 (contraste); A098 |

---

## A376 — SellerStaffContext switch loja

| Campo | Valor |
|-------|-------|
| **ID** | A376 |
| **Nome** | Alternar entre loja própria e loja assistida |
| **Pré-condições** | User é seller **e** helper de ≥1 loja (multi-link) |
| **Passos** | 1. Perfil → badge contexto 2. «Modo pessoal» 3. «Loja X» 4. Ver `effectiveSellerId` em acções |
| **Resultado esperado** | `switchToOwnStore` / `switchToHelperSeller` actualizam permissões; prefs `batata_active_seller_staff_id_v1` persistem; KPI/encomendas filtram loja correcta |
| **Componentes afectados** | `SellerStaffContext`, `account_context_badge.dart`, `auth_util.dart` (`effectiveSellerId`) |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 `seller_helpers` accepted |
| **Validar BD** | `batata_staff_ping_active` ao mudar para helper |
| **Validar UI** | Label contexto muda; catálogo/encomendas da loja seleccionada |
| **Risco de regressão** | Alto — acções na loja errada |
| **Dependências** | A371 |

---

## A377 — Helper rejeita convite

| Campo | Valor |
|-------|-------|
| **ID** | A377 |
| **Nome** | Colaborador recusa convite pendente |
| **Pré-condições** | A370; convite `pending`; helper autenticado |
| **Passos** | 1. Helper abre `HelperInvitationPage` 2. Tocar Recusar 3. Confirmar se dialog |
| **Resultado esperado** | `invitation_status=rejected`, `active=false`; convite some do banner; seller vê estado recusado na equipa |
| **Componentes afectados** | `SellerStaffContext.rejectInvitation`, `helper_invitation_page_widget.dart`, `staff_helper_events` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | `seller_helpers.id` pending |
| **Validar BD** | `invitation_status='rejected'`; log `helper_invitation_rejected` |
| **Validar UI** | Banner pendente vazio; card seller «Recusado» |
| **Risco de regressão** | Baixo |
| **Dependências** | A370 |

---

## A378 — Seller revoga helper activo

| Campo | Valor |
|-------|-------|
| **ID** | A378 |
| **Nome** | Remover/desactivar colaborador aceite |
| **Pré-condições** | Helper `accepted` + `active=true`; seller owner na equipa |
| **Passos** | 1. Seller → Equipa 2. Editar helper → Desactivar ou Remover 3. Helper tenta reabrir painel live |
| **Resultado esperado** | `active=false` ou row removida; helper perde acesso imediato; `SellerStaffContext.refresh` sem link activo |
| **Componentes afectados** | `seller_helpers_page_widget.dart`, `SellerStaffRepository.removeHelper`, `helper_live_ops_page_widget.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | `seller_helpers` accepted |
| **Validar BD** | `active=false` ou ausência row; `staff_helper_events` revoke |
| **Validar UI** | Helper vê «Acesso restrito»; seller lista actualizada |
| **Risco de regressão** | Alto — segurança equipa |
| **Dependências** | A371 |

---

## A379 — canEditProducts false → catálogo bloqueado

| Campo | Valor |
|-------|-------|
| **ID** | A379 |
| **Nome** | Helper sem editar anúncios — catálogo live read-only |
| **Pré-condições** | Helper `can_edit_products=false`; live activa; itens no catálogo |
| **Passos** | 1. Helper abre painel catálogo live 2. Tentar editar preço/stock/título 3. Tentar adicionar item |
| **Resultado esperado** | Campos desactivados ou `SellerStaffGate` bloqueia; **sem** RPC `batata_update_live_item` bem-sucedido |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, `seller_staff_gate.dart`, `live_catalog_stock_service.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | helper perms sem `can_edit_products` |
| **Validar BD** | `live_items` inalterados após tentativa |
| **Validar UI** | Ícones edição ocultos; painel negado se rota directa |
| **Risco de regressão** | Médio — preço/stock indevido |
| **Dependências** | A372; A375 (padrão gate) |

---

## A380 — canEndLive false — guard UI e RPC

| Campo | Valor |
|-------|-------|
| **ID** | A380 |
| **Nome** | Dupla verificação terminar live (UI + servidor) |
| **Pré-condições** | Helper `can_end_live=false`; live activa |
| **Passos** | 1. Inspeccionar UI (A374) 2. (Opcional) forçar RPC end live com JWT helper |
| **Resultado esperado** | UI sem CTA; RPC servidor rejeita com erro permissão; live não `ended` |
| **Componentes afectados** | `SellerStaffPermissions.canEndLive`, edge/SQL end live, `helper_live_ops_page_widget.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | helper JWT, `live_id` |
| **Validar BD** | `lives.status='live'` |
| **Validar UI** | A374 confirmado |
| **Risco de regressão** | Crítico — bypass API |
| **Dependências** | A374 |

---

## A381 — Helper muda artigo «a mostrar»

| Campo | Valor |
|-------|-------|
| **ID** | A381 |
| **Nome** | `can_change_current_item` — spotlight no carrossel |
| **Pré-condições** | Helper `can_change_current_item=true`; ≥2 itens catálogo; live activa |
| **Passos** | 1. Helper selecciona outro item «a mostrar» 2. Buyer observa carrossel player |
| **Resultado esperado** | `live_items.is_current` ou equivalente actualiza; compradores vêem novo spotlight ≤4s |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, `live_feed` poll, player carrossel |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Manual |
| **Dados necessários** | 2+ `live_items`, buyer + helper sessions |
| **Validar BD** | current item flag na loja correcta |
| **Validar UI** | Card destacado muda no player |
| **Risco de regressão** | Médio |
| **Dependências** | A372 |

---

## A382 — Helper modera chat público

| Campo | Valor |
|-------|-------|
| **ID** | A382 |
| **Nome** | `can_manage_chat` — resposta/moderar no studio |
| **Pré-condições** | Helper `can_manage_chat=true`; chat público activo |
| **Passos** | 1. Buyer envia mensagem 2. Helper abre painel chat 3. Responde ou aplica acção moderar (se existir) |
| **Resultado esperado** | Mensagem helper visível no chat público com identidade loja; sem leak ERP |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, `live_room_service.dart`, `SellerStaffPermissions.canManageChat` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot |
| **Dados necessários** | `live_messages`, helper JWT |
| **Validar BD** | `live_messages` row helper/sistema |
| **Validar UI** | Chat player mostra resposta |
| **Risco de regressão** | Médio — Z54 username |
| **Dependências** | A372; A105 |

---

## A383 — canViewPayouts false → financeiro oculto

| Campo | Valor |
|-------|-------|
| **ID** | A383 |
| **Nome** | Helper sem ver saldo/wallet/pagamentos |
| **Pré-condições** | Helper `can_view_payouts=false`, `can_manage_payouts=false` |
| **Passos** | 1. Helper em modo loja assistida 2. Navegar Perfil → Wallet / Pagamentos / KPI financeiro |
| **Resultado esperado** | Secções wallet e payouts **ocultas** ou `SellerStaffDeniedPage`; **sem** valores saldo |
| **Componentes afectados** | `perfil_widget.dart`, `seller_staff_gate.dart`, wallet pages |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | helper default financial perms false |
| **Validar BD** | — (UI gate) |
| **Validar UI** | Links wallet ausentes; lock panel se deep link |
| **Risco de regressão** | Alto — dados financeiros sensíveis |
| **Dependências** | A376 |

---

## A384 — canManageHelpers false → equipa bloqueada

| Campo | Valor |
|-------|-------|
| **ID** | A384 |
| **Nome** | Helper não gere outros colaboradores |
| **Pré-condições** | Helper `can_manage_helpers=false` (default) |
| **Passos** | 1. Helper tenta abrir `SellerHelpersPage` 2. Tentar convidar/remover membro |
| **Resultado esperado** | Rota bloqueada ou lista read-only; **sem** novo `seller_helpers` row |
| **Componentes afectados** | `seller_helpers_page_widget.dart`, `SellerStaffPermissions.canManageHelpers` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | helper JWT |
| **Validar BD** | count `seller_helpers` inalterado |
| **Validar UI** | «Acesso restrito» |
| **Risco de regressão** | Médio — escalada privilégios |
| **Dependências** | A370 (contraste owner) |

---

## A385 — Convidar e-mail sem conta

| Campo | Valor |
|-------|-------|
| **ID** | A385 |
| **Nome** | Convite falha se utilizador não registado |
| **Pré-condições** | Seller na equipa; e-mail **sem** row `profiles` / RPC null |
| **Passos** | 1. Adicionar colaborador com e-mail inexistente 2. Confirmar |
| **Resultado esperado** | Snack «Não encontrámos conta… deve registar-se primeiro»; **sem** insert `seller_helpers` |
| **Componentes afectados** | `seller_helpers_page_widget.dart`, `batata_find_user_id_by_email` |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | email fictício |
| **Validar BD** | zero rows novo helper |
| **Validar UI** | Snack erro; form mantém-se |
| **Risco de regressão** | Baixo |
| **Dependências** | A370 |

---

## A386 — Convidar duplicado

| Campo | Valor |
|-------|-------|
| **ID** | A386 |
| **Nome** | Segundo convite mesmo helper bloqueado |
| **Pré-condições** | Já existe `seller_helpers` row (pending ou accepted) para par seller/helper |
| **Passos** | 1. Seller tenta convidar mesmo e-mail outra vez |
| **Resultado esperado** | Erro amigável ou no-op; **uma** row por par; log `staff.helper` duplicate |
| **Componentes afectados** | `seller_staff_service.dart` invite RPC, unique constraint SQL |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | existing `seller_helpers` |
| **Validar BD** | `count(*)=1` para seller_id+helper_user_id |
| **Validar UI** | Snack «já colaborador» ou similar |
| **Risco de regressão** | Baixo |
| **Dependências** | A370 |

---

## A387 — Deep link convite inválido

| Campo | Valor |
|-------|-------|
| **ID** | A387 |
| **Nome** | `helperLinkId` expirado ou de outro user |
| **Pré-condições** | Deep link `/helperInvitation?helperLinkId=…` com id inexistente ou `helper_user_id` ≠ current |
| **Passos** | 1. Abrir link na app 2. Ver estado página |
| **Resultado esperado** | Mensagem «convite não encontrado» ou redirect seguro; **sem** aceitar convite alheio |
| **Componentes afectados** | `helper_invitation_page_widget.dart`, `nav.dart` params |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Manual |
| **Dados necessários** | UUID inválido ou convite de outro helper |
| **Validar BD** | `invitation_status` inalterado |
| **Validar UI** | Empty state; sem botão Aceitar |
| **Risco de regressão** | Médio — segurança convite |
| **Dependências** | A371 |

---

## A388 — Permissões editadas reflectem sem re-login

| Campo | Valor |
|-------|-------|
| **ID** | A388 |
| **Nome** | Seller muda perms — helper vê gate após refresh |
| **Pré-condições** | Helper com sessão activa no painel; seller edita JSON permissions |
| **Passos** | 1. Seller desliga `can_manage_reservations` 2. Helper pull-to-refresh ou reabre painel (`refresh()`) 3. Tentar aceitar |
| **Resultado esperado** | Gate bloqueia após `SellerStaffContext.refresh`; sem necessidade logout/login |
| **Componentes afectados** | `SellerStaffContext.refresh`, `seller_helpers_page_widget.dart` edit |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 devices seller+helper |
| **Validar BD** | `permissions` JSON actualizado |
| **Validar UI** | Botão Aceitar desaparece ≤1 refresh |
| **Risco de regressão** | Alto — stale permissions |
| **Dependências** | A375; A376 |

---

## A389 — RPC `batata_staff_has_permission` server gate

| Campo | Valor |
|-------|-------|
| **ID** | A389 |
| **Nome** | Bypass UI não contorna servidor |
| **Pré-condições** | Helper `can_manage_reservations=false`; reserva pending |
| **Passos** | 1. Chamar directamente RPC accept reserva com JWT helper (curl/app instrumentado) 2. Comparar com `serverCan()` |
| **Resultado esperado** | RPC servidor retorna erro/false; reserva `pending`; `SellerStaffContext.serverCan` === false |
| **Componentes afectados** | `batata_staff_has_permission` (SQL), `live_reservation_queue_service.dart`, `SellerStaffContext.serverCan` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | helper JWT, reservation id |
| **Validar BD** | reserva inalterada |
| **Validar UI** | — (API) |
| **Risco de regressão** | Crítico — segurança |
| **Dependências** | A375; A098 |

---

## A390 — RPC timeout — retry UI

| Campo | Valor |
|-------|-------|
| **ID** | A390 |
| **Nome** | Timeout Supabase — snack retry sem crash |
| **Pré-condições** | Rede lenta simulada ou staging throttle; acção RPC (ex. reservar) |
| **Passos** | 1. Inject delay/timeout no RPC 2. Buyer reserva 3. Ver feedback UI |
| **Resultado esperado** | Snack/estado erro amigável; botão retry ou pull refresh; **sem** ANR; estado local não corrupto |
| **Componentes afectados** | `live_reservation_queue_service.dart`, error handlers player/studio |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | proxy delay ou fault injection |
| **Validar BD** | 0 ou 1 reserva (não duplicar silenciosamente) |
| **Validar UI** | Loading pára; mensagem retry |
| **Risco de regressão** | Médio |
| **Dependências** | A148 |

---

## A391 — Realtime disconnect reconnect

| Campo | Valor |
|-------|-------|
| **ID** | A391 |
| **Nome** | Queda realtime — reconexão automática |
| **Pré-condições** | Player ou studio com subscription `live_messages` / reservas activa |
| **Passos** | 1. Toggle avião 10s 2. Restaurar rede 3. Enviar reserva/chat |
| **Resultado esperado** | Canal reconecta; eventos pendentes via poll fallback; UI sincroniza ≤10s |
| **Componentes afectados** | Supabase realtime channels, `live_room_service.dart`, studio poll timers |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live activa, 1 device |
| **Validar BD** | — |
| **Validar UI** | Chat/reservas reaparecem sem restart app |
| **Risco de regressão** | Alto — operação live |
| **Dependências** | A416 |

---

## A392 — create-mux-live timeout

| Campo | Valor |
|-------|-------|
| **ID** | A392 |
| **Nome** | Edge Mux lenta — publish não fica zombie |
| **Pré-condições** | Seller inicia directo; edge `create-mux-live` ou `livekit-mux-publish` com delay |
| **Passos** | 1. Novo directo 2. Simular timeout edge 3. Ver estado live + UI |
| **Resultado esperado** | Erro claro ao seller; live `draft` ou cleanup orphan; **sem** card LIVE fantasma na home |
| **Componentes afectados** | `livekit-mux-publish` edge, `live_publish_cleanup.dart`, prep flow |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | staging edge fault |
| **Validar BD** | `lives.status` não `live` órfão sem stream |
| **Validar UI** | Retry ou voltar prep; sem spinner infinito |
| **Risco de regressão** | Alto — A061 orphan |
| **Dependências** | A050; A061 |

---

## A393 — Dois Maestro paralelos race live

| Campo | Valor |
|-------|-------|
| **ID** | A393 |
| **Nome** | Corrida CI — dois flows mesmo seller/live |
| **Pré-condições** | 2 instâncias Maestro; mesma conta seller; live `MAESTRO` partilhado (H07) |
| **Passos** | 1. Lançar `v2_seller_harness_accept` e buyer flow em paralelo 2. Observar aceites/stock |
| **Resultado esperado** | Sem double-accept inconsistente; stock ≥0; um flow não mata o outro (A063 guard) |
| **Componentes afectados** | Maestro flows, `live_reservation_queue_service.dart`, `live_publish_cleanup.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro (paralelo) |
| **Dados necessários** | H07 live tag, 2 emuladores |
| **Validar BD** | FIFO queue coerente; sem negative stock |
| **Validar UI** | Harness verde em ambos ou falha diagnóstica clara |
| **Risco de regressão** | Alto — CI flake |
| **Dependências** | A063; A398 |

---

## A394 — Emulador ANR login

| Campo | Valor |
|-------|-------|
| **ID** | A394 |
| **Nome** | Login Maestro sem Application Not Responding |
| **Pré-condições** | Emulador Android médio; cold start app |
| **Passos** | 1. Flow `launch_fleaber_login` + `login_buyer` 2. Medir tempo até home 3. Ver logcat ANR |
| **Resultado esperado** | Login <30s; **sem** ANR; `dismiss_before_login` ok |
| **Componentes afectados** | `.maestro/subflows/login_*.yaml`, `main.dart` init, `SellerStaffContext.refresh` |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | `.maestro/.env` credenciais teste |
| **Validar BD** | — |
| **Validar UI** | Home visível; sem dialog bloqueante |
| **Risco de regressão** | Médio — smoke gate |
| **Dependências** | — |

---

## A395 — Multi-buyer 5 reservas simultâneas

| Campo | Valor |
|-------|-------|
| **ID** | A395 |
| **Nome** | Stress 5 compradores reservam em paralelo |
| **Pré-condições** | Live activa; stock≥5 ou waitlist activa; 5 buyers bot |
| **Passos** | 1. Bot dispara 5 `create_reservation` simultâneos 2. Query fila 3. Seller vê KPI |
| **Resultado esperado** | 5 rows `pending` com `queue_position` único 1..5; sem deadlock; seller vê 5 cards |
| **Componentes afectados** | `live_reservation_queue_service.dart`, `batata_live_create_reservation`, studio KPI |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | 5 buyer JWTs, 1 `live_item_id` |
| **Validar BD** | `count(*)=5`; positions distintas; `batata_recompact` coerente (A421) |
| **Validar UI** | — (API-first) |
| **Risco de regressão** | Crítico — fila core |
| **Dependências** | A111; A419 |

---

## A396 — Multi-live seller 2 drafts

| Campo | Valor |
|-------|-------|
| **ID** | A396 |
| **Nome** | Seller com 2 lives draft — só uma activa |
| **Pré-condições** | Seller cria 2 preps draft sem publicar ambas |
| **Passos** | 1. Criar live A draft 2. Criar live B draft 3. Publicar A 4. Ver B |
| **Resultado esperado** | Apenas A `live`; B permanece `draft`; `findActiveLiveForSeller` retorna A |
| **Componentes afectados** | prep flow, `SellerStaffContext.findActiveLiveForSeller`, `lives` constraints |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | seller_id |
| **Validar BD** | `count(*) where status='live' and seller_id=$sid` ≤1 |
| **Validar UI** | Um card LIVE na home seller |
| **Risco de regressão** | Médio |
| **Dependências** | A050 |

---

## A397 — Device A live + Device B login fullSweep

| Campo | Valor |
|-------|-------|
| **ID** | A397 |
| **Nome** | Publish device A não morre com login fullSweep device B |
| **Pré-condições** | Device A seller em directo `MAESTRO`/teste; Device B mesmo seller login home |
| **Passos** | 1. A em broadcast 2. B login trigger `reconcileOnAppStart(fullSweep:true)` 3. A continua; buyer no player |
| **Resultado esperado** | Live A permanece `live`; `isBroadcastInProgress` / H07 protege; buyer stream OK |
| **Componentes afectados** | `live_publish_cleanup.dart`, `main.dart`, `home_live_feed_grid.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual (2 devices) |
| **Dados necessários** | 2 phones/emuladores, seller account |
| **Validar BD** | `lives.status='live'` após B login |
| **Validar UI** | A ainda emissão; buyer sem freeze |
| **Risco de regressão** | Crítico — A063/A069 |
| **Dependências** | A063; A054 |

---

## A398 — Bot seed + Maestro verify BD

| Campo | Valor |
|-------|-------|
| **ID** | A398 |
| **Nome** | H07 pipeline — bot prepara, Maestro valida |
| **Pré-condições** | Staging; bot cria live+reserva; Maestro harness accept |
| **Passos** | 1. `tool/` bot seed live MAESTRO 2. Maestro seller accept 3. Script SQL assert |
| **Resultado esperado** | Reserva `accepted`; logs studio; Maestro verde; BD match script |
| **Componentes afectados** | `tool/fleaber_regression_runner.dart`, `.maestro/flows/v2_seller_harness_accept.yaml` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot + Maestro (H07) |
| **Dados necessários** | staging creds, MAESTRO tag |
| **Validar BD** | `live_reservation_requests.status='accepted'` |
| **Validar UI** | Maestro asserts texto studio |
| **Risco de regressão** | Alto — CI backbone |
| **Dependências** | A393; A081 |

---

## A399 — Stripe 3DS / SCA

| Campo | Valor |
|-------|-------|
| **ID** | A399 |
| **Nome** | Checkout com autenticação forte Stripe |
| **Pré-condições** | Reserva payable; cartão teste 3DS (`4000…3220` ou equivalente test mode) |
| **Passos** | 1. Pagar saco/single 2. Completar challenge 3DS no browser 3. Resume app |
| **Resultado esperado** | `orders.status=pago`; reserva `converted`; context reconcile após 3DS |
| **Componentes afectados** | `fleaber_stripe_checkout_context.dart`, Stripe Checkout SCA |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | Stripe test 3DS card |
| **Validar BD** | converted + order pago |
| **Validar UI** | Browser 3DS → sucesso app |
| **Risco de regressão** | Crítico — pagamentos UE |
| **Dependências** | A205; A206 |

---

## A400 — Web C8B overlay qty dialog

| Campo | Valor |
|-------|-------|
| **ID** | A400 |
| **Nome** | Overlay web studio — dialog qty (C8B) |
| **Pré-condições** | Seller web/vendor studio C8B; reserva T1 `requested_qty` > stock |
| **Passos** | 1. Buyer Pagar com qty>stock 2. Ver overlay web seller 3. Comparar com app nativo A204 |
| **Resultado esperado** | Dialog qty urgente no overlay web; paridade copy com app; sem Stripe até resolvido |
| **Componentes afectados** | web vendor overlay C8B, `checkoutQtyExceedsAvailable` |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | T1 setup, browser seller |
| **Validar BD** | sem order pago |
| **Validar UI** | Dialog «Pedido total» visível web |
| **Risco de regressão** | Médio — paridade web/app |
| **Dependências** | A204 |

---

## A401 — JWT expirado — refresh silencioso

| Campo | Valor |
|-------|-------|
| **ID** | A401 |
| **Nome** | Token Supabase expira mid-session — auto-refresh |
| **Pré-condições** | Sessão activa no player; `expires_at` próximo (mock ou espera) |
| **Passos** | 1. Forçar refresh token (ou esperar TTL curto staging) 2. Reservar artigo 3. Ver sessão |
| **Resultado esperado** | `SupaFlow` refresh transparente; acção RPC sucesso; **sem** redirect login |
| **Componentes afectados** | `supabase_auth`, `auth_util.dart`, Supabase client refresh |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | JWT com TTL curto |
| **Validar BD** | reserva criada com user_id correcto |
| **Validar UI** | Sem tela login intermédia |
| **Risco de regressão** | Alto — sessões longas live |
| **Dependências** | A148 |

---

## A402 — Sessão revogada — logout forçado

| Campo | Valor |
|-------|-------|
| **ID** | A402 |
| **Nome** | Refresh falha — utilizador deslogado com mensagem |
| **Pré-condições** | Sessão invalidada no servidor (sign out all / delete refresh token) |
| **Passos** | 1. Invalidar sessão remotamente 2. User tenta acção RPC 3. Ver navegação |
| **Resultado esperado** | Redirect login; snack «sessão expirada»; **sem** crash; dados locais sensíveis limpos |
| **Componentes afectados** | auth manager, `main.dart` auth listener |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | user com sessão activa |
| **Validar BD** | — |
| **Validar UI** | Login screen |
| **Risco de regressão** | Médio |
| **Dependências** | A401 (contraste) |

---

## A403 — Buyer offline — reserva falha gracioso

| Campo | Valor |
|-------|-------|
| **ID** | A403 |
| **Nome** | Sem rede — reserva com feedback retry |
| **Pré-condições** | Buyer no player; avião mode ON |
| **Passos** | 1. Tocar Reservar 2. Ver erro 3. Restaurar rede 4. Retry |
| **Resultado esperado** | Snack offline; botão retry; 1 reserva após rede OK; **sem** ghost pending local |
| **Componentes afectados** | player reserve CTA, `live_reservation_queue_service.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live activa |
| **Validar BD** | 0 rows durante offline; 1 após retry |
| **Validar UI** | Estado erro + sucesso |
| **Risco de regressão** | Médio |
| **Dependências** | A390; A391 |

---

## A404 — Seller offline — accept em fila

| Campo | Valor |
|-------|-------|
| **ID** | A404 |
| **Nome** | Vendedor offline — aceitar não aplica silenciosamente |
| **Pré-condições** | Studio aberto; rede cortada no accept |
| **Passos** | 1. Cortar rede 2. Tocar Aceitar 3. Restaurar rede |
| **Resultado esperado** | Erro visível ou retry automático; estado final `accepted` **uma vez**; sem double-accept |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, accept RPC |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | pending reserva |
| **Validar BD** | `status='accepted'` único |
| **Validar UI** | Loading → erro ou sucesso claro |
| **Risco de regressão** | Alto |
| **Dependências** | A081; A415 |

---

## A405 — App background 5min — player recover

| Campo | Valor |
|-------|-------|
| **ID** | A405 |
| **Nome** | Retomar app após background prolongado |
| **Pré-condições** | Buyer no player live; app em background 5+ min |
| **Passos** | 1. Home OS 5min 2. Reabrir app 3. Ver vídeo + chat + reservar |
| **Resultado esperado** | HLS reconecta; realtime/poll activo; saco actualiza; **sem** tela preta permanente |
| **Componentes afectados** | `fleaber_live_player_widget.dart`, `LiveHlsViewer`, app lifecycle |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live longa, 1 device |
| **Validar BD** | — |
| **Validar UI** | Stream + chat funcionais ≤15s |
| **Risco de regressão** | Alto — UX live |
| **Dependências** | A391; A145 |

---

## A406 — Double-tap reserva mesmo buyer

| Campo | Valor |
|-------|-------|
| **ID** | A406 |
| **Nome** | Duplo tap Reservar — dedupe ou increment qty |
| **Pré-condições** | Item com stock; buyer sem reserva prévia |
| **Passos** | 1. Double-tap rápido «Reservar» 2. Query BD |
| **Resultado esperado** | **1** row pending OU increment `requested_qty` (R6); **não** 2 rows duplicadas mesma ref |
| **Componentes afectados** | reserve button debounce, `batata_live_create_reservation`, R6 merge |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot + Maestro |
| **Dados necessários** | buyer, live_item |
| **Validar BD** | `count(*)<=1` por buyer+item pending |
| **Validar UI** | Um card no saco |
| **Risco de regressão** | Médio — R6 |
| **Dependências** | A149; A197 |

---

## A407 — Flood reservas rate limit

| Campo | Valor |
|-------|-------|
| **ID** | A407 |
| **Nome** | 10+ reservas rápidas mesmo buyer — throttling |
| **Pré-condições** | Buyer bot ou script; live activa |
| **Passos** | 1. Disparar 15 create_reservation em 3s 2. Ver respostas |
| **Resultado esperado** | Erro 429 ou rejeição após limite; BD com ≤N rows razoável; seller KPI não explode |
| **Componentes afectados** | RPC rate limit SQL, `live_reservation_queue_service.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | 1 buyer JWT |
| **Validar BD** | count rows bounded |
| **Validar UI** | — |
| **Risco de regressão** | Médio — abuse |
| **Dependências** | A395 |

---

## A408 — Chat flood rate limit

| Campo | Valor |
|-------|-------|
| **ID** | A408 |
| **Nome** | Spam chat público — throttle |
| **Pré-condições** | Buyer no chat; live activa |
| **Passos** | 1. Enviar 20 mensagens em 5s 2. Ver UI + BD |
| **Resultado esperado** | Bloqueio temporário ou drop; snack «demasiado rápido»; chat legível |
| **Componentes afectados** | `live_room_service.dart`, chat send guard |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | buyer JWT |
| **Validar BD** | `live_messages` count ≤ limite janela |
| **Validar UI** | Input desactivado brevemente |
| **Risco de regressão** | Baixo |
| **Dependências** | A280 |

---

## A409 — Edge 500 create-payment-intent

| Campo | Valor |
|-------|-------|
| **ID** | A409 |
| **Nome** | Falha edge pagamento — UI retry sem perder saco |
| **Pré-condições** | Reserva payable; simular 500 na edge `create-payment-intent` |
| **Passos** | 1. Pagar 2. Edge falha 3. Retry após fix |
| **Resultado esperado** | Snack erro; reserva intacta `accepted`; retry abre Stripe; **sem** order fantasma |
| **Componentes afectados** | `create-payment-intent` edge, `LiveInStreamCheckout` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | fault injection staging |
| **Validar BD** | sem order `pago` até success |
| **Validar UI** | Loading pára; CTA Pagar reactivo |
| **Risco de regressão** | Alto — dinheiro |
| **Dependências** | A205 |

---

## A410 — Reconcile rede down — prefs preservadas

| Campo | Valor |
|-------|-------|
| **ID** | A410 |
| **Nome** | Pós-Stripe sem rede — context pending sobrevive |
| **Pré-condições** | Checkout Stripe success no browser; app offline no resume |
| **Passos** | 1. Pagar Stripe 2. Cortar rede antes resume 3. Restaurar rede 4. `tryResumeOnAppResumed` |
| **Resultado esperado** | `FleaberStripeCheckoutContext` prefs intactas; reconcile corre quando online; converted |
| **Componentes afectados** | `fleaber_stripe_checkout_context.dart`, SharedPreferences |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | Stripe test, 1 device |
| **Validar BD** | order pago após reconnect |
| **Validar UI** | Snack «a sincronizar…» opcional |
| **Risco de regressão** | Crítico — A206 |
| **Dependências** | A206; A229 |

---

## A411 — RLS helper wrong seller — RPC 403

| Campo | Valor |
|-------|-------|
| **ID** | A411 |
| **Nome** | Colaborador não acede dados de outra loja |
| **Pré-condições** | Helper loja A; tenta RPC/query com `seller_id` loja B |
| **Passos** | 1. Chamar accept/update com seller_id alheio 2. Ver erro |
| **Resultado esperado** | RLS ou RPC rejeita; **sem** leak rows loja B |
| **Componentes afectados** | RLS `seller_helpers`, `batata_staff_has_permission`, reservation RLS |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 2 sellers, 1 helper A only |
| **Validar BD** | zero mutações loja B |
| **Validar UI** | — |
| **Risco de regressão** | Crítico — multi-tenant |
| **Dependências** | A389; A376 |

---

## A412 — Live ended mid-checkout — bloqueio

| Campo | Valor |
|-------|-------|
| **ID** | A412 |
| **Nome** | Directo termina durante checkout — Pagar bloqueado |
| **Pré-condições** | Buyer com saco payable aberto; seller termina live |
| **Passos** | 1. Abrir checkout sheet 2. Seller end live 3. Buyer confirma Pagar |
| **Resultado esperado** | Erro ou CTA desactivado; edge rejeita se `status=ended`; **sem** cobrança órfã |
| **Componentes afectados** | `live_bag_checkout_sheet.dart`, `create-payment-intent`, live status guard |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 sessions buyer+seller |
| **Validar BD** | sem novo order pago pós-ended |
| **Validar UI** | Snack «directo terminou» |
| **Risco de regressão** | Alto |
| **Dependências** | A057; A205 |

---

## A413 — Kill app seller mid-publish — orphan cleanup

| Campo | Valor |
|-------|-------|
| **ID** | A413 |
| **Nome** | Force-close durante broadcast — cleanup no próximo start |
| **Pré-condições** | Seller em directo; prefs `batata_active_broadcast_live_id_v1` set |
| **Passos** | 1. Publicar live 2. Force-kill app 3. Reabrir app (sem fullSweep kill MAESTRO) |
| **Resultado esperado** | `reconcileOnAppStart` fecha orphan **ou** retoma se `isBroadcastInProgress`; home sem card fantasma |
| **Componentes afectados** | `live_publish_cleanup.dart`, `registerActiveBroadcast` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | seller publish session |
| **Validar BD** | `lives.status` ended ou live coerente |
| **Validar UI** | Home feed correcto |
| **Risco de regressão** | Alto — A061 |
| **Dependências** | A061; A397 |

---

## A414 — Buyer troca conta mid-bag

| Campo | Valor |
|-------|-------|
| **ID** | A414 |
| **Nome** | Logout/login outro buyer — saco isolado |
| **Pré-condições** | Buyer A com reservas pending; logout |
| **Passos** | 1. Buyer A reserva 2. Logout 3. Login Buyer B 4. Abrir mesmo live saco |
| **Resultado esperado** | Saco B vazio ou só rows B; **sem** ver reservas A; Stripe context limpo |
| **Componentes afectados** | `live_bag_sheet.dart`, auth logout cleanup, stripe context |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 buyer accounts |
| **Validar BD** | queries filtram `buyer_id` |
| **Validar UI** | Saco correcto por conta |
| **Risco de regressão** | Alto — privacidade |
| **Dependências** | A190; A229 |

---

## A415 — Race accept mesma reserva (2 operadores)

| Campo | Valor |
|-------|-------|
| **ID** | A415 |
| **Nome** | Seller + helper aceitam simultaneamente — idempotente |
| **Pré-condições** | 1 reserva pending; seller owner + helper ambos com `can_manage_reservations` |
| **Passos** | 1. Disparar accept RPC quase simultâneo nos 2 devices 2. Query estado |
| **Resultado esperado** | `accepted` uma vez; stock decrementa uma vez; segundo accept no-op ou erro seguro |
| **Componentes afectados** | accept RPC SQL lock, `live_reservation_queue_service.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot + Integration |
| **Dados necessários** | seller + helper JWT, 1 reservation |
| **Validar BD** | `status='accepted'`; stock delta 1× |
| **Validar UI** | Um card aceite |
| **Risco de regressão** | Crítico — A112 overlap |
| **Dependências** | A373; A112 |

---

## A416 — Realtime stale — poll fallback ≤4s

| Campo | Valor |
|-------|-------|
| **ID** | A416 |
| **Nome** | Subscription morta — poll corrige UI |
| **Pré-condições** | Player com poll 2–4s; realtime desligado (bug ou rede) |
| **Passos** | 1. Simular realtime off 2. Outro user reserva 3. Observar buyer UI |
| **Resultado esperado** | Stock/chat actualiza via poll em ≤4s; sem divergência permanente |
| **Componentes afectados** | player poll timer, `live_feed`, A348 pattern |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Manual |
| **Dados necessários** | 2 clients |
| **Validar BD** | RPC stock match UI |
| **Validar UI** | Números iguais seller/buyer |
| **Risco de regressão** | Alto — A348 |
| **Dependências** | A391; A348 |

---

## A417 — Low memory — player estável

| Campo | Valor |
|-------|-------|
| **ID** | A417 |
| **Nome** | Pressão memória — player não ANR/crash |
| **Pré-condições** | Emulador memória limitada; live HLS 10+ min |
| **Passos** | 1. Abrir player 2. Background/foreground repetido 3. Monitor logcat |
| **Resultado esperado** | **Sem** crash OOM; **sem** ANR; HLS recover ou erro gracioso |
| **Componentes afectados** | `LiveHlsViewer`, `fleaber_live_player_widget.dart`, image cache |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | emulador 2GB RAM |
| **Validar BD** | — |
| **Validar UI** | App responsiva |
| **Risco de regressão** | Médio |
| **Dependências** | A394; A405 |

---

## A418 — Deep link live_id inválido

| Campo | Valor |
|-------|-------|
| **ID** | A418 |
| **Nome** | Navegação para live inexistente |
| **Pré-condições** | Deep link `live_id` UUID inválido ou `ended` há >30d apagado |
| **Passos** | 1. Abrir link app/universal 2. Ver ecrã |
| **Resultado esperado** | Erro amigável «Directo não encontrado»; redirect home; **sem** crash |
| **Componentes afectados** | `nav.dart`, `fleaber_live_player_widget.dart`, deep link handler |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | UUID random |
| **Validar BD** | — |
| **Validar UI** | Empty/error state |
| **Risco de regressão** | Baixo |
| **Dependências** | A145 |

---

## A419 — Multi-buyer stock 1 — FIFO um aceite

| Campo | Valor |
|-------|-------|
| **ID** | A419 |
| **Nome** | Stock 1, N buyers — só posição #1 aceitável sem overbook |
| **Pré-condições** | `available_qty=1`; 3 buyers reservam (A395 subset) |
| **Passos** | 1. Bot: 3 pending queue 1..3 2. Seller aceita #1 3. Tentar aceitar #2 |
| **Resultado esperado** | #1 `accepted`; #2 waitlist ou dialog over-stock; stock 0; **sem** double-sell |
| **Componentes afectados** | FIFO queue, accept guards, R30 stock |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | stock 1, 3 buyers |
| **Validar BD** | `available_qty=0`; 1 accepted max |
| **Validar UI** | #2 «Espera» (A192) |
| **Risco de regressão** | Crítico — R30 |
| **Dependências** | A395; A429; A111 |

---

## A420 — live_vendor_studio_logs cobertura eventos

| Campo | Valor |
|-------|-------|
| **ID** | A420 |
| **Nome** | Auditoria studio — eventos críticos logados |
| **Pré-condições** | Live activa; acções seller (accept, price, checkout gate) |
| **Passos** | 1. Aceitar reserva 2. Definir preço 3. Trigger qty gate 4. Query logs |
| **Resultado esperado** | Rows `live_vendor_studio_logs` com `event_type` esperados (`reservation.accept`, `checkout.pay_qty_gate`, etc.) |
| **Componentes afectados** | `FleaberLogger.instance.logVendorStudio`, `live_vendor_studio_logs` table |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | `live_id`, seller actions |
| **Validar BD** | `select event_type, payload from live_vendor_studio_logs where live_id=$id order by created_at` |
| **Validar UI** | — |
| **Risco de regressão** | Médio — debug produção |
| **Dependências** | A109; A081 |

---

## A421 — batata_recompact ordem FIFO

| Campo | Valor |
|-------|-------|
| **ID** | A421 |
| **Nome** | Recompact fila após remove/cancel |
| **Pré-condições** | ≥3 reservas pending com positions 1,2,3 |
| **Passos** | 1. Remover/cancelar position #2 2. RPC `batata_recompact` ou trigger 3. Query positions |
| **Resultado esperado** | Positions contínuas 1..N sem buracos; ordem FIFO temporal preservada |
| **Componentes afectados** | `batata_recompact` SQL, `live_reservation_queue_service.dart`, A097 |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 3+ pending rows |
| **Validar BD** | `queue_position` sequencial 1..n |
| **Validar UI** | Chips #N correctos buyer/seller |
| **Risco de regressão** | Alto — A192 chips |
| **Dependências** | A097; A230 |

---

## A422 — live_feed refresh tick cancelar (Z50)

| Campo | Valor |
|-------|-------|
| **ID** | A422 |
| **Nome** | Timer poll cancela ao sair do ecrã |
| **Pré-condições** | Home ou player com `live_feed` poll activo |
| **Passos** | 1. Abrir home live grid 2. Navegar fora 3. Inspeccionar timers (debug) |
| **Resultado esperado** | Poll cancelado no `dispose`; **sem** leak timer; **sem** requests após sair |
| **Componentes afectados** | `home_live_feed_grid.dart`, `marketplace_feed_refresh.dart`, Z50 |
| **Prioridade** | P3 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Unit |
| **Dados necessários** | debug logging |
| **Validar BD** | — |
| **Validar UI** | — |
| **Risco de regressão** | Baixo — bateria |
| **Dependências** | — |

---

## A423 — KPI pagamentos antes de totais (R5 fix)

| Campo | Valor |
|-------|-------|
| **ID** | A423 |
| **Nome** | Painel pagamentos lista antes de totais agregados |
| **Pré-condições** | Live com vendas `converted`; secção pagamentos studio |
| **Passos** | 1. Abrir painel Pagamentos 2. Ver ordem render 3. Comparar com R5 spec |
| **Resultado esperado** | Lista linhas convertidas **antes** de bloco totais/KPI; totais correctos |
| **Componentes afectados** | `live_vendor_studio_panel.dart` payments section, R5 ordering |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | ≥1 converted |
| **Validar BD** | orders converted match lista |
| **Validar UI** | Lista acima; totais abaixo |
| **Risco de regressão** | Médio — R5 KPI |
| **Dependências** | A107; A206 |

---

## A424 — Security: stripe convert auth (C1 auditoria)

| Campo | Valor |
|-------|-------|
| **ID** | A424 |
| **Nome** | Apenas buyer da order pode reconcile/convert |
| **Pré-condições** | Order `reserva_pendente`; JWT buyer B ≠ buyer da order |
| **Passos** | 1. Buyer B chama `batata_live_reconcile_stripe_order` ou edge settle com order alheia |
| **Resultado esperado** | 403/erro; order inalterada; **sem** converted cross-user |
| **Componentes afectados** | `batata_live_reconcile_stripe_order`, `create-payment-intent`, RLS orders |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | order buyer A, JWT buyer B |
| **Validar BD** | reserva não converted por B |
| **Validar UI** | — |
| **Risco de regressão** | Crítico — C1 auditoria |
| **Dependências** | A209 |

---

## A425 — live_messages RLS público vs privado

| Campo | Valor |
|-------|-------|
| **ID** | A425 |
| **Nome** | RLS impede leak mensagens privadas no chat público |
| **Pré-condições** | Mensagens `kind=private` ou thread privada; buyer não participante |
| **Passos** | 1. Seller envia privado a buyer X 2. Buyer Y query `live_messages` / UI chat |
| **Resultado esperado** | Y **não** vê msgs privadas; RLS filtra; público só `kind` permitidos |
| **Componentes afectados** | `live_messages` RLS policies, `live_private_chat` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 2 buyers, 1 seller, private thread |
| **Validar BD** | `select` como Y retorna 0 private rows |
| **Validar UI** | Chat Y limpo |
| **Risco de regressão** | Alto — privacidade |
| **Dependências** | A426; A100 |

---

## A426 — live_private_chat batata

| Campo | Valor |
|-------|-------|
| **ID** | A426 |
| **Nome** | Modo chat privado seller↔buyer no studio |
| **Pré-condições** | Live activa; seller toggle private chat (A100) |
| **Passos** | 1. Buyer envia pergunta 2. Seller responde em thread privada 3. Ver público |
| **Resultado esperado** | Thread privada persistida; badge unread (A101); **não** duplica no público |
| **Componentes afectados** | `live_private_chat` SQL/RPC, `live_vendor_studio_panel.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live_id, buyer_id |
| **Validar BD** | private messages rows |
| **Validar UI** | Modo privado + badge |
| **Risco de regressão** | Médio |
| **Dependências** | A100; A425 |

---

## A427 — livekit egress cleanup cron

| Campo | Valor |
|-------|-------|
| **ID** | A427 |
| **Nome** | Egress órfão LiveKit — job cleanup |
| **Pré-condições** | Publish interrompido sem `finalizeEnded`; egress activo no LiveKit |
| **Passos** | 1. Simular kill mid-egress 2. Executar cron/cleanup 3. Ver LiveKit + BD |
| **Resultado esperado** | Egress terminado; sem custo leak; `lives` coerente ended |
| **Componentes afectados** | `livekit-mux-publish` edge, egress cleanup cron, `live_publish_cleanup.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | staging LiveKit API |
| **Validar BD** | live ended; mux stream inactive |
| **Validar UI** | — |
| **Risco de regressão** | Médio — custos infra |
| **Dependências** | A061; A069 |

---

## A428 — mux asset card home sem playback

| Campo | Valor |
|-------|-------|
| **ID** | A428 |
| **Nome** | Card gravado home — thumbnail sem autoplay |
| **Pré-condições** | Live `ended` com `mux_asset_id`; card na home feed |
| **Passos** | 1. Scroll home 2. Ver card VOD 3. Confirmar sem player inline |
| **Resultado esperado** | Thumbnail estática/poster; **sem** HLS autoplay no feed; tap abre replay |
| **Componentes afectados** | `home_live_feed_grid.dart`, mux asset card, A295 replay entry |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | ended live com asset |
| **Validar BD** | `mux_asset_id` not null |
| **Validar UI** | Sem vídeo a tocar no scroll |
| **Risco de regressão** | Médio — performance/bateria |
| **Dependências** | A295; A310 |

---

## A429 — Regressão R30 stock pós-aceite

| Campo | Valor |
|-------|-------|
| **ID** | A429 |
| **Nome** | `available_qty` decrementa exactamente 1× por aceite |
| **Pré-condições** | Item stock 3; reserva qty 1 pending |
| **Passos** | 1. Aceitar 2. Query `live_items.available_qty` 3. Repetir até stock 0 |
| **Resultado esperado** | Cada aceite qty1 decrementa 1; em stock 0 próximo pending → waitlist; **sem** negativo |
| **Componentes afectados** | accept RPC stock, `live_catalog_stock_service.dart`, R30 |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | live_item stock conhecido |
| **Validar BD** | `available_qty` nunca <0; delta = sum accepted qty |
| **Validar UI** | Badge ESGOTADO só quando real |
| **Risco de regressão** | Crítico — R30 histórico |
| **Dependências** | A081; A419; A341 |

---

## Apêndice A — Resumo A370–A429

| Bloco | IDs | Foco |
|-------|-----|------|
| Helpers core | A370–A376 | Convite, aceite, painel HLS, accept, end-live guard, perms, switch loja |
| Helpers extendido | A377–A389 | Reject, revoke, gates catálogo/financeiro/chat, duplicados, deep link, server RPC |
| Erros / rede | A390–A405 | Timeout, realtime, Mux, Maestro race, multi-buyer, fullSweep, 3DS, web C8B, JWT, offline |
| Stress / race | A406–A419 | Double-tap, flood, edge 500, reconcile offline, RLS, ended checkout, orphan, multi-account, accept race, poll, memory, deep link, FIFO stock |
| Sync / arquitectura | A420–A429 | Studio logs, recompact, Z50 poll, R5 KPI, stripe auth C1, messages RLS, private chat, egress, mux card, R30 |

**Total fichas:** 60 (A370–A429).

### Temas transversais (sem ID próprio — cobertos nas fichas acima)

| Tema | Fichas principais |
|------|-------------------|
| Permissões client vs servidor | A375, A389, A411 |
| Delegação operação live | A372–A373, A381–A382, A415 |
| Equipa lifecycle | A370–A371, A377–A378, A385–A387 |
| CI / Maestro / H07 | A393, A394, A397, A398 |
| Multi-comprador / FIFO | A395, A419, A421 |
| Recuperação rede/sessão | A390–A391, A401–A404, A410, A416 |
| Segurança pagamentos / RLS | A399, A409, A424, A425 |
| Cleanup / orphan | A392, A413, A427 |
| Stock integrity | A419, A429 |

---

## Apêndice B — P0 desta faixa (13)

| ID | Nome curto |
|----|------------|
| A373 | Helper accept reserva |
| A375 | canManageReservations bloqueado |
| A389 | RPC server permission gate |
| A395 | Multi-buyer 5 reservas |
| A397 | fullSweep não mata publish A |
| A398 | Bot seed + Maestro BD |
| A399 | Stripe 3DS / SCA |
| A411 | RLS helper wrong seller |
| A415 | Race accept idempotente |
| A419 | FIFO stock 1 multi-buyer |
| A423 | KPI pagamentos ordem R5 |
| A424 | Stripe convert auth C1 |
| A429 | R30 stock pós-aceite |

---

## Apêndice C — Top 10 a automatizar primeiro

| # | ID | Porquê | Tipo |
|---|-----|--------|------|
| 1 | A389 | Server permission gate — segurança delegação | Integration |
| 2 | A424 | C1 stripe convert auth — fraude cross-user | Integration |
| 3 | A395 | Multi-buyer stress — fila core | Bot |
| 4 | A419 | FIFO stock 1 — R30 overbook | Bot |
| 5 | A429 | Stock pós-aceite — regressão R30 | Integration |
| 6 | A398 | H07 CI backbone bot+Maestro | Bot+Maestro |
| 7 | A415 | Race accept seller+helper | Integration |
| 8 | A421 | Recompact FIFO — chips posição | Integration |
| 9 | A411 | RLS multi-tenant helper | Integration |
| 10 | A377 | Reject invite — lifecycle equipa | Integration |

---

## Apêndice D — Classificação por tipo (faixa completa)

| Tipo | IDs |
|------|-----|
| **Unit** | A422 (parcial) |
| **Integration** | A370, A371, A377, A378, A380, A385, A386, A389, A392, A396, A401, A402, A407, A409, A411, A413, A415, A419, A420, A421, A424, A425, A427, A429 |
| **Bot** | A373, A382, A395, A406, A407, A408, A416, A419 |
| **Maestro** | A393, A394, A387, A418, A398 (parcial) |
| **Manual** | A372, A374, A375, A376, A379, A383, A384, A388, A390, A391, A397, A399, A400, A403, A404, A405, A410, A412, A414, A417, A423, A426, A428 |
| **Híbrido** | A370 (Integration+Manual), A398 (Bot+Maestro), A373 (Manual+Bot), A378 (Integration+Manual), A409 (Integration+Manual), A401 (Integration), A415 (Bot+Integration), A429 (Integration+Manual) |

---

## Apêndice E — Riscos críticos (levantamento)

1. **Delegação sem server gate (A375 + A389):** UI `SellerStaffGate` bypassed via RPC directo — aceite indevido por helper revogado ou sem perms.
2. **fullSweep mata publish (A397):** login device B fecha live device A — regressão A063; smoke Maestro vermelho.
3. **Multi-buyer race (A395 + A415 + A419):** double-accept ou stock negativo — overlap R30/A112.
4. **Stripe auth cross-user (A424):** buyer B converte order buyer A — C1 auditoria; dinheiro/desvio encomenda.
5. **Reconcile offline (A410):** prefs perdidas → pagamento sem `converted` — suporte manual (#7).
6. **JWT/sessão (A401–A402):** refresh falha em live longa → logout mid-checkout.
7. **Helper wrong tenant (A411):** RLS leak — dados loja B visíveis a helper loja A.
8. **Ended mid-checkout (A412):** cobrança após `status=ended` — order órfã.
9. **R30 stock (A429):** `available_qty` não decrementa ou duplo decrement — ESGOTADO falso (A341).
10. **Egress orphan (A427 + A392):** custos Mux/LiveKit e cards LIVE fantasmas (A061).

---

*Fim A370–A429. Próxima faixa pendente: A430–A439 (sync extendido) ou consolidação runner.*
