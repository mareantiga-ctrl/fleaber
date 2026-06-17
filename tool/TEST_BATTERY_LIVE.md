# Fleaber - Estado da bateria UX+BD

Actualizado: **2026-06-16 22:06:58** | Ultima corrida: **20260616_215118**

Regra: **PASS** exige UX Maestro nos emuladores (quando aplicavel) **e** BD. BD sozinho nao conta.

| ID | Fase | Camada | Teste | Esperado | Estado | Motivo falha / nota |
|----|------|--------|-------|----------|--------|---------------------|
| T01 | 1 | BD | Unit tests Flutter (raffle, chat, lineage) | Todos os testes unitarios PASS no servidor local | **PASS** | -LogPath |
| T02 | 1 | BD | Live ops staging V0 (RPC/BD) | Checks Doc #3/#4/#6/#7 na BD staging PASS | **PASS** | -LogPath |
| T03 | 1 | BD | Integracao stock A3 | Qty/stock coerente na BD apos cenario stock | **PASS** | -LogPath |
| T04 | 1 | BD | Integracao A3/R32 qty | Alinhamento qty reservas/vendido na BD | **PASS** | -LogPath |
| T05 | 1 | BD | Integracao cross-pool A340 | Cross-pool RR1 PASS na BD | **PASS** | -LogPath |
| T06 | 1 | BD | Integracao linhagem A005 | logical_item_lineage PASS na BD | **PASS** | -LogPath |
| T07a | 1 | UX | Seller harness: Aceitar reserva pending | emulator-5554: login + studio + Aceitar visivel; prints cs01 seller | **PASS** | -LogPath |
| T07b | 1 | UX | Seller +Stock no harness | emulator-5554: doc_03 stock sem red screen; catalogo actualizado | **PASS** | -LogPath |
| T07c | 1 | UX | Buyer player + rifa + saco | emulator-5556: login, player, saco; prints cs10 buyer | **PASS** | -LogPath |
| T08a | 1 | BD | Doc APK V0 BD | live_ops_staging_check dentro de doc_apk PASS | **PASS** | -UxNote: |
| T08b | 1 | UX | Doc #4 APK cancelar saco | emulator-5556: saco -> Gerir reservas -> Cancelar; prints cs05 | **PASS** | -LogPath |
| T08c | 1 | UX | Doc #6 APK saco Pagar | emulator-5556: saco mostra botao Pagar; print cs09 | **PASS** | -LogPath |
| T08d | 1 | UX | Doc #3 APK adicionar stock | emulator-5554: +Stock no catalogo harness; prints cs02 | **PASS** | -LogPath |
| T08e | 1 | UX | Doc #7 Stripe EUR | SKIP manual (browser real) | **SKIP** | Stripe manual |
| T09 | 1 | UX | Seller stock UI (bateria isolada) | emulator-5554: doc_03 apos open studio PASS | **PASS** | -LogPath |
| T10 | 1 | UX | Pull logs maestro_studio | Log pull do seller sem erro | **PASS** | -LogPath |
| T11 | 2 | UX+BD | Reserva pending -> Aceitar | Seller Aceitar + buyer player; BD verify_accepted; UX ambos PASS | **PASS** | seller=True buyer=True UX nav |
| T12 | 2 | UX+BD | Adicionar stock (+1) | Seller +Stock; BD stock; print catalogo | **PASS** | -LogPath |
| T13 | 2 | UX+BD | A3 quick edit qty | Seller+buyer carrossel; BD a3_r32_qty_alignment | **PASS_COM_AVISO** | -LogPath |
| T14 | 2 | UX+BD | R32 repor stock | Vendido + restock; seller+buyer prints | **PASS_COM_AVISO** | -LogPath |
| T15 | 2 | UX+BD | Cancelar saco | Buyer cancela; seller cancelados; BD cancel | **PASS_COM_AVISO** | -LogPath |
| T16 | 2 | UX+BD | Marcar vendido | Seller vendido + buyer card; BD stock | **PASS_COM_AVISO** | seller=True buyer=True |
| T17 | 2 | BD | Cross-pool | SKIP UX (bd_only); BD cross_pool_rr1 | **PASS** | BD cross_pool_rr1 OK (igual T05/CS07); sem UI Maestro |
| T18 | 2 | UX+BD | Linhagem prep -> live | Home->Novo Direto->Artigos do directo; BD lineage | **PASS** | -LogPath |
| T19 | 2 | UX+BD | Saco Pagar | Buyer saco Pagar visivel; BD bag_edge | **PASS** | -LogPath |
| T20 | 2 | UX+BD | Rifa + saco | Buyer rifa+saco; BD verify_raffle_join | **PASS** | buyer rifa+saco OK; BD verify_raffle_join fix |
| T21 | 2 | UX | Stripe Doc #7 | SKIP manual | **SKIP** | -UxNote:USB/browser real obrigatÃƒÆ’Ã‚Â³rio |

## Legenda
- **PASS** - auditoria Cursor OK (Maestro + evidÃªncia + BD quando aplicÃ¡vel)
- **PASS_COM_AVISO** - fluxo OK com avisos UX/dados menores
- **PASS_COM_AVISO_DEEPLINK** - Maestro OK mas navegaÃ§Ã£o via deep link (nÃ£o valida UX real)
- **PENDING** - ainda nao corrido nesta sessao
- **RUNNING** - em curso
- **SKIP** - manual ou nao automatizado

Dados: tool/test_battery_registry.json | logs: tool/logs/

