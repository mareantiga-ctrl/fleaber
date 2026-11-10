/**
 * E31 — capturas P13 detalhe produto (só leitura, sem checkout).
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(__dirname, '../reports/hub_p13_e31/screenshots');
const base = process.env.P13_BASE || 'http://127.0.0.1:8798';
const email = process.env.P13_EMAIL || 'axinoqua@axinoquaa.pt';
const password = process.env.P13_PASSWORD || 'testeteste';
const forcedId = process.env.P13_PRODUCT_ID || '';

fs.mkdirSync(OUT, { recursive: true });

async function settle(page, ms = 8000) {
  await page.waitForSelector('flt-glass-pane, flutter-view, canvas', {
    timeout: 180000,
  });
  await page.waitForTimeout(ms);
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
    if (hit && hit.top > 60 && hit.top < 850) {
      await page.mouse.click(hit.x, hit.y);
      return true;
    }
    await page.mouse.wheel(0, 320);
    await page.waitForTimeout(350);
  }
  return false;
}

async function login(page) {
  await page.goto(`${base}/#/login?returnTo=/homePage`, {
    waitUntil: 'domcontentloaded',
    timeout: 180000,
  });
  await settle(page, 9000);
  if (/Comprar agora|Detalhe|Para ti|Início/i.test(await text(page))) return;
  const inputs = page.locator('input');
  if ((await inputs.count()) >= 2) {
    await inputs.nth(0).fill(email);
    await inputs.nth(1).fill(password);
  }
  await tapExact(page, 'Entrar');
  await page.waitForTimeout(12000);
  await settle(page, 5000);
}

function isProductPage(t) {
  return (
    /Detalhe|Comprar agora|Fazer proposta|Artigo não encontrado/i.test(t) &&
    !/Bem-vindo de volta|Palavra-passe/i.test(t)
  );
}

const browser = await chromium.launch({
  headless: true,
  args: ['--use-gl=angle', '--enable-webgl', '--ignore-gpu-blocklist'],
});

const meta = { opened: false, method: null, sample: '', shots: [] };

// Login once in a warm context, find product
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  await login(page);

  if (forcedId) {
    await page.goto(
      `${base}/#/productDetails?product_id=${encodeURIComponent(forcedId)}`,
      { waitUntil: 'domcontentloaded' },
    );
    await settle(page, 12000);
    meta.method = 'forced_id';
  } else {
    await page.goto(`${base}/#/homePage`, { waitUntil: 'domcontentloaded' });
    await settle(page, 10000);
    // Tap center of first marketplace card area (below header)
    await page.mouse.click(320, 420);
    await page.waitForTimeout(6000);
    await settle(page, 5000);
    let t = await text(page);
    if (!isProductPage(t)) {
      // try Favoritos then first item area
      await page.goto(`${base}/#/favoritos`, { waitUntil: 'domcontentloaded' });
      await settle(page, 8000);
      await page.mouse.click(400, 280);
      await page.waitForTimeout(6000);
      await settle(page, 5000);
      t = await text(page);
      meta.method = 'favoritos_tap';
    } else {
      meta.method = 'home_tap';
    }
  }

  const t = await text(page);
  meta.sample = t.slice(0, 160).replace(/\s+/g, ' ');
  meta.opened = isProductPage(t) && !/Artigo não encontrado/i.test(t);
  meta.hash = await page.evaluate(() => location.hash);
  console.log('open', meta);

  if (!meta.opened) {
    await page.screenshot({
      path: path.join(OUT, 'P13-BLOCKED_no_product.png'),
      fullPage: true,
    });
    fs.writeFileSync(
      path.resolve(__dirname, '../reports/hub_p13_e31/CAPTURE_META.json'),
      JSON.stringify(meta, null, 2),
    );
    await browser.close();
    process.exit(0);
  }

  // Capture URL for other viewports
  const productUrl = await page.evaluate(() => location.href);
  meta.productUrl = productUrl.replace(/^http:\/\/127\.0\.0\.1:\d+/, base);
  await ctx.close();

  const viewports = [
    ['m390', 390, 1600],
    ['t768', 768, 1600],
    ['d1024', 1024, 1700],
    ['d1280', 1280, 1800],
    ['d1440', 1440, 1900],
    ['d1920', 1920, 2000],
  ];

  for (const [name, w, h] of viewports) {
    const c = await browser.newContext({ viewport: { width: w, height: h } });
    const p = await c.newPage();
    await login(p);
    await p.goto(meta.productUrl, { waitUntil: 'domcontentloaded' });
    await settle(p, 10000);
    await p.waitForTimeout(2000);
    const tt = await text(p);
    const file = path.join(OUT, `P13-produto_${name}.png`);
    await p.screenshot({ path: file, fullPage: true });
    const row = {
      name,
      bytes: fs.statSync(file).size,
      ok: isProductPage(tt) && !/Artigo não encontrado/i.test(tt),
      hasComprar: /Comprar agora/i.test(tt),
      hasProposta: /Fazer proposta/i.test(tt),
      hasContactar: /Contactar/i.test(tt),
      sample: tt.slice(0, 100).replace(/\s+/g, ' '),
    };
    meta.shots.push(row);
    console.log(name, row.bytes, row.ok, row.hasComprar);
    await c.close();
  }
}

fs.writeFileSync(
  path.resolve(__dirname, '../reports/hub_p13_e31/CAPTURE_META.json'),
  JSON.stringify(meta, null, 2),
);
await browser.close();
console.log('done p13 capture');
