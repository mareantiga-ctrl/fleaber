# FLEABER — RED TEAM CEGO M
## Auditor independente · HUB WEB / EDGE / DEEP LINK / CONNECT ORIGEM · v1

> Superfície **fora da app nativa**: Hub público, Edge Functions, origins, deep links, AccountLink.  
> Não re-auditar checkout JWT clássico nem HIJ dinheiro/chat (K faz isso).  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 não.  
Prefixo: `RTM-<timestamp>-`.  
Anon + JWT + origins hostis em headers/`web_return_origin`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Pela web / Edge / link, consigo dinheiro, stock, autoridade ou dados que a app esconde?**

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR
--------------------------------------------------
Não ler HARDENING como roteiro. Não corrigir. Provar → documentar.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Não Pass 1 em: Hub paused items (já 1-A), invite enum, pairing ended, dual Session, mint pós-payout, plain→JSON.  
≥50% = essas → `ATROFIA_ABORT`.

--------------------------------------------------
LENTES M (≥4)
--------------------------------------------------
| # | Lente |
|---|--------|
| M1 | Hub views / FOMO / handle resolve (anon) — leak além do publicado |
| M2 | Edge `web_return_origin` / CORS / Connect return → domínio evil |
| M3 | Deep link / settle GET com `session_id` alheio ou forjado |
| M4 | Edge body spoof (`buyer_id`, `amount`, `tip_id`, `user_id`) |
| M5 | Mux/LiveKit create/complete cross-user |
| M6 | Storage público vs privado (não chat_uploads J) |
| M7 | Composição M*→Session/captura |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. Anon Hub exercitado.  
2. ≥2 Edges com body/origin hostil.  
3. ≥1 tentativa settle/checkout com id alheio.  
4. Distinguir SESSION criada ≠ captura.  
5. Flutter ≠ fronteira.

--------------------------------------------------
ENTREGA
--------------------------------------------------
`tool/redteam_blind_m_<timestamp>/FROZEN_REPORT.md`

```
AUDITOR: REDTEAM_BLIND_M_HUB_EDGE_v1
FROZEN_AT: ...
production_touched: false
fase4: false
corrections_applied: false
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Por finding: ID · lente · actor · passos · esperado vs obtido · prova · severidade.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
