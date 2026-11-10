# FLEABER — RED TEAM CEGO AC
## Auditor independente · PÓS-FECHO YZAA · CHAT / PROVAS / UI · v1

> Fechámos Z (ronda 20260901T1715): JSON cru bloqueado, cards alinhados à BD (MB WAY, disputa, cancel, review, outcome), `proof_url` allowlist sempre, inbox preview, chat_image path/url, storage sem upsert.  
> **Poço:** refutar — provar que o chat ainda mente, apaga provas, ou injecta URL falsa — sem mint directo.  
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

Prefixo fixtures: `RTAC-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos YZAA chat, ainda consigo forjar recibo, mentir MB WAY/disputa/cancel/review, ou injectar URL/prova falsa?**

Prioridade: variantes **novas** — não repetir amount_eur mentiroso exact Z1-DIRECT, JSON cru exact Z1-BUNDLE-RAW, proof_url javascript exact Z4, inbox forge exact Z6.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler AUDITORIA/HARDENING · relatórios Z/Y/AA/W/V.

**Podes estudar:** triggers chat · RLS · Flutter cards · storage paths.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só em:
amount_eur lie exact · raw JSON exact · proof_url javascript exact ·  
dispute card sem disputa exact · cancel card em pago exact · inbox forge exact ·  
chat_image evil https exact · storage upsert exact.

Se ≥50% → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES AC (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| AC1 | Cards vs BD | Outro kind que mente sem cruzar tabela? |
| AC2 | Prefixo / encoding | Bypass FLEABER_JSON_V1 (unicode, whitespace, nested)? |
| AC3 | Cronologia | Prazo/timeline forjável? |
| AC4 | URLs / provas | XSS, open redirect, path traversal novo? |
| AC5 | Inbox / delete | Preview ou apagar cards? |
| AC6 | Storage | Upsert/substituir comprovativo? |
| AC7 | Cross-user | B2 vê thread alheia? |
| AC8 | Edge vs chat | Chat mente mas Edge obedece? (controlo) |

--------------------------------------------------
CONGELAMENTO · CHECKLIST OBRIGATÓRIO
--------------------------------------------------
Pasta: `tool/redteam_blind_ac_<timestamp>/` · **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_AC_POS_YZAA_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AC1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Secção **`## CONTAGEM`** (obrigatória):

```
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
```

Secção **`## CHECKLIST`** (28 linhas — copiar modelo Z).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
