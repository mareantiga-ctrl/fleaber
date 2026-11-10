# Reteste batch C1 — ledger completo (ecrã = verdade)

**APK:** `build\app\outputs\flutter-apk\app-debug.apk` · **V** TCL · **B** Redmi

## Fase C1 065–069 (artigos novos — não usar Caneca/Tigela)

| Nome | Preço | Stock inicial |
|------|-------|---------------|
| **Travessa Retro T** | **12,00 €** | **2** |
| **Taça Cerâmica U** | **8,00 €** | **2** |

Conjunto: **Travessa ×2** + **Taça ×1** — mesma matemática (32 / 28,80 / 34,57 / 32,30 MB WAY).

**067** usa chat **Jarra/Vaso fechada** (sem artigos novos).

---

## Artigos reteste anterior (referência)

---

## Ver conjunto — linha a linha (é isto que comparas no ecrã)

| Linha no ecrã | Valor esperado |
|---------------|----------------|
| **3 artigos** | 3 |
| **Preço** (subtotal antes desconto) | **32,00 €** |
| **Taxa de Proteção do Comprador** | **2,27 €** |
| **Custos de envio** | **3,50 €** |
| **Desconto de conjunto (10 %)** | **− 3,20 €** |
| **Total** (bold, fundo página) | **34,57 €** |

Tolerância: **± 0,02 €**.

### Nota proposta (não confundir)

- O diálogo **Fazer proposta** pode sugerir **28,80 €** (= só artigos após desconto) — isso é normal no código.
- O **Total 34,57 €** na página **Ver conjunto** inclui protecção + envio.
- No chat, card proposta: **Desconto − 3,20 € · Total 28,80 €** (itens negociados).
- Header chat pós-aceite: **28,80 €** + subtítulo **«com envio e protecção: 34,57 €»** (Seguro) ou **32,30 €** (MB WAY directo = 28,80 + 3,50, sem protecção).

---

## MB WAY directo (comprador)

| Conceito | Valor |
|----------|-------|
| Itens | **28,80 €** |
| + CTT | **3,50 €** |
| **Total a pagar fora da app** | **32,30 €** |

---

## Stock depois do fluxo completo

| Artigo | Depois |
|--------|--------|
| Jarra Retro R | **0** |
| Vaso Ceramica V | **1** |

## Estado actual (2026-07-06 tarde — pós C1)

| Teste | Resultado |
|-------|-----------|
| **042** Proposta | **PASS** (1.ª msg reutilizada → **061** aberto; 2.ª OK) |
| **059** Cancelar reserva | **PASS** |
| **060** Sheet desconto | **PASS** |
| **038, 053, 054, 055, 058** | **PASS** |
| **050, 056, 049, 047** | **PASS COM AVISO** (062, 063, 064) |
| **063** Ordem cards chat (etiqueta/receção) | **PASS** (revalidado passo 5–6) |
| **PAUSADO** — C1 **065–069** + 061 reopen. **Não** continuar Caneca/Tigela (stock contaminado).

### Resultados bateria R1–R6 (2026-07-06)

| ID | Resultado |
|----|-----------|
| **071/068** | Encomendas expandido | **PASS COM AVISO** — pedir borda teal mais marcada |
| **067** | Timeline Jarra legada | **FAIL** — ordem chegada ainda incoerente |
| **070/061** | Nova oferta (passos 1–3) | **PASS** |
| **066R** | Contrapropor (passo 4) | **PASS** |
| **5–9** | Aceitar → cancel → nova oferta → aceitar → MB WAY | **PASS** (6 **PASS COM AVISO**) |
| **065/R4** | Stock pós-cancel + checkout | **PASS** (passo 9) |
| **072** | Botões «Nova oferta» duplicados pós-recusa | **ABERTO** |

---

## Compra antiga (RETEST-038)

| Total | **26,06 €** | card fechado **Artigo Enviado** / **Concluída** |
