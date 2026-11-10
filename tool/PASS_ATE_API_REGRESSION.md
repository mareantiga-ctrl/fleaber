# PASS ATÉ API — regressão obrigatória (APIs externas)

**Regra (auditoria C25, 2026-08-22):** se o produto **actual** está correcto e a única parte em falta depende de uma **API externa ainda não integrada**, classificar **`PASS ATÉ API`**.

- **Não** conta em `PASS COM AVISO`
- **Não** fica `PENDENTE` / `FAIL`
- Quando a API for integrada → **retestar estes IDs** antes de promover a `PASS`

Fonte de verdade dos estados: `tool/FLEABER_APP_QA_MASTER_LIST.md`.

---

## Lista activa

| ID | Função | API de que depende | O que validar no reteste |
|----|--------|--------------------|---------------------------|
| **APP-055** | Envio postal + descarregar etiqueta (vendedor) | **API transportadora** (geração etiqueta, dados/morada, download/QR, entrega ao transportador, tracking) | Ponta-a-ponta: geração etiqueta → dados/morada → download/QR → entrega ao transportador → tracking/estado enviado → BD → UI comprador e vendedor. **Não** confundir «Descarregar etiqueta» (stub actual) com confirmação real de entrega ao carrier. Stub 2026-08-23: CTA → card enviado (`battery_aviso_2026-08-23/screenshots/aviso055_*`). |
| **APP-071** | `devolucao_entregue` (etiqueta devolução) | **API transportadora** (etiqueta PDF real + eventos de envio/scan) | Download/abertura da etiqueta **não** marca enviado sozinho; `devolucao_entregue` (ou equivalente) só após evento real do carrier (contrato a definir). Stub actual: `BUG_C25_RETURN_LABEL_CHROME.md` |

**Total PASS ATÉ API na lista mestre:** **2**

---

## Histórico

| Data | Alteração |
|------|-----------|
| 2026-08-23 | Auditoria AVISO ronda 2: APP-055 promovido de PASS COM AVISO → PASS ATÉ API (stub envio OK; regressão com API carrier) |
| 2026-08-22 | C25: APP-071 introduzido como PASS ATÉ API (fechamento auditoria independente) |
