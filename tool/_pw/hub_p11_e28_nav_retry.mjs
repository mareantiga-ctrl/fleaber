/**
 * E28 — reteste destinos com scroll até ao rótulo.
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(__dirname, '../reports/hub_p11_e28/screenshots/nav');
const base = 'http://127.0.0.1:8798';
const email = 'axinoqua@axinoquaa.pt';
const password = 'testeteste';
fs.mkdirSync(OUT, { recursive: true });

async function settle(page) {
  await page.waitForSelector('flt-glass-pane, flutter-view, canvas', {
    timeout: 180000,
  });
  await page.waitForTimeout(8000);
  await page
    .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
    .catch(() => {});
  const a = page.getByText('Aceitar').first();
  if (await a.count()) await a.click({ force: true }).catch(() => {});
}

async function text(page) {
  return page.evaluate(() => document.body?.innerText || '');
}

async function tapExact(page, label) {
  // scroll attempts: move mouse wheel / click lower area
  for (let i = 0; i < 8; i++) {
    const hit = await page.evaluate((lbl) => {
      const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      let n;
      while ((n = w.nextNode())) {
        if ((n.textContent || '').trim() === lbl) {
          const el = n.parentElement;
          if (!el) continue;
          const r = el.getBoundingClientRect();
          if (r.width > 0 && r.height > 0)
            return { x: r.x + r.width / 2, y: r.y + r.height / 2, top: r.top };
        }
      }
      return null;
    }, label);
    if (hit) {
      if (hit.top < 80 || hit.top > 780) {
        await page.mouse.wheel(0, hit.top < 80 ? -300 : 350);
        await page.waitForTimeout(400);
        continue;
      }
      await page.mouse.click(hit.x, hit.y);
      return true;
    }
    await page.mouse.wheel(0, 400);
    await page.waitForTimeout(500);
  }
  return false;
}

async function login(page) {
  await page.goto(`${base}/#/login?returnTo=/perfil`, {
    waitUntil: 'domcontentloaded',
    timeout: 180000,
  });
  await settle(page);
  if (/Definições de conta|Conta pessoal/i.test(await text(page))) return;
  const inputs = page.locator('input');
  if ((await inputs.count()) >= 2) {
    await inputs.nth(0).fill(email);
    await inputs.nth(1).fill(password);
  }
  await tapExact(page, 'Entrar');
  await page.waitForTimeout(10000);
  await settle(page);
}

async function goPerfil(page) {
  await page.goto(`${base}/#/perfil`, { waitUntil: 'domcontentloaded' });
  await settle(page);
  await page.waitForTimeout(2500);
}

const items = [
  { label: 'Favoritos', expect: /Favorito/i },
  { label: 'Encomendas e Compras', expect: /Encomenda|Compra|pedido/i },
  { label: 'Explorar FleaHub', expect: /FleaHub|ao vivo|Explorar|Comprar/i },
  { label: 'Como funciona o Fleaber', expect: /funciona|Como|Fleaber/i },
  { label: 'Perguntas Frequentes', expect: /Pergunta|Frequente|FAQ/i },
  { label: 'Informação legal', expect: /legal|Termos|Privacidade|Informação/i },
  { label: 'Sobre a nossa plataforma', expect: /plataforma|Sobre|Fleaber/i },
];

const browser = await chromium.launch({
  headless: true,
  args: ['--use-gl=angle', '--enable-webgl', '--ignore-gpu-blocklist'],
});
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();
await login(page);

const results = [];
for (const item of items) {
  await goPerfil(page);
  const tapped = await tapExact(page, item.label);
  await page.waitForTimeout(4500);
  await settle(page);
  const t = await text(page);
  const landed = tapped && item.expect.test(t);
  const shot = path.join(
    OUT,
    `P11-nav2_${item.label.replace(/\s+/g, '_').slice(0, 36)}.png`,
  );
  await page.screenshot({ path: shot, fullPage: false });
  await page.goto(`${base}/#/perfil`, { waitUntil: 'domcontentloaded' });
  await settle(page);
  const backOk = /Conta pessoal|Definições de conta|Terminar Sessão/i.test(
    await text(page),
  );
  results.push({ label: item.label, tapped, landed, backOk, sample: t.slice(0, 80) });
  console.log(item.label, { tapped, landed, backOk });
}

// Mensagens via bottom
await goPerfil(page);
const msg = await tapExact(page, 'Mensagens');
await page.waitForTimeout(5000);
await settle(page);
const mt = await text(page);
await page.screenshot({ path: path.join(OUT, 'P11-nav2_bottom_Mensagens.png') });
results.push({
  label: 'bottom:Mensagens',
  tapped: msg,
  landed: /Mensagens|Nova|conversa|Notifica/i.test(mt),
  sample: mt.slice(0, 80),
});
console.log('Mensagens', results.at(-1));

// Início
await goPerfil(page);
const home = await tapExact(page, 'Início');
await page.waitForTimeout(5000);
await settle(page);
const ht = await text(page);
await page.screenshot({ path: path.join(OUT, 'P11-nav2_bottom_Inicio.png') });
results.push({
  label: 'bottom:Início',
  tapped: home,
  landed: /Início|Direto|Para ti|Explorar/i.test(ht),
  sample: ht.slice(0, 80),
});
console.log('Início', results.at(-1));

fs.writeFileSync(
  path.resolve(__dirname, '../reports/hub_p11_e28/NAV_RETRY.json'),
  JSON.stringify(results, null, 2),
);
await browser.close();
console.log('done nav retry');
