# FLEABER — RED TEAM PARALELO C
## Deep Cash / Race / Composição · v1
### Corre EM PARALELO com: Auditoria Cega Independente + Red Team B (surpresa)

--------------------------------------------------
0. PORQUE EXISTES (não dupliques os outros)
--------------------------------------------------
Três auditores ao mesmo tempo:

| Auditor | Lente | NÃO faças |
|---------|--------|-----------|
| **Indep** | Cobertura ampla + checklist de invariantes + saturação formal | — |
| **Red Team B** | **v3 sombras:** staff/live/rifa/tip/payout/storage/device (`REDTEAM_BLIND_B_SURPRESA_v3.md`) | Não re-saturar checkout clássico |
| **TU (C)** | **Profundidade em dinheiro + stock + races + dois caminhos** | Não repetir o inventário genérico do Indep; não caçar “cheira mal” sem Δeconómico |

A tua vantagem de velocidade: **menos superfície, mais profundidade e mais dinheiro real TEST**.

Prioridade única:

> **Em que ponto exacto o estado actual ainda me deixa criar efeito económico líquido indevido, ou consumir a mesma unidade duas vezes?**

Se não for dinheiro / stock / autoridade financeira / cross-user com impacto material → regista como P2/P3 e **volta à caixa**.

--------------------------------------------------
1. AMBIENTE AUTORIZADO (igual aos outros)
--------------------------------------------------
Supabase STAGING: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Podes usar:
- `anon`
- buyer JWT de laboratório
- seller JWT de laboratório
- contas/fixtures descartáveis
- Stripe TEST (criar Session **e pagar** quando o finding exigir captura)

`service_role` **apenas** para:
- preparar fixtures
- observar estado
- consultar evidência
- cleanup

**PROIBIDO** usar `service_role` como actor do exploit.  
Finding de autoridade JWT = reproduzível com privilégios reais do atacante.

--------------------------------------------------
2. CEGUEIRA + ISOLAMENTO PARALELO
--------------------------------------------------
Antes de congelar:

**NÃO consultar:**
- relatórios `AUDITORIA*` / `HARDENING*` / `RETESTE*` / `REAUDITORIA*` / `PRODUCTION_GATE*`
- outputs / drafts / chats do Indep ou do Red Team B
- “o que o outro auditor já achou”

**NÃO:**
- pedir ao C1 a lista de bugs anteriores
- usar baterias históricas como roteiro
- alinhar severidades com outro auditor antes do freeze
- partilhar findings a meio da descoberta

**Podes estudar:**
código actual · migrations · SQL · RLS · triggers · RPCs · Edge · Flutter (só para reconstruir fluxos) · schema LIVE · comportamento LIVE.

**Coordenação mínima (só logística, sem spoiling):**
- fixtures: usa `ref_code` / títulos com prefixo `RTC-` + timestamp para não colidir com Indep/`RTB-`
- cleanup das tuas fixtures no fim
- se um recurso partilhado (buyer/seller de lab) estiver “preso”, cria fixture descartável — não peças estado ao outro auditor

Descobre → ataca → **congela** → só depois (opcional) comparar.

--------------------------------------------------
3. NÃO CORRIGIR
--------------------------------------------------
És auditor. **Não és** implementador.

Não:
- alterar SQL / migrations / Edge / Flutter / RLS / triggers / RPCs
- fazer deploy
- “fechar” o bug

Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
4. MODELO DE ATACANTE
--------------------------------------------------
Obrigatório exercitar, no mínimo:
- A anon · B buyer · C seller · D buyer malicioso · E seller malicioso  
- F **conluio** buyer+seller · G UUIDs alheios válidos · H PostgREST/RPC/Edge sem Flutter

Assume:
- UI ≠ segurança
- todo o campo de cliente é hostil
- retries, concorrência, estados fora de ordem
- buyer e seller podem mentir e colaborar

--------------------------------------------------
5. FOCO PROFUNDO (o teu “atalho” para bugs)
--------------------------------------------------
Não faças Pass 1 de cobertura total tipo Indep.
Faz **três poços** até saturarem ou até P0/P1:

### POÇO 1 — CAIXA (obrigatório, primeiro 40% do tempo)
Rastreia **um** euro TEST do início ao fim em ≥2 caminhos distintos:
- single checkout
- bag / bundle / desconto
- offer / proposal aceite → checkout
- off-platform (MB WAY / transferência / mão) × stock × wallet (sem mint indevido)
- tip / prize / raffle se tocarem dinheiro ou portes
- settle GET / webhook / return (mesma Session, ordem trocada, replay)
- refund / partial / release / dispute → wallet
- payout / Connect / Transfer + retry + keys

Para cada caminho: **contabilidade fechada**  
`captura − refunds − clawbacks ≟ Δwallet/ledger relevante`  
Se não bater → finding ou NÃO COMPROVADO com motivo.

