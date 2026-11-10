# FLEABER — RED TEAM CEGO W
## Auditor independente · CHAT / TIMELINE / PROVAS · v1

> **Poço:** o que o chat e as provas **afirmam** vs o que a BD / Stripe **têm**.  
> Não re-auditar checkout saco (U/V), payout (R), live bag mismatch (Q/T).  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** quando o finding exigir captura / refund.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer · seller · buyer2.  
`service_role` **só** fixture / observação.

Prefixo fixtures: `RTW-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Consigo forjar recibo de pagamento, mentir no chat, ou usar provas/labels para dinheiro ou autoridade?**

Prioridade: **mensagens sistema · order_paid · seguro unpaid · media alheia · disputa proof · cronologia**.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler AUDITORIA/HARDENING/PRODUCTION_GATE nem relatórios J/I/H.

**Podes estudar:** código · RLS `chat_messages` · Edge · storage.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só em:
plain→JSON exact · list `chat_media` público exact · proof_url evil exact ·  
`#https://` exact · seller PATCH `resolvida` exact.

Se ≥50% → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES W (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| W1 | Sistema / kinds | INSERT `order_paid` / `seguro` sem captura |
| W2 | UPDATE imutável | Alterar JSON já gravado; apagar recibo |
| W3 | Thread alheia | Ler/escrever chat ou media de outro par |
| W4 | Provas disputa | Path storage; OCR; proof_url variante nova |
| W5 | Timeline | Ordem cards; inject no fundo; supersede |
| W6 | Cancel / refund no chat | Mentira UI vs Edge refund |
| W7 | Bundle / proposta cards | Preço no card ≠ order |
| W8 | Composição → caixa | Chat mentira → refund / release |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 compra Stripe TEST com chat de encomenda.  
2. ≥1 tentativa INSERT/UPDATE mensagem «sistema».  
3. ≥1 path storage / proof de outro user.  
4. Flutter ≠ fronteira.  
5. Não partir: chat legítimo entre buyer/seller da order.

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
Pasta: `tool/redteam_blind_w_<timestamp>/` · **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_W_CHAT_PROVAS_v1
production_touched: false
fase4: false
VEREDICTO: FAIL_P0 | FAIL_P1 | … | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
