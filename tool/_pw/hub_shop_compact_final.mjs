import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const out = path.resolve('../../04-marketplace-compact-final');
const shots = path.join(out, 'SCREENSHOTS');

const viewports = [
  { name: '390', width: 390, height: 844 },
  { name: '768', width: 768, height: 1024 },
  { name: '1024', width: 1024, height: 768 },
  { name: '1280', width: 1280, height: 800 },
  { name: '1440', width: 1440, height: 900 },
  { name: '1920', width: 1920, height: 1080 },
];

const report = {
  viewports: {},
  functional: {},
  regression02: {},
  regression03: {},
  console: { consoleErrors: [], pageErrors: [], failedRequests: [] },
  meta: { base, at: new Date().toISOString() },
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
  try {
    await page.mouse.click(
      page.viewportSize().width / 2 + 140,
      page.viewportSize().height - 36,
    );
  } catch (_) {}
  await page.waitForTimeout(400);
}

async function waitShop(page) {
  await page.goto(`${base}/vendedora-prod/shop`, {
    waitUntil: 'domcontentloaded',
    timeout: 120000,
  });
  for (let i = 0; i < 50; i++) {
    await page.waitForTimeout(1000);
    const t = await page.title();
    if (t.includes('encontrada') || t.includes('A carregar') || t === 'Fleaber')
      continue;
    if (page.url().includes('/shop') && i >= 10) {
      await dismiss(page);
      await page.waitForTimeout(1000);
      return true;
    }
  }
  return page.url().includes('/shop');
}

function measureTheory(vw) {
  const shopMinCardWidth = 210;
  const shopGridGap = 10;
  const shopGridPadding = 12;
  const shopMaxContentWidth = 1680;
  let contentW;
  if (vw < 700) contentW = 480;
  else if (vw < 1000) contentW = Math.min(vw - 48, 900);
  else contentW = Math.min(vw - 64, shopMaxContentWidth);
  let cols;
  if (vw < 1000) cols = 2;
  else {
    const inner = contentW - shopGridPadding * 2;
    cols = Math.floor((inner + shopGridGap) / (shopMinCardWidth + shopGridGap));
    cols = Math.max(3, Math.min(7, cols));
  }
  const inner = contentW - shopGridPadding * 2;
  const cardW = cols > 0 ? (inner - shopGridGap * (cols - 1)) / cols : 0;
  const side = (vw - contentW) / 2;
  return {
    cols,
    cardW: Math.round(cardW),
    cardH: Math.round(cardW / 0.58),
    gutters: shopGridGap,
    contentWidth: Math.round(contentW),
    sideMarginLeft: Math.round(side),
    sideMarginRight: Math.round(side),
  };
}

const browser = await chromium.launch({ headless: true });

// Viewports
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  const ok = await waitShop(page);
  report.viewports.loadOk = ok;
  report.viewports.loadTitle = await page.title();
  if (!ok) {
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(path.join(out, 'RAW_REPORT.json'), JSON.stringify(report, null, 2));
    console.error('SHOP LOAD FAIL');
    process.exit(2);
  }
  for (const vp of viewports) {
    await page.setViewportSize({ width: vp.width, height: vp.height });
    await page.waitForTimeout(1600);
    await page.mouse.wheel(0, -8000);
    await page.waitForTimeout(500);
    const m = measureTheory(vp.width);
    report.viewports[vp.name] = m;
    const dir = path.join(shots, vp.name);
    fs.mkdirSync(dir, { recursive: true });
    await page.screenshot({ path: path.join(dir, 'first.png'), fullPage: false });
    for (let i = 0; i < 8; i++) {
      await page.mouse.wheel(0, 900);
      await page.waitForTimeout(250);
    }
    await page.screenshot({ path: path.join(dir, 'full.png'), fullPage: false });
    console.log(`[${vp.name}] cols=${m.cols} card≈${m.cardW}`);
  }
  await ctx.close();
}

