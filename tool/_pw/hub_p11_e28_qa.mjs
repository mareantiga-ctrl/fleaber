/**
 * E28 — P11 QA final: breakpoints, scroll, destinos seguros, loading sample.
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../reports/hub_p11_e28/screenshots');
const base = process.env.P11_BASE || 'http://127.0.0.1:8798';
const email = process.env.P11_EMAIL || 'axinoqua@axinoquaa.pt';
const password = process.env.P11_PASSWORD || 'testeteste';

for (const d of ['breakpoints', 'nav', 'loading', 'after']) {
  fs.mkdirSync(path.join(ROOT, d), { recursive: true });
}

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
  await page.waitForTimeout(400);
}

async function text(page) {
  return page.evaluate(() => document.body?.innerText || '');
}

async function tapExact(page, label) {
  const hit = await page.evaluate((lbl) => {
    const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = w.nextNode())) {
      if ((n.textContent || '').trim() === lbl) {
        const el = n.parentElement;
        if (!el) continue;
        const r = el.getBoundingClientRect();
        if (r.width > 0 && r.height > 0)
          return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
      }
    }
    return null;
  }, label);
  if (!hit) return false;
  await page.mouse.click(hit.x, hit.y);
  return true;
}

async function login(page) {
  await page.goto(`${base}/#/login?returnTo=/perfil`, {
    waitUntil: 'domcontentloaded',
    timeout: 180000,
  });
  await settle(page);
  const t = await text(page);
  if (/Definições de conta|Os meus anúncios|Terminar Sessão/i.test(t) &&
      !/E-mail|Entrar na/i.test(t)) {
    return;
  }
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
  await page.waitForTimeout(2000);
  return text(page);
}

const browser = await chromium.launch({
  headless: true,
  args: ['--use-gl=angle', '--enable-webgl', '--ignore-gpu-blocklist'],
});

const results = { breakpoints: [], nav: [], loading: null, after: [] };

// --- Breakpoints + after identity shots ---
const bps = [
  ['m390', 390, 1400],
  ['t767', 767, 1400],
  ['t768', 768, 1600],
  ['t800', 800, 1600],
  ['d1024', 1024, 1700],
  ['d1280', 1280, 1700],
  ['d1440', 1440, 1800],
  ['d1920', 1920, 1900],
];

for (const [name, w, h] of bps) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h } });
  const page = await ctx.newPage();
  await login(page);
  const t0 = Date.now();
  const t = await goPerfil(page);
  const loadMs = Date.now() - t0;
  const hub = /Conta pessoal|Compras e atividade|Vendas e FleaHub/i.test(t);
  const mobileList = /Definições de conta/i.test(t) && !hub;
  const hasBottom =
    /Início/.test(t) && /Mensagens/.test(t) && /Vender/.test(t);
  const nameHit = /Maria S\.|Utilizador Fleaber|axinoqua/i.exec(t)?.[0] || '?';
  const fileBp = path.join(ROOT, 'breakpoints', `P11-bp_${name}.png`);
  const fileAfter = path.join(ROOT, 'after', `P11-perfil_${name}.png`);
  await page.screenshot({ path: fileBp, fullPage: true });
  fs.copyFileSync(fileBp, fileAfter);
  const row = {
    name,
    w,
    h,
    bytes: fs.statSync(fileBp).size,
    hubSections: hub,
    mobileList,
    bottomNav: hasBottom,
    displayName: nameHit,
    loadMs,
    sample: t.slice(0, 100).replace(/\s+/g, ' '),
  };
  results.breakpoints.push(row);
  results.after.push(row);
  console.log(
    'bp',
    name,
    'hub=' + hub,
    'bottom=' + hasBottom,
    'name=' + nameHit,
    row.bytes,
  );
  await ctx.close();
}

// --- Loading: capture early frame during navigation ---
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  await login(page);
  await page.goto(`${base}/#/homePage`, { waitUntil: 'domcontentloaded' });
  await settle(page);
  const shotPromise = (async () => {
    await page.goto(`${base}/#/perfil`, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(400);
    await page.screenshot({
      path: path.join(ROOT, 'loading', 'P11-loading_early_d1280.png'),
      fullPage: false,
    });
    await page.waitForTimeout(8000);
    const t = await text(page);
    await page.screenshot({
      path: path.join(ROOT, 'loading', 'P11-loading_settled_d1280.png'),
      fullPage: true,
    });
    results.loading = {
      earlyBytes: fs.statSync(
        path.join(ROOT, 'loading', 'P11-loading_early_d1280.png'),
      ).size,
      settledBytes: fs.statSync(
        path.join(ROOT, 'loading', 'P11-loading_settled_d1280.png'),
      ).size,
      settledName: /Maria S\.|Utilizador Fleaber|axinoqua/i.exec(t)?.[0],
      sample: t.slice(0, 120).replace(/\s+/g, ' '),
    };
    console.log('loading', results.loading);
  })();
  await shotPromise;
  await ctx.close();
}

// --- Safe nav destinations (open + back to perfil) ---
const safeNav = [
  { label: 'Favoritos', expect: /Favoritos|favorito/i },
  { label: 'Explorar FleaHub', expect: /FleaHub|Explorar|ao vivo/i },
  { label: 'Como funciona o Fleaber', expect: /funciona|Fleaber|Como/i },
  { label: 'Perguntas Frequentes', expect: /Frequente|FAQ|Pergunta/i },
  { label: 'Informação legal', expect: /legal|Informação|Termos|Privacidade/i },
];

{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  await login(page);
  for (const item of safeNav) {
    await goPerfil(page);
    const tapped = await tapExact(page, item.label);
    await page.waitForTimeout(5000);
    await settle(page);
    const t = await text(page);
    const ok = tapped && item.expect.test(t);
    const shot = path.join(
      ROOT,
      'nav',
      `P11-nav_${item.label.replace(/\s+/g, '_').slice(0, 40)}.png`,
    );
    await page.screenshot({ path: shot, fullPage: false });
    // return via hash
    await page.goto(`${base}/#/perfil`, { waitUntil: 'domcontentloaded' });
    await settle(page);
    const backT = await text(page);
    const backOk = /Definições de conta|Conta pessoal|Terminar Sessão/i.test(
      backT,
    );
    results.nav.push({
      label: item.label,
      tapped,
      landed: ok,
      backOk,
      bytes: fs.statSync(shot).size,
    });
    console.log('nav', item.label, { tapped, landed: ok, backOk });
  }
  // Bottom nav: Mensagens
  await goPerfil(page);
  const msgTap = await tapExact(page, 'Mensagens');
  await page.waitForTimeout(5000);
  await settle(page);
  const msgT = await text(page);
  await page.screenshot({
    path: path.join(ROOT, 'nav', 'P11-nav_bottom_Mensagens.png'),
    fullPage: false,
  });
  results.nav.push({
    label: 'bottom:Mensagens',
    tapped: msgTap,
    landed: /Mensagens|conversa|Notifica/i.test(msgT),
    backOk: null,
  });
  console.log('nav bottom Mensagens', results.nav.at(-1));
  await ctx.close();
}

await browser.close();
fs.writeFileSync(
  path.resolve(__dirname, '../reports/hub_p11_e28/QA_RAW.json'),
  JSON.stringify(results, null, 2),
);
console.log('done e28 qa');
