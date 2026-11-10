# Fleaber Seller Studio — Extensão Chrome (Facebook Live)

**v1.7.29** — **Produção**. Contrato Face: `quero T10` / `quero 5 T10`; `cancela T10` = todas as unidades; bare REF = chat.

Rollback staging: copiar `studio_config.staging.js` → `studio_config.js` e apontar `background.js` / `popup.js` ao URL staging.

## Instalar / actualizar

1. `chrome://extensions` → Modo de programador  
2. **Recarregar** `tool/fleaber_ps_extension` (aceitar novos host_permissions se o Chrome pedir)  
3. Ícone → janela Seller Studio — label deve mostrar **`v1.7.29 (production)`**  
4. Login vendedor = conta **produção** (não staging)

## Painéis

| Painel | Conteúdo |
|--------|----------|
| Live | Face compacto · Fleaber hero (Mux) · KPIs · produtos · fila · alertas · estado limpo sem live activa |
| Produtos | Catálogo Hub + stock/fila FOMO |
| Reservas | Fila com Aceitar / Rejeitar / Promover (JWT vendedor) |
| Análises | Métricas A/B reais (sem inventar) |
| Histórico | Lives terminadas (Hub + snapshot local) · só consulta |
| Modo Técnico | REF, Ollama, sonda, journal PS, forçar refresh fila, diagnóstico |

## Login vendedor

Sem JWT: Hub anon + actividade Face. Com login Produção: fila operativa (mesmos RPCs da app).  
O formulário permanece aberto até Entrar / Cancelar — polling não o fecha.

## Ambiente

| | |
|--|--|
| Activo | Produção `bpmpkzwnrbmuqnhgdscf` |
| Staging (backup) | `studio_config.staging.js` · `fxdknzrqjenzqcvnwqqq` |
| Hub web | `https://fleaber.pt` (já em produção) |

## Nota Abrir loja

A URL segue `HubUrls.liveWebHash` (`fleaber.pt/fleahub/index.html#/{handle}/live?liveId=`).
