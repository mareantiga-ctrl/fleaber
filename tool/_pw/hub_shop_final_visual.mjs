import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const base = process.argv[2] ?? 'http://127.0.0.1:8798';
const handle = 'vendedora-prod';
const out = path.resolve('../../04-marketplace-final-validation');
const shots = path.join(out, 'SCREENSHOTS');
const report = {
  functional: {},
  regression02: {},
  regression03: {},
  console: { consoleErrors: [], pageErrors: [], failedRequests: [] },
  meta: { base, mode: 'visual-release', startedAt: new Date().toISOString() },
};

function wire(page) {
  page.on('console', (m) => {
    if (m.type() === 'error') report.console.consoleErrors.push(m.text());
  });
  page.on('pageerror', (e) => report.console.pageErrors.push(String(e)));
  page.on('response', (r) => {
    if (r.status() >= 400)
      report.console.failedRequests.push({
        status: r.status(),
        url: r.url().slice(0, 160),
      });
  });
}

async function dismiss(page) {
  // cookie banner: click approximate "Aceitar" zone top if present — try text via evaluate canvas N/A
  try {
    await page.mouse.click(page.viewportSize().width - 80, 40);
  } catch (_) {}
  await page.waitForTimeout(300);
}

async function waitTitle(page, pred, secs = 55) {
  for (let i = 0; i < secs; i++) {
    await page.waitForTimeout(1000);
    const t = await page.title();
    if (pred(t)) return t;
  }
  return await page.title();
}

const browser = await chromium.launch({ headless: true });

// ---- A/B Ver loja via profile ----
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  await page.goto(`${base}/${handle}`, { waitUntil: 'networkidle', timeout: 120000 }).catch(() =>
    page.goto(`${base}/${handle}`, { waitUntil: 'domcontentloaded' }),
  );
  const tProf = await waitTitle(
    page,
    (t) => t.includes('Vendedora') && !t.includes('encontrada'),
  );
  await page.waitForTimeout(2500);
  fs.mkdirSync(path.join(shots, 'FUNCTIONAL'), { recursive: true });
  await page.screenshot({ path: path.join(shots, 'FUNCTIONAL', 'profile_1440.png') });

  // Scroll down looking for marketplace / Ver loja; click mid-right CTA area repeatedly
  let verOk = false;
  for (let y = 400; y <= 2400; y += 280) {
    await page.mouse.wheel(0, 280);
    await page.waitForTimeout(400);
    // try click likely "Ver loja" positions (right side of marketplace section)
    for (const x of [1100, 1000, 900, 720]) {
      await page.mouse.click(x, 700);
      await page.waitForTimeout(1200);
      if (page.url().includes('/shop')) {
        verOk = true;
        break;
      }
    }
    if (verOk) break;
  }
  report.functional.profileTitle = tProf;
  report.functional.verLoja = {
    executed: verOk,
    url: page.url(),
    onShop: page.url().includes('/shop'),
    method: verOk ? 'coordinate-click' : 'fallback-goto',
  };
  if (!verOk) {
    await page.goto(`${base}/${handle}/shop`, { waitUntil: 'domcontentloaded' });
    await waitTitle(page, (t) => t.includes('Marketplace'));
  }
  await page.waitForTimeout(3000);
  await page.screenshot({ path: path.join(shots, 'FUNCTIONAL', 'shop_after_verloja.png') });

  // C–G product clicks by grid coords (1440 → 4 cols, card ~319x613, padding ~16)
  // first card center approx
  const cardCenters = [
    { x: 220, y: 420 },
    { x: 560, y: 420 },
  ];
  // click product 1
  await page.mouse.click(cardCenters[0].x, cardCenters[0].y);
  await page.waitForTimeout(2500);
  const url1 = page.url();
  report.functional.clickProduct1 = {
    executed: true,
    url: url1,
    openedProductDetails: url1.includes('productDetails') || url1.includes('product_id'),
    title: await page.title(),
  };
  await page.screenshot({ path: path.join(shots, 'FUNCTIONAL', 'product1.png') });

  await page.goBack();
  await waitTitle(page, (t) => t.includes('Marketplace'), 20);
  await page.waitForTimeout(1500);
  report.functional.backAfterProduct1 = {
    executed: true,
    url: page.url(),
    backOnShop: page.url().includes('/shop'),
  };

  // ensure shop
  if (!page.url().includes('/shop')) {
    await page.goto(`${base}/${handle}/shop`, { waitUntil: 'domcontentloaded' });
    await waitTitle(page, (t) => t.includes('Marketplace'));
    await page.waitForTimeout(2000);
  }

  await page.mouse.click(cardCenters[1].x, cardCenters[1].y);
  await page.waitForTimeout(2500);
  const url2 = page.url();
  report.functional.clickProduct2 = {
    executed: true,
    url: url2,
    openedProductDetails: url2.includes('productDetails') || url2.includes('product_id'),
    title: await page.title(),
  };
  await page.screenshot({ path: path.join(shots, 'FUNCTIONAL', 'product2.png') });

  await page.goBack();
  await page.waitForTimeout(1500);
  report.functional.backAfterProduct2 = {
    executed: true,
    url: page.url(),
    backOnShop: page.url().includes('/shop'),
  };

  await page.goForward();
  await page.waitForTimeout(1500);
  report.functional.forward = {
    executed: true,
    url: page.url(),
    onProduct: page.url().includes('product'),
  };
  await page.goBack();
  await page.waitForTimeout(1000);

  if (!page.url().includes('/shop')) {
    await page.goto(`${base}/${handle}/shop`, { waitUntil: 'domcontentloaded' });
    await waitTitle(page, (t) => t.includes('Marketplace'));
  }
  // scroll bottom
  for (let i = 0; i < 12; i++) {
    await page.mouse.wheel(0, 900);
    await page.waitForTimeout(300);
  }
  await page.waitForTimeout(800);
  report.functional.scrollBottom = {
    executed: true,
    url: page.url(),
    title: await page.title(),
  };
  await page.screenshot({ path: path.join(shots, 'FUNCTIONAL', 'shop_bottom.png') });
  await ctx.close();
}

