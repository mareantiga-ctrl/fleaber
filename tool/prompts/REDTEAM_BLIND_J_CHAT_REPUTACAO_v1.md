# FLEABER — RED TEAM CEGO J
## Auditor independente · CHAT / REPUTAÇÃO / MEDIA / DEEP LINK · v1

> **Terceira onda** — superfície social e mensagens, não o checkout clássico.  
> Chat cards, reviews, storage, deep links Hub, notificações forjadas.  
> Mesmas regras: staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, não corrigir.

--------------------------------------------------
AMBIENTE
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST se o finding exigir captura.  
Produção proibida · Fase 4 não.  
Prefixo: `RTJ-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Consigo mentir no chat, forjar reputação, ler media alheia, ou usar um link/notificação para abrir autoridade ou dinheiro que não é meu?**

Não re-provar: Hub paused items, reviews buyer_id (acabado de fechar), FLEABER_JSON_V1 update clássico se já HOLD no D, invite enum.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
≥50% = classes fechadas recentes (cancel hold, Hub paused, offer morto, pairing ended) → `ATROFIA_ABORT`.

--------------------------------------------------
LENTES J (≥4)
--------------------------------------------------
| # | Lente |
|---|--------|
| J1 | Chat card / timeline forge (INSERT/UPDATE hostil) |
| J2 | Review forge / dupla / role errado pós-policy 6-A |
| J3 | Storage buckets (chat-media, private) cross-user |
| J4 | Deep link / Hub handle / notificação → acção indevida |
| J5 | Notificação INSERT JWT / ler alheias |
| J6 | Favoritos / follows hijack pós-unlist |
| J7 | Composição J*→caixa (ex. card «pago» falso → refund UI) |

--------------------------------------------------
ENTREGA
--------------------------------------------------
`tool/redteam_blind_j_<timestamp>/FROZEN_REPORT.md`

```
AUDITOR: REDTEAM_BLIND_J_CHAT_REPUTACAO_v1
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | PASS_CEGO_SATURADO | ATROFIA_ABORT
production_touched: false
fase4: false
corrections_applied: false
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