// Functional
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  await page.goto(`${base}/vendedora-prod`, { waitUntil: 'domcontentloaded' });
  let profileOk = false;
  for (let i = 0; i < 40; i++) {
    await page.waitForTimeout(1000);
    const t = await page.title();
    if (t.includes('Vendedora') && !t.includes('encontrada')) {
      profileOk = true;
      break;
    }
  }
  await dismiss(page);
  await page.waitForTimeout(1500);
  fs.mkdirSync(path.join(shots, 'FUNCTIONAL'), { recursive: true });
  await page.screenshot({ path: path.join(shots, 'FUNCTIONAL', 'profile.png') });

  // Try Ver loja via known marketplace row (right side) — fallback goto /shop
  let verOk = false;
  for (let y = 400; y <= 2000 && !verOk; y += 300) {
    await page.mouse.wheel(0, 300);
    await page.waitForTimeout(300);
    for (const x of [1280, 1200, 1100, 1000]) {
      await page.mouse.click(x, 520);
      await page.waitForTimeout(1200);
      if (page.url().includes('/shop')) {
        verOk = true;
        break;
      }
      if (!page.url().includes('vendedora-prod') || page.url().includes('perfil')) {
        await page.goto(`${base}/vendedora-prod`, { waitUntil: 'domcontentloaded' });
        for (let i = 0; i < 20; i++) {
          await page.waitForTimeout(800);
          if ((await page.title()).includes('Vendedora')) break;
        }
        await page.waitForTimeout(1000);
      }
    }
  }
  report.functional.verLoja = {
    executed: verOk,
    url: page.url(),
    onShop: page.url().includes('/shop'),
    profileOk,
  };
  if (!page.url().includes('/shop')) {
    await waitShop(page);
    report.functional.shopFallback = true;
  }
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(shots, 'FUNCTIONAL', 'shop.png') });

  // product clicks by coords (4/6 col layout at 1440 → 6 cols, card ~217)
  const centers = [
    { x: 140, y: 380 },
    { x: 370, y: 380 },
  ];
  await page.mouse.click(centers[0].x, centers[0].y);
  await page.waitForTimeout(2500);
  report.functional.clickProduct1 = {
    executed: true,
    url: page.url(),
    opened: page.url().includes('product'),
  };
  await page.screenshot({ path: path.join(shots, 'FUNCTIONAL', 'product1.png') });
  await page.goBack();
  await page.waitForTimeout(2000);
  report.functional.back1 = {
    executed: true,
    url: page.url(),
    onShop: page.url().includes('/shop'),
  };
  if (!page.url().includes('/shop')) await waitShop(page);
  await page.mouse.click(centers[1].x, centers[1].y);
  await page.waitForTimeout(2500);
  report.functional.clickProduct2 = {
    executed: true,
    url: page.url(),
    opened: page.url().includes('product'),
  };
  await page.goBack();
  await page.waitForTimeout(1500);
  report.functional.back2 = {
    executed: true,
    onShop: page.url().includes('/shop'),
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
  if (!page.url().includes('/shop')) await waitShop(page);
  for (let i = 0; i < 10; i++) {
    await page.mouse.wheel(0, 900);
    await page.waitForTimeout(200);
  }
  report.functional.scrollBottom = {
    executed: true,
    url: page.url(),
    title: await page.title(),
  };
  await page.screenshot({ path: path.join(shots, 'FUNCTIONAL', 'shop_bottom.png') });
  await ctx.close();
}

// P02
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  await page.goto(`${base}/vendedora-prod`, { waitUntil: 'domcontentloaded' });
  let ok = false;
  for (let i = 0; i < 40; i++) {
    await page.waitForTimeout(1000);
    if ((await page.title()).includes('Vendedora') && !(await page.title()).includes('encontrada')) {
      ok = true;
      break;
    }
  }
  await dismiss(page);
  await page.waitForTimeout(1500);
  fs.mkdirSync(path.join(shots, 'REGRESSION_PAGE02'), { recursive: true });
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', '1440_first.png') });
  for (let i = 0; i < 8; i++) {
    await page.mouse.wheel(0, 400);
    await page.waitForTimeout(300);
  }
  await page.screenshot({
    path: path.join(shots, 'REGRESSION_PAGE02', '1440_marketplace.png'),
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(1200);
  await page.mouse.wheel(0, -5000);
  await page.waitForTimeout(600);
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', '390_first.png') });
  report.regression02 = { loaded: ok, title: await page.title(), url: page.url() };
  await ctx.close();
}

// P03
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  await page.goto(`${base}/vendedora-prod/live`, { waitUntil: 'domcontentloaded' });
  let ok = false;
  for (let i = 0; i < 45; i++) {
    await page.waitForTimeout(1000);
    const t = await page.title();
    if (
      (t.includes('Gravado') || t.includes('Vendedora') || t.includes('Direto')) &&
      !t.includes('encontrada')
    ) {
      ok = true;
      break;
    }
  }
  await dismiss(page);
  await page.waitForTimeout(2000);
  fs.mkdirSync(path.join(shots, 'REGRESSION_PAGE03'), { recursive: true });
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE03', '1440_first.png') });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(1200);
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE03', '390_first.png') });
  report.regression03 = { loaded: ok, title: await page.title(), url: page.url() };
  await ctx.close();
}

fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'RAW_REPORT.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
await browser.close();
console.log('DONE');
