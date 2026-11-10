# Fleaber — Mapa mestre de baterias QA

**Lista completa (142 testes):** `tool/FLEABER_APP_QA_MASTER_LIST.md`

**Cobertura %:** `tool/QA_COVERAGE_AUDIT.md` (~20% após série P parcial)

**Arco activo:** **ARCO-H1** Hub → `tool/reports/hub_h_manual_qa_battery.md`  
**Marketplace P1:** pausa — retestes em `tool/B1_NEXT_C1_BATCH.md`

---

## Princípios

- **Lista mestre** deriva do **código** (`lib/`) — não de perguntas ao utilizador.
- **Arco denso:** um fio, máximo de APP-ids, mínimo de passos; até feedback quando possível.
- **Cross-superfície:** live/Hub/marketplace devem reflectir os mesmos dados (APP-400–405).
- **Stripe sandbox** → WONTFIX retorno app; arco usa MB WAY (APP-120 setup + APP-031).

---

**B1-v2 / série P** cobre **só marketplace** — ver cobertura real em `tool/QA_COVERAGE_AUDIT.md` (~**12–18%** da app total testada; **não** confundir com progresso global).

## Ordem de execução (não saltar áreas — Hub é tarde no plano)

| # | Bateria | Ficheiro | Área | Estado real |
|---|---------|----------|------|-------------|
| **1a** | Série P marketplace | `B1_V2_QA_BATTERY.md` | Conjunto MB WAY | **PAUSA** — suficiente |
| **1a′** | Retestes encaixados | `B1_NEXT_C1_BATCH.md` | 072, 067, 071 | Nas baterias onde couber |
| **3** | **Hub H manual** | `hub_h_manual_qa_battery.md` | FleaHub público + ↔ app | **ACTIVO** ← agora |
| auto | Matriz A### / T## | `FULL_TEST_INVENTORY.md` | CI/C2 | Paralelo |

**Regra utilizador:** testar **toda a app** (funcional + UX), **incluindo** navegação (NAV-001–008) — automatizar quando possível.

---

## F-v3 — o que falta depois de B1-v2 (referência)

Grupos da bateria completa original (IDs F###) ainda por correr manualmente:

| Grupo | Exemplos | Dispositivos |
|-------|----------|--------------|
| Live prep + studio | Preparar directo, linhagem, catálogo | V |
| Live player + saco | Reservar, pagar saco, rifa | V + B + PC |
| Chat live + DM profundo | Todos os tipos M01–M30+ | V + B |
| Wallet + levantamentos | Créditos, payout | V |
| Feedback + avaliações | Pós-entrega | B |
| Modo férias, staff, Operação | Backoffice seller | V |

Quando B1-v2 fechar CHECKPOINT E → retomar Hub Seller (bateria #2).

---

## Prints mestres (cobertura cruzada)

| Print | Audita (múltiplos IDs) |
|-------|-------------------------|
| **P03** chat bundle | RGX-CHAT: topo expandível, card só texto, sem teal, total, lista, tap detalhe, timestamps |
| **P05** encomendas | RGX-ENC: estado, copy humana, total, sub-linhas, ⋮, overflow, coerência B↔V |
| **P07** timeline | RGX-TIMELINE: ordem cronológica, comprado+enviado+proposta separados |
| **P01** overflow | Gestão + marketplace scroll |
| **P08** envio | Etiqueta/confirmado + chat pós-envio |

---

## Dispositivos

- **V** = TCL vendedor
- **B** = Redmi comprador
- **PC** = Chrome (Hub web / 2.ª conta)

---

## Histórico decisões

- Série produtos **M/N/L** activa na B1-v2 (L eliminado).
- Séries A/B/C, G/H/I, J/K — abandonadas, não reutilizar.
- Hub encomendas seller: **N/A** no Hub público (034 SKIP doc).
