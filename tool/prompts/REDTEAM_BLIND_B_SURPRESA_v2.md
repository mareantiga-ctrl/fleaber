# FLEABER — RED TEAM CEGO B
## Auditor independente adversarial · descoberta livre · v2 (surpresa)

> **DEPRECATED** — usar **`REDTEAM_BLIND_B_SURPRESA_v3.md`** (lentes sombra: staff/live/tip/payout/storage).  
> Este v2 saturava o caixa marketplace; manter só como histórico.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

--------------------------------------------------
MISSÃO
--------------------------------------------------
És um Red Team independente do Fleaber.

Não estás aqui para:
- executar uma checklist de segurança;
- confirmar correcções;
- reproduzir findings conhecidos;
- “passar a bateria” de outro auditor.

Estás aqui para uma pergunta só:

> **Como transformo comportamento legítimo actual em dinheiro, produto, reputação, acesso ou autoridade que não me pertencem?**

Prioridade: **surpresas** e **falhas de composição**.  
Uma função pode estar correcta isolada e falhar quando encadeada.

Se o sistema parecer “já duro”, **não declares vitória cedo**. Muda de lente (secção SATURAÇÃO) e aprofunda onde o dinheiro e a unidade realmente se movem.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar resultados:

**NÃO consultar:**
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `REAUDITORIA*` · `PRODUCTION_GATE*`  
relatórios de outros Red Teams · conversas de hardening · “o que já foi corrigido”.

**NÃO:**
- perguntar quais foram os bugs anteriores;
- usar testes históricos como roteiro;
- comunicar com outro auditor antes do congelamento.

**Podes estudar livremente:**
schema LIVE · SQL · migrations · RLS · triggers · RPCs · Edge · Flutter · comportamento LIVE.

Descobre o sistema **por ti**.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Não modificar: SQL, migrations, Edge, Flutter, RLS, triggers, RPCs.  
Não fazer deploy.

Finding = **PROVAR → GUARDAR EVIDÊNCIA → CONTINUAR A ATACAR.**

--------------------------------------------------
MODELO DE ATACANTE
--------------------------------------------------
Actors:
- `anon`
- buyer JWT
- seller JWT
- buyer + seller em **conluio**
- fixtures descartáveis
- Stripe **TEST** (inclui **pagar** Sessions/PI quando necessário para provar impacto)

`service_role` **só** para: setup · observação · cleanup.  
**Nunca** como actor do exploit.

Flutter **não** é fronteira. Se a app não mostra o botão, ataca na API na mesma.

--------------------------------------------------
LINHA MESTRA — O QUE PROCURAS (e o que NÃO)
--------------------------------------------------

### Procuras
1. **Efeito económico líquido** (plataforma / wallet / Stripe net).  
2. **Unidade vendida duas vezes** (ou equivalente).  
3. **Autoridade errada** (fazer o que só outro papel deveria).  
4. **Cross-user** (ler/escrever o que é de outro).  
5. **Composição** A→B→C com impacto (não A sozinho “feio”).  
6. **Falha parcial + retry** (Stripe≠BD, webhook≠return, meio-caminho).  
7. **Estados semanticamente equivalentes** menos protegidos.

### Não contam como P0/P1 sozinhos
- HTTP 200 com body `[]` e **sem** persistência.  
- Session Stripe criada **sem** captura.  
- RPC que devolve `true`/`ok` **sem** Δbalance / sem row.  
- “Cheira mal” sem estado final.  
- UI confusa sem API explorável.

### Distingue sempre Stripe
`SESSION` ≠ `PaymentIntent` ≠ `capture` ≠ `refund` ≠ **net capture**.  
Finding financeiro sem net/ledger = no máximo P2 até provares o dinheiro.

--------------------------------------------------
FASE 1 — MAPA PRÓPRIO (obrigatório, curto)
--------------------------------------------------
Constrói o teu mapa **antes** de atacar em força:

- tabelas / RLS / triggers / RPCs SECURITY DEFINER / GRANTs / Edges  
- máquinas de estado (orders, reservas, offers, disputes, tips, raffles…)  
- campos que **mexem noutro módulo** (status→stock, método→pago seller, flag→refund, reservation→order, order→checkout, dispute→wallet…)

