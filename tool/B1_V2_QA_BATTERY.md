# B1-v2 — Retoma QA pós C1 (BUG-037–041)

**ESTADO:** **PAUSA** — marketplace conjunto suficiente; retestes encaixados nas baterias.

**Seguinte:** **ARCO-H1** — `tool/reports/hub_h_manual_qa_battery.md`

## Pipeline ciclo 2 — ordem obrigatória (não saltar)

Cada passo só começa quando o anterior está **PASS**:

1. Proposta conjunto enviada — **APP-083-B** ✓
2. Vendedor aceita — **APP-043-V** ✓
3. Comprador escolhe MB WAY e **declara pagamento enviado** — **APP-031-B** ← **aqui**
4. Vendedor **confirma receção do dinheiro** — **APP-063-V** (estado **pago**)
5. Vendedor **envia artigos** + etiqueta — **APP-055-V** (**nunca antes do 4**)
6. Comprador confirma **receção dos artigos** — **APP-056-B**
7. Avaliação / feedback — **APP-057-B**, **APP-039-B**, **APP-040-V**

**Erro QA corrigido:** «envio» no passo 3 significa **pagamento MB WAY enviado**, não envio postal. **Envio de artigos** = passo 5, só após vendedor confirmar o guito.

### C1 entregue (RETEST)

| Bug | Fix resumido |
|-----|----------------|
| 034 | Timeline por bundle; proposta não mistura compra paga ciclo 1 |
| 041 | Totais do bundle activo (não 26,06 € do ciclo 1) |
| 045 | Sheet Seguro Fleaber vs MB WAY em «Concluir compra» |
| 044 | 1.º lembrete só 2 h após aceite; depois 24 h |
| 043 | Sem header redundante; sem cards reservation legados no bundle |
| 038 | Estado agregado no card fechado + sub-linhas alinhadas |
| 042 | Logs `BATATA_BUNDLE_PROPOSAL` |

## Resultados última ronda (ciclo 2)

| ID | Resultado | Notas |
|----|-----------|-------|
| APP-038-B | **FAIL** | Estado só ao expandir; 1/2 artigos com estado correcto; V igual |
| APP-047a-B | **PASS** | Steppers 2×P + 1×Q OK |
| APP-083-B | **FAIL** | Proposta OK; total 26,06 € errado; thread compra anterior; flash vermelho |
| APP-043-V | **PASS COM AVISO** | Cards duplicados; lembrete pagamento imediato |
| APP-031-B | **FAIL** | Sem MB WAY — só Seguro Fleaber |
| Resto | **SKIP** | Bloqueado por APP-031 |

## Ledger (ecrã = verdade)

- **Prato Vintage P** — 14,00 € — stock **2**
- **Quadro Antigo Q** — 9,00 € — stock **2**
- **Pedido antigo (ciclo 1):** 1×P + 1×Q — **26,06 €** — enviado — receção — **feedback já dado**
- **Pedido novo (ciclo 2):** 2×P + 1×Q — **3 artigos** — proposta → MB WAY → envio → receção → feedback

**Nota estados:** APP-039, APP-040, APP-056, APP-037 (envio limpo) → só no **ciclo 2**. No pedido antigo: só APP-038 se ainda não PASS.

---

## APP-038-B — Encomenda conjunto fechada mostra «Enviado»

**Pré-condição:** pedido ciclo 1 (26,06 €) ainda na lista.

**Quem:** B

1. Abre **Minhas encomendas** → tab **Comprado**.
2. Localiza o card **Conjunto · 2 artigos** — **26,06 €**.
3. **Não expandas** o card.

**No ecrã deve aparecer:**
- Label **«Artigo Enviado»** (ou agregado equivalente) **visível no card fechado**
- Total **26,06 €**

📷 Print do card **fechado**.

**Auditoria deste print:**
1. Estado visível sem expandir
2. Total 26,06 € correcto
3. Sem overflow
4. Coerente com artigo individual «espelho» que também mostra estado fechado

Responde: `APP-038-B: PASS / FAIL`

---

## APP-047a-B — Stepper 2× Prato + 1× Quadro

**Pré-condição:** APK novo com BUG-041; stocks P=2, Q=2.

**Quem:** B

1. Vai ao perfil da vendedora → **Criar conjunto** (ou **Ver conjunto**).
2. Adiciona **Prato Vintage P** e **Quadro Antigo Q**.
3. No **Prato**, toca **+** até mostrar **2**.
4. No **Quadro**, mantém **1**.
5. Abre **Ver conjunto**.

**No ecrã deve aparecer:**
- **3 artigos** no total
- Linha ou texto **Prato ×2** (ou equivalente)
- Total com desconto 10 % — **usa o valor exacto do ecrã**

📷 Print **Ver conjunto** com steppers e total.

**Auditoria deste print:**
1. Stepper P no máximo **2** (não passa stock)
2. Q em **1**
3. Contagem **3 artigos**
4. Total legível, sem overflow

