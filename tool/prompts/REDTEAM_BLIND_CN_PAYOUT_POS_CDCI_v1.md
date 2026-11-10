# FLEABER — RED TEAM CEGO CN · DEEP v2 · PÓS-FECHO CDCI
## Payout / wallet / refund — **quota ≥16 keys + Transfer TEST**

> Staging · TEST · **NÃO CORRIGIR**.  
> CH trouxe 2 P2; matriz curta — **agora ≥16 keys + races + release**.

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

Prefixo `RTCN-<timestamp>-` · `tool/redteam_blind_cn_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS` ≥24 linhas**.
2. **≥16** pares/keys idempotency (CN-A) com resultado Stripe (1 vs 2 `tr_`).
3. **≥1** Transfer/payout Stripe TEST real (não só 400).
4. **≥1** release∥refund race · **≥1** destination/amount hostil · **≥1** buyer refund 403.
5. Controlo residual CDCI (arménio/grego/I vs i) ≤3.
6. Sem quota → **`INCONCLUSIVO`**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> 2 Transfers / mint / refund>captura / release pós-partial — além fold CDCI?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Armenian/Georgian/İ/υ/toLowerCase · Greek α/ο/ρ · Cyrillic. Residual só.

--------------------------------------------------
## MATRIZ CN-A — ≥16 keys (pares Latin vs lookalike)
--------------------------------------------------
Documentar cada POST amount=100 (ou mínimo wallet) + `idempotency_key`:

**Coptic (≥4 pares → 8 posts):** ⲟ vs o · ⲁ vs a · ⲣ vs p · ⲉ vs e  
**Cherokee (≥2 pares):** Ꮎ vs o · Ꭺ vs A  
**Length (≥4):** max−1 · max · max+1 · empty/ZWSP  
**Paralelo (≥2):** Future.wait key≡fold · key≠fold  

### CN-B Transfer/amount ≥4
destination alheio · amount array · payout>saldo · currency mismatch  

### CN-C Webhook/crash ≥2
sig inválida · crash_inject retry (se secret staging)

### CN-D Release/refund ≥4
release∥refund · partial refund→release · buyer refund 403 · seller2 refund alheio

--------------------------------------------------
## LENTES ≥5/7
--------------------------------------------------
CN1 Connect · CN2 return · CN3 release+refund · CN4 Transfer · CN5 FSM · CN6 actor · CN7 Δwallet

```
AUDITOR: REDTEAM_BLIND_CN_PAYOUT_POS_CDCI_v1
probes_na_tabela: N (≥24)
VEREDICTO: …
```
**NÃO CORRIGIR.** Seller-only refund: reportar só se abriu.