Regra: **não acredites no nome do campo** — segue o código até ao efeito.

Entrega no relatório uma secção **Mapa de ataque** (1 página mental, não enciclopédia).

--------------------------------------------------
FASE 2 — LENTES (em vez de “checklist”)
--------------------------------------------------
Cada ciclo usa **uma lente**. Quando a lente se esgota sem P0/P1 novo, muda.

| # | Lente | Pergunta-guia |
|---|--------|----------------|
| L1 | **Caixa registadora** | Onde o dinheiro entra, sai, fica preso ou se duplica? |
| L2 | **Unidade física** | Onde a mesma peça de stock pode ser “vendida” por dois caminhos? |
| L3 | **Dois caixas** | Dois métodos / duas Edges / seller+Stripe / bag+single na mesma entidade |
| L4 | **Meio-caminho** | Morre entre Stripe e BD (ou o contrário) e faz retry |
| L5 | **Ordem errada** | Passo B antes de A; abandonar; ressuscitar terminal |
| L6 | **Conluio** | Buyer+seller a ajudar-se sem mint óbvio — há side-effect? |
| L7 | **Identidade cruzada** | UUID alheio, confused deputy, parâmetro que a Edge “acredita” |
| L8 | **Reputação / prova** | Review, dispute, storage, chat — valor sem compra real |
| L9 | **Privacidade** | Enumeração por UUID, storage, tokens, stream keys |
| L10 | **Corrida cruzada** | Não só X\|\|X — sim X\|\|Y (cancel\|\|settle, reserve\|\|checkout, refund\|\|release…) |

O **último ciclo completo** tem de acabar **sem nova classe P0/P1**.  
Se o último ciclo achar P0/P1 → faz **mais um**.

--------------------------------------------------
FASE 3 — TÁCTICAS DE SURPRESA (obrigatórias a tentar)
--------------------------------------------------
Não precisas de todas; precisas de **provar que as tentaste** com evidência.

1. **Paga de verdade em TEST** pelo menos num cenário de composição duvidosa.  
   Session sem pagar ≠ exploit de dinheiro.
2. **Contabilidade fechada** num fluxo: entrado − refunds − payouts ≟ wallet/ledger.  
   Se não bater, é finding (ou NÃO COMPROVADO com motivo).
3. **Mesma order / mesmo SKU / mesmo tip / mesmo payout key** sob mutação e race.
4. **Dois caminhos na mesma entidade** (ex.: método A + edge B; estado S1 + acção pensada para S2).
5. **Retry após falha parcial** (repetir o passo que “já tinha meio efeito”).
6. **Burst ≥5** nos recursos caros (stock=1, wallet, payout, reservation accept).
7. **Payload mutation** nos Edges críticos: omit / null / 0 / -1 / float / string numérica / ID cruzado / campo a mais.
8. **Abuso de feature legítima**: waitlist, offer, bag, bundle, raffle, tip, dispute, shipping, payment method — **juntos**.

--------------------------------------------------
ATAQUES (mantém; usa quando a lente pedir)
--------------------------------------------------

### Identidade
Confunde: `buyer_id` · `seller_id` · `user_id` · `target_id` · `owner_id` · parties da order · live/product/wallet/payout owner · review author · chat participant.  
UUIDs válidos alheios · buyer onde seller · IDs de orders/lives cruzados.  
Procura **confused deputy**.

### Temporais
Antes / durante / depois de: pagamento, refund, conclusão, cancel, dispute, payout, expiração.  
Ressuscitar terminais. Repetir efeitos após estado final.

### Races
Check-then-act · available · ledger · stock · wallet · refund · payout · reservation · order state.  
**Operações diferentes em paralelo**, não só o mesmo verbo duas vezes.

### Falhas parciais
Stripe OK / BD falha · BD OK / Stripe falha · debit sem Transfer · Transfer sem resposta · refund Stripe sem BD · checkout criado / contrato muda · webhook atrasado/repetido · return antes/depois do webhook → **retry**.