Responde: `APP-047a-B: PASS / FAIL`

---

## APP-083-B — Proposta de conjunto (3 artigos)

**Pré-condição:** APP-047a PASS.

**Quem:** B

1. Em **Ver conjunto**, toca **Fazer proposta**.
2. Introduz um valor (ex. **30,00 €**) ou aceita o sugerido.
3. Envia a proposta.
4. Abre **Mensagens** → chat com a vendedora.

**No ecrã deve aparecer:**
- Card **«Enviaste uma proposta de conjunto»**
- **Prato Vintage P** e **Quadro Antigo Q** com **×2** / **×1** se aplicável
- Total da proposta coerente
- «Aguarda resposta do vendedor»

📷 Print card proposta no chat.

**Auditoria deste print:**
1. Card novo na timeline (não fundido com compra antiga 26,06 €)
2. Três artigos referidos
3. Copy humana, sem ERP
4. Timestamp próprio

Responde: `APP-083-B: PASS / FAIL`

---

## APP-043-V — Vendedor aceita proposta

**Pré-condição:** APP-083-B enviado.

**Quem:** V

1. Abre **Mensagens** → chat com o comprador.
2. No card da proposta → toca **Aceitar**.

**No ecrã deve aparecer:**
- Aceite visível no **V** e confirma no **B**
- Opção **Concluir compra** / pagamento directo para o comprador
- Card compra antiga 26,06 € **intacto** acima

Responde: `APP-043-V: PASS / FAIL`

---

## APP-031-B — Pagamento MB WAY (directo)

**Pré-condição:** APK novo (C1 044–049); ciclo 2 **aceite**; APP-120 PASS; dinheiro **ainda não** confirmado pelo vendedor.

**Quem:** B (Redmi)

1. Instala o APK debug mais recente no Redmi.
2. Abre **Mensagens** → chat com a vendedora (ciclo 2, **3 artigos**).
3. Confirma no **topo** (sticky): **um** botão **«Concluir compra»** — **sem** «Pagar agora (Seguro Fleaber)» duplicado.
4. Confirma no header conjunto: **30,00 €** (proposta) + subtítulo com envio/protecção (**~35,83 €** ou equivalente) — **não** dois totais contraditórios no mesmo sítio.
5. Toca **«Concluir compra»** (sticky do topo).
6. No sheet: **Pagamento directo (MB WAY/Transf)** → confirma.
7. Deve aparecer **card com dados MB WAY/IBAN** na timeline.
8. No sticky: **«Ver dados de pagamento»**, **«Confirmo pagamento»**, **«Mudar para Seguro Fleaber»** (com recomendação).
9. Toca **«Confirmo pagamento»** e envia prova/texto se pedir.
10. Abre **Minhas encomendas** → **Comprado** → conjunto ciclo 2 → **«Ver dados de pagamento»**.
11. Espera **~30 s** no chat — **sem** lembrete «Completa o pagamento» (regra 2 h).

**No ecrã deve aparecer:**
- Sticky único «Concluir compra» → depois CTAs pós-MB WAY coerentes
- Card **dados de pagamento** no chat
- Estado **aguarda confirmação** do vendedor
- Header **30 €** + subtítulo taxas
- **Sem** crash / ecrã vermelho

📷 Print: (1) sticky + header antes de pagar; (2) card dados MB WAY; (3) encomendas com «Ver dados de pagamento».

**Auditoria destes prints:**
1. BUG-046: um fluxo de checkout (não checkout artigo individual)
2. BUG-049: 30 € + subtítulo taxas coerente com card proposta
3. BUG-047/048: dados MB WAY visíveis + sticky evolui
4. BUG-044: sem lembrete imediato
5. Card proposta sem botão duplicado (só texto orientativo)

Responde: `APP-031-B: PASS / FAIL`

**Se PASS** → passo seguinte é **APP-063-V** no TCL (vendedor confirma dinheiro). **Não** fazer envio postal antes.

---

## APP-063-V — Vendedor confirma receção do dinheiro (MB WAY)

**Pré-condição:** APP-031-B PASS — comprador já declarou pagamento; estado **aguarda confirmação**. **Obrigatório antes de qualquer envio de artigos.**

**Quem:** V (TCL)

1. Abre **Mensagens** → chat com o comprador (conjunto **3 artigos**).
2. Ou **Encomendas e Compras** → encomenda do conjunto ciclo 2.
3. Toca **Confirmar receção de dinheiro** (ou equivalente).

**No ecrã deve aparecer:**
- Estado **pago** no **V** e no **B**
- Totais coerentes com proposta aceite (**30,00 €** itens + taxas se aplicável)

📷 Print chat **V** ou encomenda após confirmar.

**Auditoria deste print:**
1. Confirmação foi sobre **dinheiro**, não envio postal
2. Estado **pago** visível nos dois lados
3. Conjunto 3 artigos, não pedido 26,06 €
4. Comprador deixa de ver CTAs de pagamento pendente

Responde: `APP-063-V: PASS / FAIL`