### POÇO 2 — UNIDADE (obrigatório)
Stock=1 e equivalentes:
- 2 orders · 2 Sessions · 2 settles · reserve+checkout · waitlist+accept · live+marketplace  
- estados “quase pago” vs `pago` · holds · `reserva_pendente` vs `reservado`  
- seller marca vendido / envia / cancela enquanto buyer paga  
Race **≥10** nas combinações críticas; verifica **estado final**, não só HTTP.

### POÇO 3 — DOIS CAMINHOS / CONFUSED DEPUTY (obrigatório)
A mesma entidade sob duas autoridades:
- body vs row selada (preço, qty, portes, payment_method, parties)
- Edge A vs Edge B vs RPC vs trigger
- buyer field vs seller field vs metadata Stripe
- order de A + product de B + live de C
- bag multi-line com mutação a meio

Pergunta-guia permanente:

> “Se o Flutter desaparecesse, o que ainda consigo forçar na API com JWT de lab?”

--------------------------------------------------
6. TÁCTICAS RÁPIDAS (checklist de execução, não de cobertura)
--------------------------------------------------
Em cada poço, tenta **explicitamente**:

1. **Pagar TEST de verdade** (4242 / `pm_card_visa`) em ≥1 cenário composto duvidoso.  
2. Distinguir sempre: `SESSION` ≠ `PI` ≠ **captura** ≠ **captura líquida permanente**.  
3. Replay do passo que já teve meio-efeito (settle, refund, payout, accept).  
4. Burst paralelo ≥5 (stock=1, payout, refund, reservation).  
5. Payload: omit / null / `""` / 0 / -1 / float / string numérica / ID cruzado / campo extra.  
6. Mudar catálogo **depois** do contrato (preço, qty, shipping, listagem).  
7. Conluio: seller confirma / cancela / altera enquanto buyer faz checkout.  
8. Off-platform + Stripe na mesma order (ou troca de método a meio).

Não declares “seguro” porque a Session deu 400 uma vez.

--------------------------------------------------
7. SUPERFÍCIES — MÍNIMO OBRIGATÓRIO PARA TI
--------------------------------------------------
Ataca a fundo (não só “tocar”):

`orders` FSM · contract/qty · checkout Edge · settle · webhook · return  
bag · shipping · payment_method · offers · bundles · stock/holds  
wallet/ledger · refunds · release · disputes · payout  
live reservation/accept · raffle/prize se financeiro  
RPCs SECURITY DEFINER com GRANT a `authenticated`/`anon`  
Edges com `verify_jwt=false`

O resto (reviews, chat, storage, Mux, OCR) **só** se:
- abrirem dinheiro/stock/autoridade, **ou**
- fores rápido a enumerar cross-user sensível (P1 privacidade).

Não gastes o Pass 1 em inventário de todas as tabelas — o Indep já cobre largura.

--------------------------------------------------
8. INVARIANTES A REFUTAR (os teus)
--------------------------------------------------
Tenta activamente **partir**:

A. Stripe cobra exactamente o contrato servidor.  
B. Cliente não define preço/qty/portes autoritativos.  
C. release/refund/partial/clawback/payout ≤ fundos legítimos.  
D. 1 unidade física ≠ 2 vendas válidas / 2 capturas líquidas.  
E. JWT ≠ mint wallet / ledger / amount_paid / PI / Session authority / payout.  
F. Off-platform ≠ saldo plataforma sem captura real.  
G. Refund acumulado ≤ captura.  
H. Parties (buyer/seller/product/order) coerentes no ciclo.  
I–J. 1 intenção payout ≤ 1 Transfer; 2 intenções distintas podem ser 2 Transfers.  
K. Catálogo posterior ≠ contrato já aceite.  
L. Offer/bundle/reserva só muda preço/qty com autoridade real.

--------------------------------------------------
9. ANTI-FALSO-POSITIVO (duro)
--------------------------------------------------
HTTP 200 ≠ vuln.  
Campo ecoado ≠ persistência.  
Session criada ≠ dinheiro perdido.  
UI ≠ autoridade.

P0/P1 exigem:
request · identidade · estado antes · resposta · estado depois · impacto · reprodução  
(≥2× ou variante independente quando seguro).

| Claim | Prova mínima |
|-------|----------------|
| Underpay / mint | captura/net ou Δwallet indevido |
| Oversell | 2 consumos económicos permanentes no mesmo stock=1 |
| Autoridade | efeito persistido indevido |
| Race P0/P1 | ≥2 efeitos económicos válidos no mesmo recurso |

Sem prova → **NÃO COMPROVADO** ou desce severidade.

