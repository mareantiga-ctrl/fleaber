/**
 * Seed Prod: vendedora pronta para live + 10 anúncios de teste.
 * Lê service_role de tool/.tmp_prod_service_role.txt (apagado no fim).
 * Credenciais email → tool/live_ops_production.env (gitignored).
 *
 * node tool/fase4_prod_seed_seller_listings.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const ref = 'bpmpkzwnrbmuqnhgdscf';
const baseUrl = `https://${ref}.supabase.co`;
const tmpKey = path.join(root, 'tool/.tmp_prod_service_role.txt');
const envFile = path.join(root, 'tool/live_ops_production.env');
const reportFile = path.join(
  root,
  'tool/reports/fase4_execution_2026-09-13/P4.5/SEED_SELLER_LISTINGS.md',
);

const serviceRole = fs.readFileSync(tmpKey, 'utf8').trim();
if (serviceRole.length < 40) throw new Error('service_role tmp em falta');

const headers = {
  apikey: serviceRole,
  Authorization: `Bearer ${serviceRole}`,
  'Content-Type': 'application/json',
  Prefer: 'return=representation',
};

async function api(method, pathName, body) {
  const res = await fetch(`${baseUrl}${pathName}`, {
    method,
    headers: {
      ...headers,
      ...(method === 'GET' ? { Prefer: 'return=representation' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  if (!res.ok) {
    throw new Error(`${method} ${pathName} ${res.status}: ${text.slice(0, 500)}`);
  }
  return json;
}

function upsertEnv(key, value) {
  let content = fs.existsSync(envFile) ? fs.readFileSync(envFile, 'utf8') : '';
  const line = `${key}=${value}`;
  const re = new RegExp(`^\\s*${key}\\s*=.*$`, 'm');
  if (re.test(content)) content = content.replace(re, line);
  else content = `${content.trimEnd()}\n${line}\n`;
  fs.writeFileSync(envFile, content, 'utf8');
}

const listings = [
  {
    title: 'Casaco ganga oversized — TESTE 01',
    price: 28.5,
    ref_code: 'T01',
    category: 'Roupa',
    clothing_size: 'M',
    gender: 'Mulher',
    state: 'Bom estado',
    description:
      'Casaco de ganga azul, tamanho M. Anúncio de teste Prod — não vender a clientes reais.',
  },
  {
    title: 'Vestido floral verão — TESTE 02',
    price: 18.0,
    ref_code: 'T02',
    category: 'Roupa',
    clothing_size: 'S',
    gender: 'Mulher',
    state: 'Como novo',
    description: 'Vestido leve floral. Stock de teste para marketplace e directo.',
  },
  {
    title: 'Sapatilhas brancas 38 — TESTE 03',
    price: 22.0,
    ref_code: 'T03',
    category: 'Calçado',
    clothing_size: '38',
    gender: 'Mulher',
    state: 'Usado',
    description: 'Sapatilhas brancas, pouco uso. Ref T03 teste Prod.',
  },
  {
    title: 'Mala pequenina couro — TESTE 04',
    price: 35.0,
    ref_code: 'T04',
    category: 'Acessórios',
    clothing_size: null,
    gender: 'Mulher',
    state: 'Bom estado',
    description: 'Mala a tiracolo. Teste hub + saco.',
  },
  {
    title: 'Camisola knit bege — TESTE 05',
    price: 14.5,
    ref_code: 'T05',
    category: 'Roupa',
    clothing_size: 'L',
    gender: 'Mulher',
    state: 'Bom estado',
    description: 'Camisola de malha. Disponível marketplace e live.',
  },
  {
    title: 'Calças cargo verde — TESTE 06',
    price: 19.9,
    ref_code: 'T06',
    category: 'Roupa',
    clothing_size: 'M',
    gender: 'Mulher',
    state: 'Como novo',
    description: 'Calças cargo. Ref T06.',
  },
  {
    title: 'Colar prateado — TESTE 07',
    price: 9.5,
    ref_code: 'T07',
    category: 'Bijuteria',
    clothing_size: null,
    gender: 'Mulher',
    state: 'Novo',
    description: 'Colar curto. Bom para rifa/live teste.',
  },
  {
    title: 'Blazer preto clássico — TESTE 08',
    price: 32.0,
    ref_code: 'T08',
    category: 'Roupa',
    clothing_size: 'M',
    gender: 'Mulher',
    state: 'Bom estado',
    description: 'Blazer preto. Anúncio completo de teste.',
  },
  {
    title: 'Saia midi plissada — TESTE 09',
    price: 16.0,
    ref_code: 'T09',
    category: 'Roupa',
    clothing_size: 'S',
    gender: 'Mulher',
    state: 'Como novo',
    description: 'Saia midi. Teste quantidade 2.',
  },
  {
    title: 'Cachecol lã xadrez — TESTE 10',
    price: 12.0,
    ref_code: 'T10',
    category: 'Acessórios',
    clothing_size: null,
    gender: 'Unissexo',
    state: 'Bom estado',
    description: 'Cachecol de inverno. Último do lote de teste Prod.',
  },
];

async function main() {
  // 1) List profiles — prefer existing vendedor
  const profiles = await api(
    'GET',
    '/rest/v1/profiles?select=id,full_name,user_type,handle,hub_published&order=created_at.desc&limit=50',
  );
  let seller = (profiles || []).find(
    (p) =>
      String(p.user_type || '')
        .toLowerCase()
        .match(/vendedor|seller|admin/),
  );

  // 2) Ensure dedicated email seller exists (Auth Admin)
  const email = 'vendedora.prod.teste@fleaber.test';
  const password = `FpT-${crypto.randomBytes(6).toString('hex')}!aA1`;
  let emailUserId = null;

  const listUsers = await fetch(`${baseUrl}/auth/v1/admin/users?page=1&per_page=200`, {
    headers,
  });
  const listJson = await listUsers.json();
  const users = listJson.users || listJson || [];
  const existing = (Array.isArray(users) ? users : []).find(
    (u) => String(u.email || '').toLowerCase() === email,
  );

  if (existing) {
    emailUserId = existing.id;
    // reset password so we know it
    await fetch(`${baseUrl}/auth/v1/admin/users/${emailUserId}`, {
      method: 'PUT',
      headers,
      body: JSON.stringify({ password, email_confirm: true }),
    }).then(async (r) => {
      if (!r.ok) throw new Error(`reset pw ${r.status} ${await r.text()}`);
    });
  } else {
    const created = await fetch(`${baseUrl}/auth/v1/admin/users`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: 'Vendedora Prod Teste' },
      }),
    });
    const createdJson = await created.json();
    if (!created.ok) {
      throw new Error(`create user ${created.status}: ${JSON.stringify(createdJson)}`);
    }
    emailUserId = createdJson.id || createdJson.user?.id;
  }

  if (!emailUserId) throw new Error('emailUserId em falta');

  // Profile: trigger Auth costuma criar a linha — PATCH garante vendedor + Hub
  const handle = 'vendedora-prod';
  await api('PATCH', `/rest/v1/profiles?id=eq.${emailUserId}`, {
    user_type: 'vendedor',
    handle,
    hub_published: true,
    hub_bio: 'Conta de teste Prod — lives e marketplace. Não é loja real.',
    full_name: 'Vendedora Prod Teste',
    location: 'Portugal',
    shipping_country: 'PT',
    phone: '910000001',
  });

  // Se PATCH não actualizou (sem linha), INSERT
  const check = await api(
    'GET',
    `/rest/v1/profiles?id=eq.${emailUserId}&select=id,user_type,handle,hub_published`,
  );
  if (!check || check.length === 0) {
    await api('POST', '/rest/v1/profiles', {
      id: emailUserId,
      full_name: 'Vendedora Prod Teste',
      user_type: 'vendedor',
      handle,
      hub_published: true,
      hub_bio: 'Conta de teste Prod — lives e marketplace. Não é loja real.',
      location: 'Portugal',
      shipping_country: 'PT',
      phone: '910000001',
    });
  }

  // Also harden any existing Face vendedor profiles (hub + type)
  const faceSellers = (profiles || []).filter(
    (p) =>
      p.id !== emailUserId &&
      String(p.user_type || '')
        .toLowerCase()
        .match(/vendedor|seller/),
  );
  for (const p of faceSellers) {
    const h =
      p.handle && String(p.handle).length >= 3
        ? p.handle
        : `seller-${String(p.id).slice(0, 8)}`;
    await api('PATCH', `/rest/v1/profiles?id=eq.${p.id}`, {
      user_type: 'vendedor',
      handle: h,
      hub_published: true,
      hub_bio: p.hub_bio || 'Perfil vendedor Prod (teste).',
    });
  }

  seller = { id: emailUserId, full_name: 'Vendedora Prod Teste', handle };

  upsertEnv('PROD_TEST_SELLER_EMAIL', email);
  upsertEnv('PROD_TEST_SELLER_PASSWORD', password);
  upsertEnv('PROD_TEST_SELLER_ID', emailUserId);
  upsertEnv('PROD_TEST_SELLER_HANDLE', handle);

  // Remove old teste listings for this seller (refs T01-T10)
  await api(
    'DELETE',
    `/rest/v1/products?seller_id=eq.${emailUserId}&ref_code=in.(T01,T02,T03,T04,T05,T06,T07,T08,T09,T10)`,
  );

  const inserted = [];
  for (let i = 0; i < listings.length; i++) {
    const L = listings[i];
    const qty = L.ref_code === 'T09' ? 2 : 1;
    const row = {
      seller_id: emailUserId,
      title: L.title,
      price: L.price,
      ref_code: L.ref_code,
      category: L.category,
      clothing_size: L.clothing_size,
      gender: L.gender,
      state: L.state,
      description: L.description,
      list_on_marketplace: true,
      available_for_live: true,
      is_sold: false,
      quantity: qty,
      image_urls: [
        `https://picsum.photos/seed/fleaber-prod-${L.ref_code}/600/800`,
      ],
    };
    const out = await api('POST', '/rest/v1/products', row);
    inserted.push(Array.isArray(out) ? out[0] : out);
  }

  const md = `# Seed Prod — vendedora + 10 anúncios (2026-09-14)

## Conta vendedora (email)

- **Email:** \`${email}\`
- **Password:** ver \`tool/live_ops_production.env\` → \`PROD_TEST_SELLER_PASSWORD\` (não no Git / não no chat)
- **User id:** \`${emailUserId}\`
- **Handle Hub:** \`${handle}\` (hub_published=true)
- **user_type:** vendedor

## Contas Facebook já vendedor

${faceSellers.length ? faceSellers.map((p) => `- ${p.id} · ${p.full_name || '?'} · handle actualizado`).join('\n') : '- (nenhuma além da email, ou já estavam ok)'}

## Anúncios criados (${inserted.length})

| Ref | Título | Preço | Qty | Marketplace | Live |
|-----|--------|-------|-----|-------------|------|
${listings
  .map(
    (L) =>
      `| ${L.ref_code} | ${L.title} | ${L.price.toFixed(2)} € | ${L.ref_code === 'T09' ? 2 : 1} | sim | sim |`,
  )
  .join('\n')}

Imagens: picsum.photos (placeholder).

## Como entrar na app

1. Na app Prod: logout.
2. Login **email** com as credenciais do env (não Face, para esta conta de teste).
3. Novo directo / marketplace deve listar os T01–T10.

## Arquitectura permissão live

Ver \`ARQUITETURA_PERMISSAO_LIVE.md\` neste pacote.
`;

  fs.writeFileSync(reportFile, md, 'utf8');
  console.log('SEED_OK');
  console.log(`seller_id=${emailUserId}`);
  console.log(`listings=${inserted.length}`);
  console.log(`report=${reportFile}`);
  console.log('password=written_to_live_ops_production.env_only');
}

main()
  .catch((e) => {
    console.error('SEED_FAIL', e.message || e);
    process.exit(1);
  })
  .finally(() => {
    try {
      fs.unlinkSync(tmpKey);
    } catch {
      /* ignore */
    }
  });
