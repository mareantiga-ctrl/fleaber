# FLEABER — RED TEAM CEGO O
## Auditor independente · DISPUTA / ENVIO / DEVOLUÇÃO PÓS-PAGO · v1

> **Terceira onda** depois de K/L/M fechados.  
> **Poço:** o que acontece **depois de pago** — envio, disputa, devolução, stock a voltar, reembolso no meio do caos.  
> Não re-auditar checkout JWT clássico, cron L, Hub/Edge M, HIJ K.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente (Session **e** pagar 4242 quando o finding exigir captura / Transfer / refund).  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · 2.º seller · conluio.  
`service_role` **só** fixture / observação / cleanup — **nunca** actor do exploit.

Prefixo fixtures: `RTO-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
És Red Team cego independente.

Pergunta única:

> **Depois de pago, consigo (com envio, disputa, devolução ou reembolso no meio) dinheiro, stock, autoridade ou um estado que a UI esconde?**

Prioridade: **FSM pós-pago · disputa ∩ envio · stock restore · refund residual · races enviado∥disputa∥receção**.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler:
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `REAUDITORIA*` · `PRODUCTION_GATE*`  
relatórios / freezes K/L/M/J/I/H/G/F/D · “o que já foi corrigido”.

**Podes estudar:** código actual · SQL · RLS · triggers · RPCs · Edge · Flutter (só fluxos) · schema LIVE · comportamento LIVE · Stripe TEST dashboard.

Descobre **por ti**. Congela. Só depois (opcional) comparar.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Não alterar SQL / migrations / Edge / Flutter / RLS / triggers / RPCs.  
Não fazer deploy.  
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 a redescobrir e parar em:
dual Session · bag unlist · seguro plain · list `chat_media` · resolve handle unpublished ·  
DELETE review→5★ · TTL resurrect · CORS `*.fleaber.pt` · mux draft ·  
mint pós-payout · pairing ended · Hub paused · cancel hold · helper escalate · invite enum ·  
seller PATCH disputa `resolvida` clássico · chat UPDATE `FLEABER_JSON_V1` ·  
`pago`→`concluido` carrier sem enviado · OCR kick storage 1442.

Se ≥50% findings = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES O (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta-guia |
|---|--------|----------------|
| O1 | **Disputa vs FSM** | Abrir / fechar / reabrir disputa em `pago` / `enviado` / `concluido` / `cancelada` — JWT alheio? |
| O2 | **Enviado ∥ disputa** | Seller marca `enviado` com disputa aberta; buyer abre disputa depois de enviado; tracking forjado |
| O3 | **Devolução / stock** | `pedido_devolucao` · restore de stock · item volta à venda sem refund / com refund duplo |
| O4 | **Refund no caos** | Refund Stripe a meio de envio; parcial; buyer2; seller após release; residual PI |
| O5 | **Receção ∩ disputa** | Buyer `concluido` com disputa aberta; seller força receção; mão vs carrier |
| O6 | **Etiqueta / carrier** | Label sem captura; tracking alheio; `enviado` sem portes pagos; carrier lixo → estado |
| O7 | **Evidência disputa** | Upload / path / OCR / storage de prova — ler ou escrever alheio (não re-provar 1442 kick) |
| O8 | **Composição O*→caixa** | Encadear 2+ lentes até Δwallet, stock, Stripe net ou autoridade |

Último ciclo sem nova classe P0/P1 → saturação O (não PASS global da app).

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥1 fluxo Stripe TEST **pago** até envio **e/ou** disputa/devolução.  
2. Contabilidade fechada: buyer wallet · seller wallet · stock · PI · `stripe_refund_id` · status order.  
3. ≥1 race real (`Future.wait`) com verbos diferentes (ex. `enviado`∥abrir disputa; refund∥`concluido`).  
4. 2.º buyer e/ou 2.º seller no mesmo objecto.  
5. Flutter ≠ fronteira — REST/RPC/Edge.  
6. Não partir: confirmação mão **legítima**; seller `enviado` carrier correcto.

--------------------------------------------------
ANTI-FALSO-POSITIVO · SEVERIDADE
--------------------------------------------------
- **SESSION ≠ captura ≠ Transfer ≠ net na carteira.**  
- HTTP 200 / “pending” sem efeito final ≠ P0.  
- UI esconde mas API permite **com efeito** = finding.  
- UI esconde e API bloqueia = não é finding.  
- P0: dinheiro/stock/autoridade irreversível ou roubo claro.  
- P1: caminho explorável a dinheiro/stock/dados sensíveis com prova.  
- P2: informação / enumeração / UX de segurança sem loot directo.  
- P3: hygiene / inconsistência sem impacto.

--------------------------------------------------
CONGELAMENTO · ENTREGA
--------------------------------------------------
Pasta: `tool/redteam_blind_o_<timestamp>/`  
Ficheiro obrigatório: **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_O_DISPUTA_ENVIO_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [O1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Por finding: ID · lente · actor · passos · esperado vs obtido · prova (IDs, montantes, timestamps) · severidade.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
