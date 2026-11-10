# FLEABER — RED TEAM CEGO Z
## Auditor independente · PÓS-FECHO VWX · CHAT / PROVAS / UI · v1

> Acabámos de fechar W+VWX chat: JSON imutável (DELETE), `created_at` fixo, totais Seguro, cards alinhados à BD, proof_url INSERT.  
> **Poço:** provar que o chat ainda mente, apaga provas, ou engana UI — sem mint directo.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST se preciso, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** se o finding exigir captura.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: buyer · seller · buyer2.  
`service_role` **só** fixture (simular recibo servidor).

Prefixo fixtures: `RTZ-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos W+VWX chat, ainda consigo forjar recibo, apagar prova, mentir cancelamento/envio, ou injectar URL/prova falsa?**

Prioridade: variantes **novas** — não repetir DELETE order_paid exact W2, total 4321 exact W1, created_at 2020 exact W5.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler AUDITORIA/HARDENING · relatórios W/V/K/J.

**Podes estudar:** triggers chat · RLS · Flutter cards · storage paths.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só em:
DELETE JSON exact · seguro total inventado exact · cancel outcome exact ·  
created_at backdate exact · proof_url INSERT evil exact · bundle 7777 exact.

Se ≥50% → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES Z (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| Z1 | Recibos / totais | Outro kind ou campo mente valor? |
| Z2 | Imutabilidade | UPDATE/DELETE bypass? plain text gaps? |
| Z3 | Cronologia | Reorder sem created_at? outro campo? |
| Z4 | URLs / provas | proof_url, dispute photos, chat_image, storage |
| Z5 | Cards operacionais | Envio/concluído/disputa sem BD |
| Z6 | Inbox / preview | last_message, snippets |
| Z7 | 2.º actor | B2 lê/forja thread alheia? |
| Z8 | Composição → caixa | Chat mente **e** Edge obedece? (deve ser NÃO) |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 order Stripe TEST capturada + thread chat.  
2. Provar UI mente **e** BD/Edge não (W8).  
3. REST/RPC ≠ Flutter.  
4. Não partir chat legítimo buyer/seller.

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_z_<timestamp>/` · **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_Z_CHAT_POS_W_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [Z1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

**`## CONTAGEM`** (obrigatória):

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
```

**`## CHECKLIST`** (28 linhas — igual Y; preencher todos).

P0 chat = apagar prova servidor / mint dinheiro via mensagem.  
P1 = UI/autoridade mente com prova.  
P2/P3 = hygiene (NBSP, preview, órfãos).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
