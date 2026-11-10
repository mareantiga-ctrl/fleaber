# Guia definitivo C3 — auditoria em PROD (pré-lançamento)

## Decisão

- Sem Docker / WSL / projecto TEST.
- Auditoria em **Supabase PROD** `bpmpkzwnrbmuqnhgdscf` com contas **fictícias**.
- App ainda **não lançada**; sem utilizadores reais de clientes.

## Contas C3 (password fora do git)

| Papel | Email | Handle |
|-------|-------|--------|
| Comprador A | `c3.buyer.a@fleaber.test` | `c3buyera` |
| Comprador B | `c3.buyer.b@fleaber.test` | `c3buyerb` |
| Vendedor A | `c3.seller.a@fleaber.test` | `c3sellera` |
| Vendedor B | `c3.seller.b@fleaber.test` | `c3sellerb` |

Passwords: ficheiro local do operador  
`%TEMP%\fleaber_c3_prod_creds.json` (não no repositório / ZIP).  
Pedir ao dono do produto por canal seguro.

Login smoke C1: **4/4 OK**.

## Dados

- Bio `C3_AUDIT…` nos 4 perfis.
- 2 produtos `C3_AUDIT Artigo demo` (12,50 € ×5) nos vendedores.
- Limpeza: emails `@fleaber.test` + títulos/bio `C3_AUDIT` (script futuro; sem delete em massa agora).

## Como correr

1. Branch código: `c1/191-c3-unblock` (+ bootstrap webrtc).
2. Android: APK **1881** PROD (ou build novo se pedires UX OTP).
3. Hub stamp **189** (docs) — revalidar no browser.
4. Login com contas C3; testar RLS cruzado (Buyer A não edita Seller A).
5. Checkout Stripe: só **TEST keys** / sem LIVE.
6. DPD: sem create comercial.
7. SMS: operacional; **sem campanhas em massa**.

## Limites (obrigatório)

Autorizado: auth, RLS, reservas, chat, anúncios, stock, checkout TEST, fluxos UI.

Proibido sem GO: Stripe LIVE, reembolsos reais, etiquetas DPD reais, destrutivo, carga, SMS em massa.

Sem `service_role` no relatório C3.

## Versões

| Artefacto | Valor |
|-----------|--------|
| Branch | `c1/191-c3-unblock` |
| APK | 1881 PROD |
| Hub | stamp 189 (docs) |
| SMS | `OPS_SMS_SEND_ENABLED=1` permanente |
| OTP exp | **600 s** |
| CPI F-001 | charge servidor; LIVE off |

## BulkGate / Cláudia

Verificação efectiva do …5912: **ainda FAIL** até ela pedir código novo na app e confirmar (OTP antigo expirou).  
Instruções: Conta → Verificar telemóvel → pedir SMS → introduzir em **≤10 min**.