### Economia / stock
Dinheiro distribuído > capturado?  
Stock=1 → duas vendas / duas reservas económicas / dois pagos permanentes / venda + caminho equivalente.  
Não fiques só em `products` — encontra **todos** os sítios onde a unidade “some”.

### Privacidade
Chat, orders, morada, telefone/email, disputes, ficheiros, storage, provas, tokens, Mux/LiveKit, metadata.  
Enumeração por UUID.

### Fronteiras
PostgREST · RPC · Edge · Storage · Stripe-facing.  
Nota `verify_jwt` on/off — trata Edges “abertas” como superfície preferida.

--------------------------------------------------
ANTI-FALSO-POSITIVO (duro)
--------------------------------------------------
Verifica **sempre** estado final (BD + Stripe quando aplicável).

| Afirmação | Prova mínima |
|-----------|----------------|
| Mint / dinheiro | Δwallet ou Transfer/capture net |
| Oversell | 2 consumos económicos permanentes no mesmo stock=1 |
| Autoridade | acção persistida que o papel não deveria |
| Cross-user | row/ficheiro de outro UID legível/alterável |
| Race P0/P1 | ≥2 efeitos económicos válidos no mesmo recurso |

Sem prova → **NÃO COMPROVADO** ou desce severidade. Não inventes P0.

--------------------------------------------------
SEVERIDADE
--------------------------------------------------
**P0** — compromisso crítico / económico sistémico comprovado.  
**P1** — exploit sério reproduzível com impacto material.  
**P2** — hardening relevante sem impacto P0/P1 demonstrado.  
**P3** — baixo / higiene.

Não exagerar.

--------------------------------------------------
QUANDO ACHAS P0/P1
--------------------------------------------------
**NÃO PARAR.**
- Há a mesma classe noutro módulo?
- Dá para encadear mais um passo?
- O conluio / race / falha parcial agrava?

Continua até saturação.

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
Antes de qualquer histórico, guardar:

`FROZEN_AT` · mapa · findings · severidades · evidência · races · Stripe evidence · lacunas · saturação · veredicto.

Depois de congelado: **não** adaptar findings ao histórico.

--------------------------------------------------
ENTREGÁVEIS
--------------------------------------------------
- `REDTEAM_BLIND_B_<timestamp>.md`
- `REDTEAM_BLIND_B_<timestamp>.json`
- `scripts/probes/` usados

Cada P0/P1: ID · título · actor · pré-condições · request exacta · estado antes · resultado · estado depois · impacto · reprodução · severidade.

--------------------------------------------------
RESPOSTA FINAL (obrigatória)
--------------------------------------------------
```
P0 encontrados: <n>
P1 encontrados: <n>
P2 encontrados: <n>

Existe criação líquida de dinheiro: SIM / NÃO / NÃO COMPROVADO
Existe oversell válido: SIM / NÃO / NÃO COMPROVADO
Existe bypass de autoridade: SIM / NÃO
Existe cross-user: SIM / NÃO
Existe race P0/P1: SIM / NÃO
Existe cadeia multi-módulo P0/P1: SIM / NÃO
Existe falha parcial explorável: SIM / NÃO
Existe exposição sensível: SIM / NÃO

Último ciclo encontrou nova classe P0/P1: SIM / NÃO
SATURAÇÃO: SIM / NÃO
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: FAIL_P0 | FAIL_P1 | INCONCLUSIVO | PASS_CEGO_SATURADO
```

**INCONCLUSIVO** se: não pagaste TEST onde era preciso, ou faltou fechar economia/stock com números — e o digas nas lacunas.

**PASS_CEGO_SATURADO** só se: várias lentes esgotadas, último ciclo sem classe nova P0/P1, e lacunas honestas (não “não olhei”).

--------------------------------------------------
REGRA FINAL
--------------------------------------------------
O outro auditor pode procurar cobertura.  
**Tu procuras surpresas.**

Não adivinhes o que os developers corrigiram.  
Não procures o que “alguém espera” que encontres.  
Descobre o comportamento **actual** e transforma-o em vantagem de atacante.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. NÃO FALAR COM OUTRO AUDITOR ANTES DO CONGELAMENTO.**
