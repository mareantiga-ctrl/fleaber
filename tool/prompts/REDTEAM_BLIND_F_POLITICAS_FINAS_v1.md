# FLEABER — RED TEAM CEGO F
## Auditor independente · POLÍTICAS FINAS / RLS ∩ FSM · v1

> **Substitui** a auditoria Indep «checklist A–L larga» saturada (ex. 1752 PASS sem P0/P1).  
> **Não** re-auditar freeze 1442. **Não** repetir E6/E4 já no anti-objectivo após fecho.  
> Mesmas regras duras: staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, não corrigir, P0–P3 com prova.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Onde duas políticas “correctas” se cruzam (RLS ∩ trigger ∩ Edge ∩ view) e o cruzamento ainda deixa comprar, ler ou aceitar o que a UI esconde?**

Prioridade: intersecções finas — não inventário de 178 RPCs.

Prefixo fixtures: `RTF-<timestamp>-`.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 em: dual Session, offer amount, carrier concluido, disputa seller close,
OCR kick, tip sem live, email enum rate-limited, admin resolve fail-closed,
**produto is_sold/unlist** (E6 — se ainda aberto, 1 repro máximo e segue),
**bundle self-accept** (E4 — idem).

Se ≥50% findings = classes acima → `ATROFIA_ABORT`.

--------------------------------------------------
LENTES F
--------------------------------------------------
| F1 | Policy OR shadow | Uma policy larga anula outra apertada? |
| F2 | View vs base | View limpa mas base JWT lê o resto? |
| F3 | Trigger silent vs raise | 200 [] vs exception — falso OK? |
| F4 | Edge vs BD | Edge bloqueia mas INSERT directo passa (ou o contrário)? |
| F5 | Partial unique / TTL | Expirou na BD mas token ainda válido? |
| F6 | Multi-seller bag residual | |
| F7 | Helper permission mínima | Permissão X implica Y sem querer? |
| F8 | Composição F*→caixa | |

≥4 lentes; último ciclo sem nova classe P0/P1.

--------------------------------------------------
ENTREGA
--------------------------------------------------
```
AUDITOR: REDTEAM_BLIND_F_POLITICAS_FINAS_v1
...
VEREDICTO: FAIL_P0 | FAIL_P1 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

`tool/redteam_blind_f_<timestamp>/FROZEN_REPORT.md`

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
