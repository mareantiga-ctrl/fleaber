# Fleaber — Website oficial

Landing page e páginas legais para aprovação Meta / Stripe e lançamento em Portugal.

Conteúdo alinhado com `lib/legal/legal_texts.dart` e `Historico/FLEABER_DOCUMENTO.md` (Maio 2026).

## Estrutura

```
website/
  index.html      — Landing page
  privacy.html    — Política de Privacidade (RGPD)
  terms.html      — Termos e Condições
  refunds.html    — Reembolsos e Disputas
  css/styles.css
  js/main.js
  assets/logo.png
```

## Como ver localmente

Abre `index.html` no browser ou serve a pasta:

```bash
cd website
python -m http.server 8080
```

Depois visita `http://localhost:8080`

## Deploy

Faz upload da pasta `website/` completa para qualquer hosting estático (Netlify, Vercel, Cloudflare Pages, cPanel, etc.).

Domínio sugerido: `https://fleaber.pt` ou `https://www.fleaber.com`

## Contactos no site

- Suporte: geral@fleaber.pt · +351 937 475 638
- Legal/RGPD: mareantiga@gmail.com
- Comercial: geral@fleaber.com
