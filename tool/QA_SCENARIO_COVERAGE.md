# Cobertura QA — métrica complementar (2026-08-23)

**Problema:** «0 PENDENTES» nos 170 IDs **não** reflecte horas de baterias (Hub H, regressões, subtestes, matriz A###).

**Regra:** não inflacionar os 170. Esta métrica **complementa** a lista mestre.

---

## Resumo director (copiar)

**170 IDs QA (lista mestre)** — **146 fechados** / **24 com trabalho documentado**

| Bucket | Contagem | Significado |
|--------|----------|-------------|
| PASS | 141 | Fechado |
| PASS ATÉ API | 1 | Fechado produto; falta API transportadora (071) |
| WONTFIX | 2 | Fechado por decisão (030, 044 Stripe sandbox) |
| N/A | 2 | Retirado (062, 084) |
| **Subtotal fechado** | **146** | |
| PASS COM AVISO | 19 | Funciona; falta print/reteste/API parcial |
| FAIL | 2 | 065, 095 |
| BLOQUEADO | 3 | 143–145 (deploy refund) |
| **Subtotal aberto** | **24** | |

**~52 cenários Hub H + regressões nomeadas** — **~15 executados hoje (Hub H 2026-08-23)** / **~37 ainda por correr ou revalidar**

**Matriz técnica A### (429)** + **T01–T21 (21)** — camada CI/bot; **~131 marcados `manual`** na matriz — **não** entram no denominador 170.

**Performance (novo, pós-bug catálogo)** — **0/5 perfis** (1 / 20 / 50 / 80 / 150 artigos **seleccionados**).

---

## Hub H 2026-08-23 — mapa para IDs

| Cenário Hub | Executado | ID(s) mestre | Tipo |
|-------------|-----------|--------------|------|
| **Z1** | PASS | **NAV-004** | Regressão (já PASS) |
| **R1** | PASS | *(sem ID)* — refresh Home/Loja/Opiniões | Subteste Hub |
| **D1** | PASS | *(sem ID)* — login web escrever/colar | Subteste Hub |
| **APP-200 / prep catálogo** | PASS | **APP-200** | **ID real — único que mudou estado** (FAIL→PASS pós-fix) |
| **A0** | PASS | **APP-202** (directo activo) | Regressão |
| **A2a sem rifa** | PASS manual | **APP-216** (sub-cenário partilhar sem +1) | Regressão subteste |
| **C1** | PASS | **APP-306**, **APP-213** | Regressão cross-check unidades |
| **C1b** | PASS | *(sem ID)* — UX card reservas | Subteste UX |
| **A2a com rifa** | PASS | **APP-216** (sub-cenário rifa activa) | Regressão subteste |
| **A2** | PASS | **APP-304** (Gravados) | Regressão revalidada |
| **C2** | PASS | **NAV-006**, **NAV-007** (parcial) | Regressão navegação saco/player |
| **D2** | SKIP | — | Fora âmbito |
| Maestro Hub UX 01–04 | PASS | **APP-300**, **302**, **016**, **200** (parcial) | Regressão automatizada |

**Conclusão Hub H:** ~3h de testes → **+1 ID no placar** (APP-200). Resto = **confiança** em IDs já PASS.

---

## Subtestes Hub **sem ID próprio** (importantes, fora dos 170)

| Código | Descrição | Estado 2026-08-23 |
|--------|-----------|-------------------|
| **HUB-R1** | Pull-to-refresh Home/Loja/Opiniões | PASS |
| **HUB-D1** | Login Chrome paste | PASS |
| **HUB-C1b** | Card reservas compacto | PASS |
| **HUB-A2a-S** | Partilhar sem rifa (só link) | PASS manual |
| **HUB-A2a-R** | Partilhar com rifa + retroactivo | PASS |
| **HUB-C2** | Sair/voltar player — reservas mantidas | PASS |
| **HUB-D2** | Demo Facebook `ps_demo=1` | SKIP |

Regressão permanente documentada (bug catálogo): **produtos OFF no prep nunca entram no sync** — cobrir em reteste APP-200 + cenário futuro **PERF-01**.

---

## O que falta executar (lista nominal)

### A) Placar 170 — acções reais

**FAIL (2) — obrigatório para subir placar**
1. **APP-065** — card encomenda «enviado» só expandido (BUG-038)
2. **APP-095** — lembretes 2h/24h, não imediato (BUG-044)

**BLOQUEADO (3) — precisa deploy/SQL**
3. **APP-143** — cancel Seguro → refund Stripe auto
4. **APP-144** — cancel MB WAY pago
5. **APP-145** — pós-cancel Seguro carteira V

**PASS COM AVISO (19) — fechar aviso (opcional para «PASS limpo»)**
6. APP-026 · 028 · 031 · 043 · 055 · 056 · 063 · 083 · 085 · 086 · 218  
7. NAV-003  
8. APP-SEC-008 · 013 · 017 · 019 · 020 · 021 · 025  

**PASS ATÉ API (1)**
9. **APP-071** — etiqueta devolução quando API transportadora existir

### B) Fila `MANUAL_QA_PENDING.md` (fora coluna PENDENTE)

10. **Carrossel montra** — scroll carrossel não salta vitrine  
11. **AO VIVO fantasma Home** — sem badge live morta  
12. **CTAs texto** — padding pós-fix APP-032  
13. **Reembolsos legal** — copy secção A automática  
14. Reteste visual **APP-124** Lab 3 reservas (master diz PASS; fila ainda lista confusão)

### C) Performance (pós-bug catálogo — auditor)

15. **PERF-01** — perfil 1 artigo seleccionado  
16. **PERF-02** — 20 artigos  
17. **PERF-03** — 50 artigos  
18. **PERF-04** — 80 artigos  
19. **PERF-05** — 150 artigos  

*(Só medir; não optimizar às cegas — `PERFORMANCE_LIVE_CATALOG.md`)*

### D) Cross-checks Hub (opcionais na mesma sessão)

20. **APP-402** — preço/stock Hub loja ↔ Início  
21. **APP-067** — ordem cronológica chat compra antiga  
22. **APP-071** UI — card 26,06 € expandido (se ainda visível)

### E) Matriz A### — manual restante (~131 linhas `manual`)

Não listar os 131 aqui — inventário completo: `tool/FULL_TEST_INVENTORY.md`.  
Exemplos prioritários pós-Hub: **A331** scrub gravado · **A348** sync cross-device · **A357** toggle marketplace em directo activo.

### F) Arcos ainda «PENDENTE» no mapa (desactualizado vs IDs)

- **ARCO-P1** marketplace — **PAUSA** (maioria IDs já PASS; retestes 065/095)
- **ARCO-L1** — IDs 200–218 largamente PASS; falta reteste performance + 124 visual
- **ARCO-MSG** — sweep 060–073 parcial
- **ARCO-PROF** — 143–145 bloqueados

---

## Porque «0 PENDENTES» engana

| Situação | Conta como PENDENTE? | Trabalho real |
|----------|---------------------|---------------|
| Hub H Z1/R1/C1… | Não (IDs já PASS) | Horas de regressão |
| APP-200 bug novo | Só quando marcado FAIL | 1 ID mexeu |
| APP-065/095 FAIL | Sim | Ainda abertos |
| PASS COM AVISO | Não | 19 retestes opcionais |
| PERF 1/20/50/80/150 | Não existe ID | 5 sessões planeadas |
| A### manual | Fora dos 170 | Dezenas/centenas |

---

## Próximo passo recomendado (placar + honestidade)

1. **APP-065** ou **APP-095** — única forma de **+1 PASS** no placar global (fora AVISO→PASS).  
2. Documentar **PERF-01** (1 artigo) antes de qualquer batch RPC.  
3. Manter **HUB-*** subtestes neste ficheiro; não duplicar como APP-xxx.

---

## Referências

- Lista mestre: `tool/FLEABER_APP_QA_MASTER_LIST.md`
- Hub H: `tool/reports/hub_h_manual_qa_battery.md`
- Auditor Hub final: `tool/reports/battery_hub_h_2026-08-23/AUDITORIA_HUB_H_FINAL.md`
- Fila retest: `tool/reports/MANUAL_QA_PENDING.md`
- Performance: `tool/reports/battery_c27_2026-08-23/PERFORMANCE_LIVE_CATALOG.md`
