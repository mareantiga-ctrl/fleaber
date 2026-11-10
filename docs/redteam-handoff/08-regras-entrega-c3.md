# 08 — Regras de entrega do C3

## Formato do ZIP final

Nome sugerido: `NNN-C3-redteam-<slug>.zip`  
Pasta de entrega no repo (quando o dono indicar): tipicamente `00-fleahub-zips/` (convenção Fleaber).

### Conteúdo obrigatório

1. **Relatório executivo** (PT-PT, linguagem de director — sem jargão desnecessário)  
2. **Exame numerado** completo (matriz preenchida)  
3. **Resultados por ID** (PASS / FAIL / AVISO / BLOQUEADO / STOP)  
4. **Provas individuais** por teste (pasta `proofs/RT-xxx/`)  
5. **Passos reproduzíveis** (o que outra pessoa faria amanhã)  
6. **Lista de vulnerabilidades** com severidade e impacto de negócio  
7. **O que não foi testado** e porquê  
8. **Instruções de rollback / mitigação** se aplicável  

### Proibido no ZIP

- Passwords, tokens, API keys, OTP, webhooks secrets  
- Dumps completos de PII (emails reais, moradas, IBAN, telefones completos)  
- Extratos Stripe LIVE / etiquetas com dados pessoais de clientes reais  
- Código de exploit pronto a usar contra PROD sem contexto (preferir descrição + PoC TEST)

## Provas

Cada prova deve incluir:

- ID do teste  
- Data/hora  
- Ambiente (staging / TEST / PROD read-only)  
- Contas usadas (pseudónimos: VendedorA / CompradorB)  
- Print ou resposta HTTP **redigida**  
- Conclusão numa frase  

## Reprodução

Se um FAIL não for reproduzível com os passos do ZIP, classificar **FAIL COM AVISO** e explicar.

## Independência

- Trabalhar em **cópia** do repo / fork privado.  
- Não fazer push para `master` sem pedido.  
- Não misturar commits com branches C2 activas.  
- Primeira entrega pode ser **só documentação + plano**; PoCs depois do GO.
