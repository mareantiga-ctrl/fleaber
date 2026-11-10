# FLEABER — RED TEAM CEGO S
## Auditor independente · IDENTIDADE / STAFF / MULTI-CONTA · v1

> **Poço:** quem és na API — perfis, admin, staff, multi-conta, enumeração, PII.  
> Não re-auditar checkout nem live player UI.  
> Staging `fxdknzrqjenzqcvnwqqq`, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe TEST só se o finding exigir pagamento.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer · seller · buyer2 · seller2 · contas novas se necessário.  
`service_role` **só** fixture — **nunca** actor do exploit.

Prefixo fixtures: `RTS-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Consigo ler ou alterar dados de outro utilizador, passar-me por staff/admin, ou ligar duas contas para benefício financeiro?**

Prioridade: **RLS profiles · admin RPCs · storage paths · chat/media · invite/pairing · reviews**.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler:
`AUDITORIA*` · `HARDENING*` · `PRODUCTION_GATE*` · relatórios H/G.

**Podes estudar:** código · RLS · policies storage · `batata_is_admin` · Flutter auth.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só em:
email→UUID enum clássico · `chat_media` list público · invite 6 dígitos brute (sem variante) ·  
profiles SELECT anónimo (se já bloqueado em LIVE — provar variante).

Se ≥50% = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES S (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| S1 | Profiles PII | Ler email/telefone/NIF de outro user? |
| S2 | Admin boundary | JWT normal chama RPC/trigger admin? |
| S3 | Storage paths | Ler `proof_photos` / chat media de thread alheia? |
| S4 | Multi-conta | Buyer+seller mesma pessoa — rifa, review, disputa? |
| S5 | Reviews / reputação | UPDATE review alheia; DELETE→5★ release |
| S6 | Pairing / director | Tokens lab no binário vs RLS staging |
| S7 | Orders cross-user | Ver encomendas/chat de outro por ID leak |
| S8 | Composição S*→caixa | Identidade → autoridade → dinheiro |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥1 prova com **dois UUIDs reais** (não só anon).  
2. Tentar PATCH/INSERT em tabelas com `user_id` alheio.  
3. ≥1 storage URL/path de outro utilizador.  
4. Flutter ≠ fronteira.  
5. Não partir: login legítimo; perfil próprio editável.

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
Pasta: `tool/redteam_blind_s_<timestamp>/` · **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1
VEREDICTO: FAIL_P0 | FAIL_P1 | … | PASS_CEGO_SATURADO | ATROFIA_ABORT
production_touched: false
fase4: false
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