---

## APP-055-V — Envio postal + etiqueta (valida BUG-037)

**Pré-condição:** **APP-063-V PASS** — encomenda ciclo 2 em estado **pago**. Se ainda **aguarda confirmação** do dinheiro → **PARAR**, fazer APP-063 primeiro.

**Quem:** V (TCL)

1. Abre chat com comprador (conjunto **3 artigos**).
2. No card **«Vendido — envia os artigos»** → **Descarregar etiqueta de envio**.
3. Completa fluxo até **marcar enviado**.

**No ecrã deve aparecer:**
- Card **comprado** mantém-se
- **Um só** card **«Artigos enviados»** (cinza)
- **Sem** card azul «O vendedor confirmou o envio…» com carrinha

📷 Print timeline **V**.

**Auditoria deste print:**
1. Botão etiqueta funcionou (regressão BUG-036)
2. Um card envio cinza apenas
3. Sem carrinha azul duplicada
4. Texto «3 artigos» ou «2 artigos» coerente com qty

Responde: `APP-055-V: PASS / FAIL` e `APP-037-V: PASS / FAIL`

---

## APP-086-B — Chat comprador após envio

**Pré-condição:** APP-055-V PASS.

**Quem:** B

1. Abre o mesmo chat.
2. Scroll na timeline.

**No ecrã deve aparecer:**
- Card **Conjunto comprado!** (só texto + 📦)
- Card **Artigos enviados** abaixo — **sem** card azul carrinha

📷 Print timeline **B**.

**Auditoria deste print:**
1. Dois cards cinza distintos (comprado + enviado)
2. Ordem cronológica
3. Compra antiga 26,06 € ainda visível se aplicável
4. Cabeçalho **3 artigos** / total novo coerente

Responde: `APP-086-B: PASS / FAIL`

---

## APP-065-B — Encomenda conjunto 3 artigos (fechado + expandido)

**Quem:** B

1. **Minhas encomendas** → card **Conjunto · 3 artigos** — **sem expandir**.
2. Expande o card.

**No ecrã deve aparecer:**
- **Fechado:** estado **Enviado** visível
- **Expandido:** **Prato ×2** e **Quadro ×1** com estados legíveis

📷 Print fechado + expandido.

Responde: `APP-065-B: PASS / FAIL` e `APP-038-B: PASS / FAIL` (se ainda não fizeste o primeiro)

---

## APP-056-B — Confirmar receção

**Pré-condição:** encomenda **enviada**; receção **ainda não** confirmada neste pedido.

**Quem:** B

1. Chat ou encomenda → **Confirmar receção da encomenda**.

**No ecrã deve aparecer:**
- Estado actualizado para recebido/entregue
- Card comprado + enviado **preservados** na timeline

Responde: `APP-056-B: PASS / FAIL`

---

## APP-039-B — Botão «Deixar avaliação» no chat

**Pré-condição:** APP-056-B PASS; **feedback ainda não dado** neste pedido (ciclo 2).

**Quem:** B

1. No **mesmo chat**, após confirmar receção.
2. Procura CTA no card ou timeline.

**No ecrã deve aparecer:**
- Botão ou link **«Deixar avaliação»** (ou equivalente)

📷 Print com CTA visível.

Responde: `APP-039-B: PASS / FAIL`

---

## APP-057-B — Deixar avaliação

**Pré-condição:** APP-039-B PASS.

**Quem:** B

1. Toca **Deixar avaliação**.
2. Escolhe estrelas e escreve texto curto → envia.

Responde: `APP-057-B: PASS / FAIL`

---

## APP-040-V — Card vendedor pós-avaliação

**Pré-condição:** APP-057-B PASS.

**Quem:** V

1. Abre chat com o comprador.

**No ecrã deve aparecer:**
- Card cinza **«Avaliação recebida (N★). O valor ficará disponível na tua carteira.»** (ou copy equivalente)

**Quem:** B — no chat deve aparecer **«Avaliação enviada…»**

📷 Print chat **V**.

**Auditoria deste print:**
1. Card vendedor presente
2. Menciona carteira/saldo
3. Estrelas coerentes com review
4. Não apaga cards compra/envio anteriores

Responde: `APP-040-V: PASS / FAIL` e `APP-040-B: PASS / FAIL`

---

## APP-047-B — Stock final

**Quem:** B

1. **Início → Marketplace** → abre **Prato Vintage P** e **Quadro Antigo Q**.

**No ecrã deve aparecer:**
- **Prato:** stock **0** (ou vendido se qty 0)
- **Quadro:** stock **1**

Responde: `APP-047-B: PASS / FAIL`

---

## Ordem de execução

APP-038-B → APP-047a-B → APP-083-B → APP-043-V → APP-031-B → APP-063-V → APP-055-V → APP-086-B → APP-065-B → APP-056-B → APP-039-B → APP-057-B → APP-040-V → APP-047-B

Responde um ID de cada vez ou em bloco; prints nos passos marcados 📷.
