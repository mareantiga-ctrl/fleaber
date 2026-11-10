# Fleaber — Auditoria honesta de cobertura QA manual

**Última actualização:** 2026-08-24 (APP-143 · 144 · 145 → PASS; BLOQUEADO 0)  
**Âmbito:** toda a app (funcional + UX), **incluindo** NAV-* (back / tabs / deep links).

---

## Resumo executivo

Contagem a partir de `FLEABER_APP_QA_MASTER_LIST.md` (170 linhas únicas). Categorias fecham: APP 139 · NAV 8 · SEC 23 · global 170.

| Métrica | Realidade |
|---------|-----------|
| **APP-ids na lista mestre (sem SEC)** | **139** |
| **PASS (APP)** | **132 / 139** (~**95,0%**) |
| **PASS ATÉ API (APP)** | **2** (055, 071 — transportadora) |
| **PASS + PASS ATÉ API + PASS COM AVISO (APP)** | **134 / 139** (~**96,4%**) — 132 + 2 + 0 |
| **PASS COM AVISO (APP)** | **0** |
| **PENDENTE (APP)** | **0** |
| **N/A (retirado)** | **2** (APP-062, APP-084) |
| **FAIL abertos (lista)** | — |
| **BLOQUEADO** | **0** |
| **NAV-*** | 8 · **8 PASS** |
| **APP-SEC-*** | 23 · **20 PASS** · **3 PASS COM AVISO** · **0 PENDENTE** |
| **Placar global (170 linhas)** | **160 PASS · 2 PASS ATÉ API · 3 AVISO · 0 PEND · 0 FAIL · 0 BLOQ · 2 WONTFIX · 2 N/A** |

**Conclusão:** Placar 170: **160 PASS · 2 PASS ATÉ API · 3 AVISO · 0 FAIL · 0 BLOQ**. APP-143/144/145 fechados 2026-08-24 (TCL+Redmi + BD). AVISO restantes: SEC-008 · SEC-013 · SEC-019 (PS/FB lab).

**Próxima ronda:** Face real PS + Facebook Live — `tool/reports/battery_ps_face_real_DESIGN.md` (vídeo App Review / pedido API). **Sem Lab/harness.**

---

## Fontes

- Lista: `tool/FLEABER_APP_QA_MASTER_LIST.md`
- PASS ATÉ API: `tool/PASS_ATE_API_REGRESSION.md`
- AVISO ronda 2: `tool/reports/battery_aviso_2026-08-23/`
- AVISO live 218/020: `tool/reports/battery_aviso_live_2026-08-23/`
