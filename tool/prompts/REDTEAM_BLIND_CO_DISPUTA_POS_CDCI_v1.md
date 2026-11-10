# FLEABER — RED TEAM CEGO CO · DEEP v2 · PÓS-FECHO CDCI
## Disputa / envio / label / carrier — **quota ≥16 paths + FSM**

> Staging · TEST · **NÃO CORRIGIR**.  
> CI trouxe 1 P2 — **agora matriz path ≥16 + label + carrier + stock**.

--------------------------------------------------
## CONTAGEM (topo — INVÁLIDO sem TOTAL)
--------------------------------------------------
```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N
1. P0? SIM|NÃO  2. Quantos P0: N
3. P1? SIM|NÃO  4. Quantos P1: N
5. P2? SIM|NÃO  6. Quantos P2: N
7. P3? SIM|NÃO  8. Quantos P3: N
```

Prefixo `RTCO-<timestamp>-` · `tool/redteam_blind_co_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS` ≥28 linhas**.
2. **≥16** path/proof/label encoding (CO-A/B).
3. **≥4** FSM disputa/devolução · **≥4** refund/stock/release · **≥2** carrier/B2.
4. Controlo residual CDCI (triple `%25252e`, ZWSP) ≤3.
5. **≥1** cadeia Stripe refund ou stock medido.
6. Sem quota → **`INCONCLUSIVO`**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Path `%255c`/mixed, label URL, carrier spoof, stock×2 — além canónico CDCI?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
triple-encode / `%u` / UTF8-slash / ZWSP / bidi / `%252e`. Residual só.

--------------------------------------------------
## MATRIZ CO-A — ≥12 path proofs
--------------------------------------------------
1 `%255c`  
2 `%255c..%255c`  
3 mixed `%252f`+`%255c`  
4 `%u005c`  
5 `%c0%af`+`%255c`  
6 Windows `..\` URL-encoded  
7 `%00` filename  
8 `\n` / `\r` path  
9 SVG/HTML Content-Type como foto  
10 bucket swap  
11 prova order B em disputa A  
12 overwrite buyer/seller  

### CO-B Label URL ≥4
label `%255c` · label host evil · label relative · label double-encode novo  

### CO-C FSM ≥4
2.ª disputa · partial qty · `devolvida` cedo · seller `pedido_devolucao`  

### CO-D Refund/stock ≥4
amount body · restore×2 · release∥disputa · buyer refund Seguro  

### CO-E Carrier/B2 ≥2
webhook carrier sem sig / event antigo · B2 INSERT disputa A  

--------------------------------------------------
## LENTES ≥6/8
--------------------------------------------------
CO1 pedido_devolucao · CO2 FSM · CO3 provas · CO4 refund · CO5 stock · CO6 release · CO7 2.º actor · CO8 caixa

```
AUDITOR: REDTEAM_BLIND_CO_DISPUTA_POS_CDCI_v1
probes_na_tabela: N (≥28)
VEREDICTO: …
```
**NÃO CORRIGIR.**