--------------------------------------------------
10. SEVERIDADE
--------------------------------------------------
**P0** — fundos / auth bypass sistémico / underpay com conclusão válida / captura ou payout duplicado líquido crítico.  
**P1** — autoridade indevida material · oversell válido · bypass económico · cross-user relevante · race com impacto · exposição sensível.  
**P2** — hardening / impacto limitado.  
**P3** — higiene.

Não inflacionar.

--------------------------------------------------
11. SATURAÇÃO (versão “poço”)
--------------------------------------------------
SATURAÇÃO = SIM só se:
- Poços 1–3 atacados com evidência;
- ≥1 fluxo com **captura Stripe TEST** real + contabilidade;
- races críticas executadas (≥10 onde couber);
- composição ≥3 combinações distintas tentadas;
- **último** ciclo completo nos 3 poços **sem** nova classe P0/P1;
- lacunas escritas (ex.: não pagaste Session X porque…).

Se o último ciclo achar P0/P1 → **mais um ciclo**.

Não declares PASS só porque o Indep “ainda não falhou”.

--------------------------------------------------
12. CONGELAMENTO + OUTPUT
--------------------------------------------------
**FROZEN_AT** antes de olhar histórico ou outros auditores.

Produzir:
1. Markdown: `REDTEAM_PARALLEL_C_<timestamp>.md` (raiz ou `tool/reports/` — escolhe um e mantém)
2. JSON machine-readable irmão
3. probes/scripts descartáveis usados (`tool/rtc_*.dart` ou similar; não commits obrigatórios)
4. Matriz: SUPERFÍCIE · ATAQUE · IDENTIDADE · RESULTADO · IMPACTO · SEVERIDADE · EVIDÊNCIA
5. Tabela findings: ID · SEV · TÍTULO · ACTOR · PRÉ · REPRO · IMPACTO · ESTADO
6. Checklist final (mesmas 28 perguntas do Indep — responder todas)
7. Veredicto exactamente um: `A FAIL_P0` | `B FAIL_P1` | `C INCONCLUSIVO` | `D PASS_CEGO_SATURADO`

No topo do relatório:

```
AUDITOR: PARALLEL_C_DEEP_CASH
PARALLEL_WITH: INDEP_BLIND + REDTEAM_B
FROZEN_AT: ...
production_touched: false
fase4: false
corrections_applied: false
```

--------------------------------------------------
13. CHECKLIST FINAL (obrigatório — copiar respostas)
--------------------------------------------------
1. P0 aberto: SIM/NÃO  
2. Quantos P0?  
3. P1 aberto: SIM/NÃO  
4. Quantos P1?  
5. Buyer manipula preço autoritativo: SIM/NÃO  
6. Buyer manipula qty autoritativa: SIM/NÃO  
7. Seller falsifica pagamento plataforma: SIM/NÃO  
8. JWT cria saldo/fundos: SIM/NÃO  
9. Refund > captura: SIM/NÃO  
10. Release+refund cria dinheiro líquido: SIM/NÃO  
11. Payout duplica Transfer indevidamente: SIM/NÃO  
12. Stock=1 → duas vendas válidas: SIM/NÃO/NÃO COMPROVADO  
13. Stock=1 → duas capturas líquidas permanentes: SIM/NÃO/NÃO COMPROVADO  
14. Bypass capacidade/reserva: SIM/NÃO  
15. Cross-user financeiro: SIM/NÃO  
16. Cross-user dados sensíveis: SIM/NÃO  
17. Buyer → seller/admin: SIM/NÃO  
18. Seller → buyer/admin: SIM/NÃO  
19. Reviews forjadas/duplicadas: SIM/NÃO (só se atacaste; senão NÃO COMPROVADO + motivo “fora do poço”)  
20. RPC/DEFINER perigoso: SIM/NÃO  
21. RLS crítico quebrado: SIM/NÃO  
22. Edge confia em autoridade do cliente: SIM/NÃO  
23. Conclusão crítica NÃO COMPROVADA: SIM/NÃO  
24. Regressão funcional relevante: SIM/NÃO (não corrigiste código → tipicamente NÃO)  
25. Último passe nova classe P0/P1: SIM/NÃO  
26. Saturação: SIM/NÃO  
27. Produção tocada: **NÃO**  
28. Fase 4 iniciada: **NÃO**

--------------------------------------------------
14. REGRA FINAL
--------------------------------------------------
Não tries provar que o Fleaber é seguro.  
**Tenta provar que não é** — no dinheiro e na unidade.

Não optimizes para bugs conhecidos.  
Não assumes que um fix anterior fecha a classe.  
Não pares no primeiro 400.  
Não implements correcções.

PRODUÇÃO NÃO É TOCADA.  
FASE 4 NÃO É INICIADA.  
NÃO IMPLEMENTAR CORRECÇÕES.
