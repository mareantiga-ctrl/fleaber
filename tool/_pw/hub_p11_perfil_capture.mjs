/**
 * P11 Perfil — login staging + capturas before/after.
 * Usage: node hub_p11_perfil_capture.mjs [before|after]
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const phase = (process.argv[2] || 'before').toLowerCase();
const OUT = path.resolve(
  __dirname,
  `../reports/hub_p11_e27/screenshots/${phase === 'after' ? 'after' : 'before'}`,
);
const base = process.env.P11_BASE || 'http://127.0.0.1:8798';
const email = process.env.P11_EMAIL || 'axinoqua@axinoquaa.pt';
const password = process.env.P11_PASSWORD || 'testeteste';

fs.mkdirSync(OUT, { recursive: true });

// Alturas generosas: canvas Flutter não faz fullPage real — viewport alto = scroll visual.
const viewports = [
  ['m390', 390, 1400],
  ['t768', 768, 1600],
  ['d1024', 1024, 1600],
  ['d1280', 1280, 1700],
  ['d1440', 1440, 1800],
  ['d1920', 1920, 1900],
];

async function settle(page) {
  await page.waitForSelector('flt-glass-pane, flutter-view, canvas', {
    timeout: 180000,
  });
  await page.waitForTimeout(9000);
  await page
    .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
    .catch(() => {});
  await page.waitForTimeout(400);
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
  if (/Definições de conta|Os meus anúncios|Terminar Sessão|Perfil/i.test(t) &&
      !/Entrar na sua conta|E-mail/i.test(t)) {
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

async function ensurePerfil(page) {
  await page.goto(`${base}/#/perfil`, { waitUntil: 'domcontentloaded' });
  await settle(page);
  let t = await text(page);
  if (!/Definições|anúncios|Favoritos|Terminar|FleaHub/i.test(t)) {
    await page.waitForTimeout(4000);
    t = await text(page);
  }
  return t;
}

async function shotFull(page, file) {
  // Full page when content scrolls; Flutter canvas often needs viewport + scroll
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(300);
  await page.screenshot({ path: file, fullPage: true });
}

const browser = await chromium.launch({
  headless: true,
  args: ['--use-gl=angle', '--enable-webgl', '--ignore-gpu-blocklist'],
});

const meta = [];
for (const [name, w, h] of viewports) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h } });
  const page = await ctx.newPage();
  await login(page);
  const t = await ensurePerfil(page);
  const file = path.join(OUT, `P11-perfil_${name}.png`);
  await shotFull(page, file);
  const bytes = fs.statSync(file).size;
  meta.push({
    name,
    bytes,
    ok: /Definições|anúncios|Favoritos|Terminar|FleaHub|Saldo/i.test(t),
    sample: t.slice(0, 120).replace(/\s+/g, ' '),
  });
  console.log(name, bytes, meta[meta.length - 1].ok, meta[meta.length - 1].sample);
  await ctx.close();
}

await browser.close();
fs.writeFileSync(
  path.resolve(__dirname, `../reports/hub_p11_e27/EVIDENCE_${phase}.json`),
  JSON.stringify({ phase, at: new Date().toISOString(), meta }, null, 2),
);
console.log('done', phase, OUT);
