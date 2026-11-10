# Retestes / C1 — encaixados nas baterias (não correr isolados)

**Regra:** estes pontos **não** são passos à parte. Validam-se quando a bateria activa passar pelo sítio certo. Um único prompt C1 no fim acumula tudo o que ainda estiver **FAIL**.

---

## Mapa — onde cada pendente entra

| ID | O quê | Encaixar em | Gatilho natural |
|----|--------|-------------|-----------------|
| **072** | «Nova oferta» empilhada no B | **ARCO-P1 ciclo 2** ou **ARCO-L1** (chat pós-reserva) | Qualquer fluxo: recusar → nova oferta 2× |
| **067** | Timeline ordem chegada | **ARCO-H1** passo cross-chat **ou** **ARCO-L1** fim de compra | Scroll fundo chat com envio/receção |
| **071** | Borda expandido encomendas | **ARCO-H1 ↔ APP-402** ou sweep **APP-050** | Visita **Minhas encomendas** na mesma sessão Hub |
| **APP-400–405** | Cross-superfície Hub ↔ app | **ARCO-H1** (todos os passos com loja/stock) | Artigo no Hub = mesmo preço/stock na app |
| **APP-095** | Lembretes 2h/24h | **ARCO-L1** ou chat reserva activa | Quando passarem 2h/24h da aceite |
| **Travessa fim ciclo** | Confirmar $ → envio → feedback | **Opcional** em cross APP-401/402 | Só se abrires encomenda Travessa durante Hub |

**Já PASS (não re-testar isolado):** 042, 059, 060, 062, 064, 065, 066R, 070, passos 5–9 Travessa.

---

## Lote C1 único (quando houver FAIL acumulado)

Incluir na mesma entrega C1: **072** (+ **071** se ainda aviso) (+ **067** se FAIL após Hub/Live).

Ver `.cursor/rules/qa-c1-prompt-batata.mdc`.

---

## Estado marketplace (pausa estratégica)

Arco **ARCO-P1** conjunto MB WAY: **suficiente para avançar**. Pendências acima via cross-checks, não bloco dedicado.
