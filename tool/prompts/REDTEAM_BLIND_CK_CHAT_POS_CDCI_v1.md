# FLEABER — RED TEAM CEGO CK · DEEP v2 · PÓS-FECHO CDCI
## Chat / provas / inbox — **quota ≥24 rails + ≥8 paths**

> Staging · TEST · **NÃO CORRIGIR**.  
> CE (ronda anterior) aprofundou; **este pack exige o mesmo nível** (lista obrigatória, não “amostra”).

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

Prefixo `RTCK-<timestamp>-` · `tool/redteam_blind_ck_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** com **≥32 linhas** (≥24 rails/copy + ≥8 path/encoding + inbox/storage).
2. **Cada** string da lista CK-A abaixo = 1 linha (card notes **e**, se aplicável, seguro/inbox).
3. Controlo residual CDCI (Skrill/WeChat) = máx 2 linhas — não ≥50%.
4. Sem quota → **`INCONCLUSIVO`**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Mentir rail / path / inbox `last_message` fora do denylist CDCI exacto?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
WeChat/UPI/MB-WAY/cashtag/Skrill/Neteller/`%252e`/NFKC exactos — residual só.  
≥50% residual → `ATROFIA_ABORT`.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA CK-A — ≥24 STRINGS (todas)
--------------------------------------------------
Testar **todas** (card `reservation_payment_submitted` notes; marcar 201 vs forbidden):

1. PaysafeCash 12,00 €  
2. PaySafe cash código loja  
3. Pix Copia e Cola (payload EMV curto)  
4. chave pix aleatória CPF  
5. PicPay 12,00 €  
6. MB WAY QR / lê este QR MBWay  
7. SEPA Instant / SCT Inst  
8. IBAN + enviado instantâneo 12 €  
9. Revolut . Me 12,00 €  
10. revolut․me (dot U+2024)  
11. rev0lut.me 12 €  
12. Apple Cash 12,00 €  
13. Apple Pay Cash  
14. tap to cash / NFC prova  
15. Google Pay send money  
16. Samsung Pay transfer  
17. money order / cashier check  
18. Vanilla gift card  
19. PaySafe card PIN (variante ≠ Paysafecard residual)  
20. «comprovativo MB WAY QR»  
21. «transferência imediata SEPA»  
22. «enviei por RevolutMe» (sem espaço)  
23. «\$Cash App Pay» spaced novo  
24. «Wise tag @user» / «pay.wise»  
25. (+2 à escolha: IT bonifico / DE Überweisung) — total ≥24

**CK-B paths ≥8:** `%u002f` · `%255c` · UTF-16LE `%ff%fe%2e` · mixed `%252f%255c` · `‥` residual controlo · `%c1%9c` · null `%00` · soft-hyphen dots  
**CK-C:** inbox PATCH `last_message` só com ≥4 rails novos; storage list/upload alheio ≥2  
**CK-D:** composição card→PATCH pago ≥1

--------------------------------------------------
## LENTES ≥6/8
--------------------------------------------------
CK1 cards · CK2 encoding · CK3 cronologia · CK4 URLs · CK5 inbox · CK6 storage · CK7 cross-user · CK8 Edge

```
AUDITOR: REDTEAM_BLIND_CK_CHAT_POS_CDCI_v1
probes_na_tabela: N (≥32)
VEREDICTO: …
```
**NÃO CORRIGIR.**