// ---- P02 ----
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  await page.goto(`${base}/${handle}`, { waitUntil: 'domcontentloaded' });
  const t = await waitTitle(
    page,
    (tt) => tt.includes('Vendedora') && !tt.includes('encontrada'),
  );
  await page.waitForTimeout(3000);
  fs.mkdirSync(path.join(shots, 'REGRESSION_PAGE02'), { recursive: true });
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', '1440_first.png') });
  for (let i = 0; i < 10; i++) {
    await page.mouse.wheel(0, 500);
    await page.waitForTimeout(350);
  }
  await page.screenshot({
    path: path.join(shots, 'REGRESSION_PAGE02', '1440_marketplace.png'),
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(1500);
  await page.mouse.wheel(0, -5000);
  await page.waitForTimeout(800);
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', '390_first.png') });
  report.regression02 = {
    loaded: t.includes('Vendedora') && !t.includes('encontrada'),
    title: t,
    url: page.url(),
    screenshots: ['1440_first.png', '1440_marketplace.png', '390_first.png'],
  };
  await ctx.close();
}

// ---- P03 ----
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  await page.goto(`${base}/${handle}/live`, { waitUntil: 'domcontentloaded' });
  const t = await waitTitle(
    page,
    (tt) =>
      (tt.includes('Gravado') || tt.includes('Vendedora') || tt.includes('Direto')) &&
      !tt.includes('encontrada'),
  );
  await page.waitForTimeout(4000);
  fs.mkdirSync(path.join(shots, 'REGRESSION_PAGE03'), { recursive: true });
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE03', '1440_first.png') });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE03', '390_first.png') });
  report.regression03 = {
    loaded: !t.includes('encontrada'),
    title: t,
    url: page.url(),
    screenshots: ['1440_first.png', '390_first.png'],
  };
  await ctx.close();
}

// merge
let prev = {};
try {
  prev = JSON.parse(fs.readFileSync(path.join(out, 'RAW_REPORT.json'), 'utf8'));
} catch (_) {}
const merged = {
  ...prev,
  functional: { ...(prev.functional || {}), ...report.functional },
  regression02: report.regression02,
  regression03: report.regression03,
  console: {
    consoleErrors: [
      ...new Set([
        ...(prev.console?.consoleErrors || []),
        ...report.console.consoleErrors,
      ]),
    ],
    pageErrors: [
      ...new Set([...(prev.console?.pageErrors || []), ...report.console.pageErrors]),
    ],
    failedRequests: [
      ...(prev.console?.failedRequests || []),
      ...report.console.failedRequests,
    ].slice(0, 50),
  },
  meta: { ...(prev.meta || {}), ...report.meta, visualDoneAt: new Date().toISOString() },
};
fs.writeFileSync(path.join(out, 'RAW_REPORT.json'), JSON.stringify(merged, null, 2));
console.log(JSON.stringify(report, null, 2));
await browser.close();
console.log('DONE');
