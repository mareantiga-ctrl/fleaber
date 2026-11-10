## CONTAGEM — formato obrigatório no FROZEN_REPORT (auditor cego)

**Sem este bloco no topo o relatório é INVÁLIDO.**  
Tens de escrever **números** (0, 1, 2…) em cada linha — não «vários», não omitir P0/P1/P2/P3.

O agente de fecho **só** consegue fechar se vir isto no **primeiro ecrã** do relatório. Se faltar → **rejeitar e pedir reenvio** antes de qualquer fix.

No **topo** do relatório, **antes** de findings, copiar exactamente:

```
## CONTAGEM

P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: N
```

### Checklist de números (também no topo — preencher)

```
1. P0 dinheiro irreversível encontrado? SIM | NÃO
2. Quantos P0: N
3. P1 caminho explorável encontrado? SIM | NÃO
4. Quantos P1: N
5. P2 hygiene encontrado? SIM | NÃO
6. Quantos P2: N
7. P3 baixo risco encontrado? SIM | NÃO
8. Quantos P3: N
```

Os `quantos` das linhas 2/4/6/8 **têm de bater** com o bloco CONTAGEM e com o TOTAL.

### Regras (rejeitar relatório se falhar)

1. `quantos` é **número inteiro** (0, 1, 2…), nunca «vários» / «alguns» / «muitos».
2. `TOTAL P0–P3 abertos` = soma **exacta** dos quatro `quantos` P0+P1+P2+P3 (P4 não conta).
3. Linha `TOTAL P0–P3 abertos: N` é **obrigatória** — sem ela o relatório é **inválido**.
4. Se `P1 aberto: SIM → quantos: 2`, o TOTAL tem de incluir esses 2.
5. Se 0 abertos em P0–P2 e só P3 → VEREDICTO pode ser `PASS_CEGO_SATURADO` **só** se o prompt disser que P3 está fora; senão `FAIL_P3`.
6. Sem bloco CONTAGEM completo → relatório **inválido** (rejeitar e pedir reenvio).
7. O agente de fecho **começa sempre** por colar a CONTAGEM + TOTAL no chat — se o relatório não tiver números claros, pedir reenvio **antes** de corrigir.
8. Cada finding aberto tem de ter ID (`P0-1`, `P1-1`…) e a soma dos IDs por severidade = `quantos`.
9. No **fim** do FROZEN, repetir uma linha: `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`.

### Exemplo válido

```
## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 2
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 3

1. P0? NÃO
2. Quantos P0: 0
3. P1? SIM
4. Quantos P1: 2
5. P2? SIM
6. Quantos P2: 1
7. P3? NÃO
8. Quantos P3: 0

RESUMO_NUMERICO: P0=0 P1=2 P2=1 P3=0 TOTAL=3
```
