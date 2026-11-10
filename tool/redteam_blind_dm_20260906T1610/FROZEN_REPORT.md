# FROZEN_REPORT — RED TEAM CEGO DM · Cross-surface composição · POS_DBDG

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 1

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DM_CROSS_SURFACE_POS_DBDG_v1
FROZEN_AT: 2026-09-06T16:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DM1, DM2, DM3, DM4, DM5, DM6, DM7]
probes_na_tabela: 16
stripe_test_pago: true
VEREDICTO: FAIL_P2
prefix: RTDM-20260906T1610
staging: fxdknzrqjenzqcvnwqqq
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded`, vários `pi_3UCh*`) · actores JWT B1/S1/B2/S2 · `service_role` só fixture / observação / restore. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` republicado no pass2 via RPC `batata_publish_hub(true)` (`hub_published=true` à saída). Lives de fixture `status=ended`. Pass1 D3 HOLD **retractado** (a corrida não chegou a correr).

--------------------------------------------------
## P2-1 — Reserva live aceite: Hub ainda mostra o artigo; o checkout recusa
--------------------------------------------------

**O que isto é:** o mesmo stock tem de dizer a mesma coisa na vitrine do Hub, no directo e no pagamento. Se o vendedor já aceitou a reserva no directo, o Hub não pode continuar a mostrar o artigo como comprável — ou o pagamento tinha de deixar comprar (e aí seria oversell).

**Quem / onde:** Vendedor S1 (TCL/demo) · Comprador B1 Hub/checkout · Comprador B2 reserva live. SKU `a89de08c-…` «RTDM-20260906T1610 B1 hitch-bag».

**O que fizemos:** artigo qty=1 listado no marketplace e atrelado ao directo. B2 pediu reserva; S1 aceitou. Em paralelo B1 tentou pagar o saco. Pass2 (loja outra vez publicada, directo já encerrado): Hub público + tentativa de nova encomenda.

**Esperado vs resultado**
- Directo / reservas: aceite `48230d14-…` requested_qty=1 → visto **accepted**
- Pagamento (CPI / nova encomenda): esperado recusa da última unidade → visto **400** `order_hold_exceeds_stock` (pass1 saco: `quantity 1 exceeds available stock 0`)
- Produto na base: qty ainda **1**, `is_sold=false`, `list_on_marketplace=true`
- Hub (anon e comprador): esperado ocultar **ou** alinhar com o checkout → visto **1 linha** (`hub_products_public` 200 com o SKU)
- Oversell pago: **não** — o segundo comprador não abre Session

**Conclusão:** **P2** — higiene de composição, não P0/P1. O cadeado de stock no pagamento segura; a vitrine Hub (e a coluna `quantity`) não reflectem a reserva live aceite, mesmo com o directo já `ended`. Quem entra pelo Hub vê um artigo que o checkout recusa.
**Prova:** `pass1.json` B1 + `pass2.json` B1r / finding `P2-B1-HUB-HOLD`.

--------------------------------------------------
## TABELA DE PROVAS (16)
--------------------------------------------------

| probe_id | superfícies tocadas | acção | HTTP | oráculos multi-sítio | HOLD\|FAIL\|SKIP |
|----------|---------------------|-------|------|----------------------|------------------|
| A1 | Hub + CPI + tip + follows | unpublish a meio do checkout e da gorjeta + follow | CPI 200 `cs_test_a1sRwl7E…`; unpub RPC 200; follow 403; tip GET unpaid | Hub mid `hub_published=false` n=0 anon/JWT; tip `pending`; S1 restaurado `true`; CPI ainda `cs_` (Session já aberta) | FAIL |
| A2 | Hub vitrine + follows + favorites | follow+favorite published vs `hub_products_public` após unpublish | fav 201; Hub after n=0; fav unpublished 403 | vitrine published 1 linha; unpublished 0; fav deny | FAIL (feliz / residual published — **não conta**) |
| A3 | Hub + products + CPI | `is_sold=true` vs vitrine vs checkout | Hub 200 []; insertOrder 400 `order_hold_exceeds_stock` | prod sold+listed; Hub 0; sem `cs_` | FAIL |
| B1 | live hitch + bag + products | Future.wait saco CPI ∥ accept live qty=1 | bag 400 stock 0; accept 200 accepted | live accepted; qty coluna=1; sem 2.ª Session | FAIL (oversell bloqueado; ver B1r) |
| B2 | live_item + products + Hub + CPI | qty=0 listed vs live sold | Hub 200 []; insert 400 | qty=0 `is_sold=false`; Hub 0 (pass2 com loja publicada) | FAIL |
| B3 | order + product + live_item | refund após pago Stripe + hitch | refund 200 `cancelado` `re_3UChpRH7…` PI `pi_3UChpRH7…` | qty 1→2; live_item `available`; sem restore ×2 | FAIL |
| C1 | orders + chat + wallets + Hub | pago Stripe TEST → 3 sítios | e2e 200 `pi_3UChpZH7…` succeeded 590¢ | status `pago` qty 2→1; Δwallet 0/0; chat 0 (e2e); Hub n=0 no pass1 porque loja unpublished | FAIL (ver C1r) |
| C2 | orders + CPI + RPC seller | MB WAY exact → sem Session; seller confirma | CPI 400 off-platform; RPC 404 PGRST202; PATCH sem `pago` | status `reserva_pendente`; amount_paid null | FAIL (exacto off-platform — **não conta**) |
| C3 | disputa + refund + products | disputa+refund sem stock ×2 | disputa 403 42501 (janela); refund 200 `re_3UChpgH7…` | qty 1→2; status `cancelado`; 1 refund | FAIL |
| D1 | CPI + live accept + products | Future.wait CPI ∥ accept qty=1 | CPI 400 stock 0; accept 200 | ≤1 claim (live) | FAIL |
| D2 | lives + Hub lives + CPI | Future.wait end_live ∥ CPI hitch | CPI 200 `cs_test_a1mrYcw5…`; live ended | Hub lives n=0; order `reserva_pendente`; SKU marketplace ainda listado | FAIL |
| D3 | refund + CPI + products | pass1: refund ∥ nova compra qty=0 | insert 400 hold; race **não correu** | qtyMid=0; rf/cpi null | SKIP/retract (falso HOLD pass1) |
| B2r | Hub + products + CPI | re-oracle qty=0 com S1 published | Hub 200 []; insert 400 | s1_pub=true; Hub esconde qty=0; CPI não abre | FAIL |
| C1r | orders + Hub + chat + products | re-oracle leftover pago qty=1 | Hub 200 1 linha SKU `e8f0b8f8-…` | status `pago`; qty=1; Hub n=1 anon+JWT; chat 0 (e2e) | FAIL |
| B1r | Hub + live_reservation + CPI | hitch accepted vs Hub vs checkout | Hub 200 1 linha; insert 400 hold | res accepted; qty=1; Hub mostra; CPI recusa | **HOLD P2-1** |
| D3r | refund + CPI leftover | Future.wait refund pago ∥ CPI qty leftover=1 | rf 200 `re_3UChsaH7…`; CPI 200 `cs_` | qty 1→2; old `cancelado`; new `reserva_pendente` | FAIL (pass1 D3 retractado) |

