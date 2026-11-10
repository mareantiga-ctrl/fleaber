# Stripe webhook staging — instruções passo a passo

**Projecto staging Supabase:** `fxdknzrqjenzqcvnwqqq`  
**Edge já deployed:** `stripe-webhook`  
**Modo Stripe:** **Test** (não Live)

---

## Parte A — Criar o endpoint no Stripe (browser)

### A1. Abrir o Dashboard certo

1. Abre o browser e vai a: https://dashboard.stripe.com/test/webhooks  
2. Confirma no canto superior direito / toggle que estás em **Test mode** (modo de teste).  
   - Se disser **Live**, muda para **Test**.  
3. Faz login na conta Stripe da Fleaber se pedir.

### A2. Adicionar endpoint

1. Clica em **Add endpoint** (ou «Adicionar endpoint»).
2. No campo **Endpoint URL**, cola **exactamente** isto (sem espaços no fim):

```
https://fxdknzrqjenzqcvnwqqq.supabase.co/functions/v1/stripe-webhook
```

3. Em **Description** (opcional): `Fleaber staging settle`.
4. Em **Events to send** / «Seleccionar eventos»:
   - Clica **Select events** / «Escolher eventos».
   - Procura e marca **só estes dois**:
     - `checkout.session.completed`
     - `checkout.session.async_payment_succeeded`
   - Não marques tudo.
5. Clica **Add endpoint** / «Adicionar» para guardar.

### A3. Copiar o segredo `whsec_…`

1. Abre o endpoint que acabaste de criar (clica no nome/URL).
2. Procura **Signing secret** / «Segredo de assinatura».
3. Clica **Reveal** / «Mostrar».
4. Copia o valor completo. Começa por `whsec_` (exemplo: `whsec_abc123…`).
5. Guarda-o num sítio seguro (Notas / gestor de passwords) — **não** coloques no chat público nem no Git.

---

## Parte B — Meter o segredo no Supabase (PowerShell no PC)

### B1. Abrir PowerShell na pasta do projecto

1. Abre **PowerShell**.
2. Corre:

```powershell
cd C:\Users\Casa\Desktop\Fleaber\fleaber
```

### B2. Definir o secret (substitui o teu `whsec_`)

1. Substitui `whsec_COLA_AQUI_O_QUE_COPIASTE` pelo valor real do Stripe.
2. Corre **uma linha** (tudo junto):

```powershell
npx supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_COLA_AQUI_O_QUE_COPIASTE --project-ref fxdknzrqjenzqcvnwqqq
```

Exemplo (falso):

```powershell
npx supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_abc123xyz --project-ref fxdknzrqjenzqcvnwqqq
```

3. Se pedir login Supabase, autentica e volta a correr o comando.
4. Deves ver algo como sucesso / secret updated.

### B3. Confirmar que o secret existe (sem ver o valor)

```powershell
npx supabase secrets list --project-ref fxdknzrqjenzqcvnwqqq
```

Na lista deve aparecer o nome **`STRIPE_WEBHOOK_SECRET`**.  
(O valor aparece mascarado/hash — isso é normal.)

### B4. (Recomendado) Redeploy da edge depois do secret

```powershell
npx supabase functions deploy stripe-webhook --project-ref fxdknzrqjenzqcvnwqqq --use-api
```

---

## Parte C — Verificar no Stripe (opcional)

1. Volta ao endpoint no Dashboard.
2. Faz uma compra Stripe **sandbox** na app (teste APP-SEC-005 / APP-SEC-006).
3. Em **Webhook attempts** / «Tentativas» do endpoint, deve aparecer um pedido **200** / sucesso.
4. Se aparecer **400 invalid_signature**: o `whsec_` está errado ou é de outro endpoint — volta a copiar o secret e corre o `secrets set` outra vez.

---

## O que isto faz / não faz

| Faz | Não faz |
|-----|---------|
| Quando o Stripe confirma pago, avisa a Fleaber mesmo se o telemóvel fechar o browser | Não substitui o return URL da app (esse continua a funcionar) |
| Só em **Test** até criares outro endpoint em Live (mais tarde) | Não mexe em chaves Live |

**Sem o `whsec_`:** as compras sandbox **já funcionam** pelo return URL. O webhook é rede de segurança.

---

## Checklist rápido

- [ ] Stripe em **Test mode**
- [ ] Endpoint criado com a URL staging acima
- [ ] Só 2 eventos (`completed` + `async_payment_succeeded`)
- [ ] `whsec_` copiado
- [ ] `npx supabase secrets set STRIPE_WEBHOOK_SECRET=… --project-ref fxdknzrqjenzqcvnwqqq`
- [ ] Nome `STRIPE_WEBHOOK_SECRET` aparece em `secrets list`
- [ ] (Opcional) redeploy `stripe-webhook`
