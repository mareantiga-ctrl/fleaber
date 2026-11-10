# 06 — Testes seguros (TEST) e limites

## Objectivo desta fase para o C3

Primeiro: **compreender** e montar o exame numerado.  
Depois (com GO): testes de segurança em **TEST**, sem custos reais.

## Ambientes

| Nome | Ref / alvo | Permitido inicialmente |
|------|------------|------------------------|
| Staging Supabase | `fxdknzrqjenzqcvnwqqq` | Preferível para experimentação Auth/SMS histórico |
| Produção Supabase | `bpmpkzwnrbmuqnhgdscf` | **Só leitura** / smoke sem escrita destrutiva até GO |
| Stripe | chaves **TEST** | Contas Connect teste, PaymentIntents teste |
| DPD | `qabusiness.dpd.pt` (QA) | Só se GO create QA; PROD create **nunca** sem GO escrito |
| Hub / APK | builds TEST ou contas teste | Sem dados pessoais reais de clientes |

## Contas

- Usar apenas contas de teste autorizadas pelo dono do produto.
- Não criar contas com nomes/emails do utilizador real.
- Não exportar PII de produção para o ZIP C3.

## STOP absoluto (sem GO escrito)

1. Pagamentos LIVE / KYC pessoal / levantamentos reais  
2. `OPS_STRIPE_LIVE_PILOT_MONEY_GO=1` ou qualquer cobrança real  
3. Expedições / recolhas / fecho do dia / etiquetas DPD **PROD**  
4. SMS BulkGate pagos (`OPS_SMS_SEND_ENABLED=1` + hook) sem autorização  
5. Apagar dados de produção, reset de projecto, `delete-test-account` em massa  
6. Deixar lives `is_active=true` abertas (custo LiveKit/Mux)  
7. Alterar código C2 (Amazon / Moloni / overlay)  
8. Publicar secrets no Git, ZIP ou chat  
9. Fuzzing / exploração ofensiva em PROD na primeira sessão  

## GO típicos (exemplos — só o dono activa)

| GO | Efeito |
|----|--------|
| GO SMS teste | 1 SMS controlado, número mascarado, custo estimado |
| GO DPD QA create | Etiqueta QA (já feito historicamente no ZIP 184) |
| GO DPD PROD create | 1 guia real — fora do âmbito C3 inicial |
| GO Red Team TEST | Exame numerado + PoCs em staging/TEST |
| GO Red Team PROD read-only | Auditoria RLS/logs sem escrita |

## Como o C3 deve estruturar um teste seguro

1. Hipótese em linguagem simples  
2. Conta A vs conta B (isolamento)  
3. Passos reproduzíveis  
4. Esperado vs observado  
5. Prova (print / resposta HTTP **sem** tokens / query BD só campos não sensíveis)  
6. Classificação: PASS / FAIL / PASS COM AVISO / BLOQUEADO / STOP  

## Browser / devices

- Não usar Chrome/Opera pessoal do dono sem autorização.  
- Preferir browser isolado / emulador / contas teste.  
- Vendedor TCL / comprador Redmi ou Chrome — convenção QA Fleaber.