Linhas na tabela: **16** (≥12). Stripe TEST pago: **sim** (C1/B3/C3/D3r). Residual clássico A2 published + C2 MB WAY exact = 2/16 ≪ 50%. **Não** ATROFIA_ABORT.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO (hold `order_hold_exceeds_stock`)
11. Seller falsifica pagamento plataforma — NÃO (C2 PATCH/RPC não marcam `pago`)
12. JWT cria saldo/fundos — NÃO (tip unpaid; Δwallet 0 no pago até release)
13. Refund excede captura — NÃO (B3/C3/D3r idempotente ≤ captura)
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO (sem release)
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO (B1/D1 2.º CPI 400)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO (hold live vs CPI)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da matriz)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`batata_seller_confirm_direct_payment` 404)
25. RLS crítico quebrado — NÃO (follow/fav unpublished 42501; disputa 42501)
26. Edge confia total do cliente — NÃO (off-platform 400; tip unpaid)
27. Regressão funcional (happy path partido) — NÃO (A2 fav 201 published; C1 pago)
28. Saturação atingida — NÃO (P2 aberto na vitrine vs hold live)

Poços DM: published Hub↔app=SIM · stock cross=SIM · money cross=SIM · race compose=SIM · chat ledger=SIM (e2e sem card) · published mid-unpub=SIM · refund stock=SIM  
ATROFIA: NÃO (2/16 residual; ângulo novo = composição Hub vs reserva live)  
Pagamento TEST: **pago** (vários PI `succeeded`). Chat card após e2e `setup_paid_order`: **0** — lacuna honesta (o cliente da app é que injeta o cartão; o settle de fixture não).

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

### P2-1 `P2-B1-HUB-HOLD` (DM2)

Ver secção acima. Único finding aberto. IDs: **P2-1**. Soma P2 `quantos` = 1.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| A2 follow/favorite published 201 | feliz CVDA — **não conta** (anti-atrofia) |
| C2 `MB WAY` exact 400 | fold off-platform — **não conta** |
| Pass1 D3 HOLD qtyEnd=-1 | **retractado** — insert qty=0; race não correu; D3r stock 1→2 coerente |
| C1 chat 0 após e2e pago | lacuna do caminho fixture, não do checkout da app |
| C1 Hub n=0 no pass1 | loja ficou unpublished (restore PATCH no-op); C1r Hub n=1 |
| C3 disputa 403 | janela/RLS; refund mesmo assim 1× stock |
| Tip unpaid após unpublish | pending; Δ=0 — defesa |
| Mutex 4∥2 / mbωay / FOMO | **não** exercitados (anti-atrofia) |

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------

| Lente | Evidência |
|-------|-----------|
| DM1 hub↔app | A1 Hub vazio unpublished; A3 sold oculto; C1r leftover visível |
| DM2 stock cross | B1/D1 hold; **P2-1 Hub vs CPI**; B2r qty=0 oculto |
| DM3 money cross | C1 pago; C2 sem Session; tip unpaid |
| DM4 race compose | B1/D1 Future.wait; D2 end∥CPI; D3r refund∥CPI |
| DM5 chat ledger | C1/C1r msgs_n=0 (e2e) |
| DM6 published | A1 unpublish mid-CPI/tip/follow 403 |
| DM7 refund stock | B3/C3 qty 1→2 sem ×2 |

--------------------------------------------------
## FIO (marketplace + live + hub + chat + money)
--------------------------------------------------

Unpublish a meio do checkout **e** da gorjeta (A1) → vitrine/fav (A2) → sold vs CPI (A3) → hitch+saco mesma unidade (B1) → qty=0 (B2) → pago Stripe + hitch + refund (B3) → pago vs Hub/chat/wallet (C1) → MB WAY (C2) → disputa+refund (C3) → races D1–D3.

--------------------------------------------------
## OPERAÇÃO
--------------------------------------------------

- Lives criadas: todas `ended` / `is_active=false` (pass2).
- S1 `hub_published=true` à saída (RPC). O PATCH `service_role` **não** republica — só o RPC do vendedor.
- **NÃO CORRIGIR.** Fase 4 não.

```
AUDITOR: REDTEAM_BLIND_DM_CROSS_SURFACE_POS_DBDG_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 16
VEREDICTO: FAIL_P2
```
