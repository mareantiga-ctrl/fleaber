import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const base = process.argv[2] ?? 'http://localhost:8798';
const handle = 'vendedora-prod';
const shopUrl = `${base}/${handle}/shop`;
const profileUrl = `${base}/${handle}`;
const liveUrl = `${base}/${handle}/live`;
const out = path.resolve('../../04-marketplace-final-validation');
const shots = path.join(out, 'SCREENSHOTS');

const report = {
  viewports: null, // filled from prior RAW or MEASUREMENTS
  functional: {},
  regression02: {},
  regression03: {},
  console: { consoleErrors: [], pageErrors: [], failedRequests: [] },
  meta: { base, startedAt: new Date().toISOString() },
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
    await page.getByRole('button', { name: 'Aceitar' }).click({ timeout: 1500 });
  } catch (_) {}
}

async function scrollSem(page, y) {
  await page.evaluate((target) => {
    const el = [...document.querySelectorAll('flt-semantics')].find(
      (e) => e.scrollHeight > e.clientHeight + 20,
    );
    if (el) el.scrollTop = target;
    else window.scrollTo(0, target);
  }, y);
  await page.waitForTimeout(500);
}

async function waitForContent(page, pred, secs = 55) {
  for (let i = 0; i < secs; i++) {
    await page.waitForTimeout(1000);
    const t = await page.title();
    const text = await page.innerText('body').catch(() => '');
    if (pred(t, text)) {
      await dismiss(page);
      return true;
    }
  }
  return false;
}

async function gotoRetry(page, url, pred, attempts = 4) {
  for (let a = 0; a < attempts; a++) {
    const resp = await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 120000,
    });
    const status = resp?.status() ?? 0;
    if (status === 404 && a < attempts - 1) {
      await page.waitForTimeout(2000);
      continue;
    }
    if (await waitForContent(page, pred, 50)) return true;
    await page.waitForTimeout(2000);
  }
  return false;
}

function isShop(t, text) {
  return (
    t.includes('Marketplace') ||
    text.includes('@vendedora-prod · Marketplace') ||
    text.includes('TESTE') ||
    text.includes('Cachecol')
  );
}

function isProfile(t, text) {
  return (
    text.includes('Ver loja') ||
    text.includes('Marketplace') ||
    t.includes('Vendedora') ||
    (text.toLowerCase().includes('vendedora') && !t.includes('encontrada'))
  );
}

function isLive(t, text) {
  return (
    t.includes('Gravado') ||
    t.includes('Vendedora') ||
    text.includes('Saco') ||
    text.includes('Chat') ||
    text.includes('Produtos') ||
    text.includes('Em direto') ||
    text.includes('Gravação')
  );
}

async function productButtons(page) {
  return page.locator('[role=button]').filter({ hasText: '€' });
}

const browser = await chromium.launch({ headless: true });

// ---------- Functional A–K ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);

  const profileOk = await gotoRetry(page, profileUrl, isProfile);
  report.functional.profileLoaded = profileOk;
  report.functional.profileTitle = await page.title();
  report.functional.profileUrl = page.url();

  let verClicked = false;
  if (profileOk) {
    for (let i = 0; i < 24; i++) {
      await scrollSem(page, i * 400);
      const btn = page.getByRole('button', { name: /Ver loja/i });
      const txt = page.getByText('Ver loja', { exact: true });
      const target =
        (await btn.count()) > 0 ? btn.first() : (await txt.count()) > 0 ? txt.first() : null;
      if (target) {
        await target.click();
        verClicked = true;
        break;
      }
    }
  }

  if (verClicked) {
    await page.waitForTimeout(3000);
    const text = await page.innerText('body').catch(() => '');
    report.functional.verLoja = {
      executed: true,
      url: page.url(),
      onShop:
        page.url().includes('/shop') ||
        (await page.title()).includes('Marketplace') ||
        text.includes('@vendedora-prod · Marketplace'),
    };
  } else {
    report.functional.verLoja = {
      executed: false,
      reason: profileOk ? 'Ver loja not found' : 'profile load fail',
    };
  }

  if (!report.functional.verLoja?.onShop) {
    const shopOk = await gotoRetry(page, shopUrl, isShop);
    report.functional.shopFallback = { executed: true, ok: shopOk, url: page.url() };
  }

  await waitForContent(page, (t, text) => text.includes('TESTE') || text.includes('€'), 25);
  let prods = await productButtons(page);
  let pc = await prods.count();
  report.functional.productButtons = pc;

  if (pc >= 1) {
    const l1 = (await prods.nth(0).innerText()).slice(0, 100);
    await prods.nth(0).click();
    await page.waitForTimeout(3000);
    const url1 = page.url();
    const t1 = await page.title();
    const body1 = await page.innerText('body').catch(() => '');
    report.functional.clickProduct1 = {
      executed: true,
      label: l1,
      url: url1,
      title: t1,
      openedProductDetails:
        url1.includes('product') ||
        body1.includes('Comprar') ||
        body1.includes('Adicionar') ||
        t1.toLowerCase().includes('produto') ||
        !url1.includes('/shop'),
    };
    fs.mkdirSync(path.join(shots, 'FUNCTIONAL'), { recursive: true });
    await page.screenshot({
      path: path.join(shots, 'FUNCTIONAL', 'product1.png'),
      fullPage: false,
    });

    await page.goBack();
    await page.waitForTimeout(2500);
    report.functional.backAfterProduct1 = {
      executed: true,
      url: page.url(),
      backOnShop: page.url().includes('/shop') || (await page.title()).includes('Marketplace'),
    };
  } else {
    report.functional.clickProduct1 = { executed: false, reason: 'no product buttons' };
  }

  prods = await productButtons(page);
  pc = await prods.count();
  if (pc >= 2) {
    const l2 = (await prods.nth(1).innerText()).slice(0, 100);
    await prods.nth(1).click();
    await page.waitForTimeout(3000);
    const url2 = page.url();
    report.functional.clickProduct2 = {
      executed: true,
      label: l2,
      url: url2,
      openedProductDetails: url2.includes('product') || !url2.includes('/shop'),
    };
    await page.screenshot({
      path: path.join(shots, 'FUNCTIONAL', 'product2.png'),
      fullPage: false,
    });

    await page.goBack();
    await page.waitForTimeout(2000);
    report.functional.backAfterProduct2 = {
      executed: true,
      url: page.url(),
      backOnShop: page.url().includes('/shop'),
    };

    await page.goForward();
    await page.waitForTimeout(2000);
    report.functional.forward = {
      executed: true,
      url: page.url(),
      onProduct: page.url().includes('product') || !page.url().includes('/shop'),
    };
    await page.goBack();
    await page.waitForTimeout(1500);
  } else {
    report.functional.clickProduct2 = { executed: false, reason: `only ${pc} products` };
    report.functional.forward = { executed: false };
  }

  if (!page.url().includes('/shop')) {
    await gotoRetry(page, shopUrl, isShop);
  }
  await scrollSem(page, 99999);
  await page.waitForTimeout(800);
  const atBottom = await productButtons(page);
  report.functional.scrollBottom = {
    executed: true,
    productsAtBottom: await atBottom.count(),
    url: page.url(),
    title: await page.title(),
  };
  await page.screenshot({
    path: path.join(shots, 'FUNCTIONAL', 'shop_bottom.png'),
    fullPage: false,
  });

  await ctx.close();
}

// ---------- P02 regression ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  const ok = await gotoRetry(page, profileUrl, isProfile);
  const text = await page.innerText('body').catch(() => '');
  report.regression02 = {
    loaded: ok,
    title: await page.title(),
    url: page.url(),
    hasMarketplaceSection: text.includes('Marketplace'),
    hasVerLoja: text.includes('Ver loja'),
  };
  fs.mkdirSync(path.join(shots, 'REGRESSION_PAGE02'), { recursive: true });
  await page.screenshot({
    path: path.join(shots, 'REGRESSION_PAGE02', '1440_first.png'),
    fullPage: false,
  });
  // scroll marketplace preview
  for (let i = 0; i < 10; i++) {
    await scrollSem(page, i * 400);
    if ((await page.innerText('body').catch(() => '')).includes('Ver loja')) break;
  }
  await page.screenshot({
    path: path.join(shots, 'REGRESSION_PAGE02', '1440_marketplace.png'),
    fullPage: false,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(1500);
  await scrollSem(page, 0);
  await page.screenshot({
    path: path.join(shots, 'REGRESSION_PAGE02', '390_first.png'),
    fullPage: false,
  });
  report.regression02.mobileOk =
    !(await page.title()).includes('encontrada') && report.regression02.loaded;
  await ctx.close();
}

// ---------- P03 regression ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  const ok = await gotoRetry(page, liveUrl, isLive);
  const text = await page.innerText('body').catch(() => '');
  report.regression03 = {
    loaded: ok,
    title: await page.title(),
    url: page.url(),
    hasProdutos: text.includes('Produtos'),
    hasChat: text.includes('Chat'),
    hasSaco: text.includes('Saco'),
    bodySample: text.replace(/\s+/g, ' ').slice(0, 240),
  };
  fs.mkdirSync(path.join(shots, 'REGRESSION_PAGE03'), { recursive: true });
  await page.screenshot({
    path: path.join(shots, 'REGRESSION_PAGE03', '1440_first.png'),
    fullPage: false,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(1500);
  await page.screenshot({
    path: path.join(shots, 'REGRESSION_PAGE03', '390_first.png'),
    fullPage: false,
  });
  await ctx.close();
}

// merge prior viewport measurements if present
try {
  const prev = JSON.parse(fs.readFileSync(path.join(out, 'RAW_REPORT.json'), 'utf8'));
  if (prev.viewports) report.viewports = prev.viewports;
} catch (_) {}

fs.writeFileSync(path.join(out, 'RAW_REPORT.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
await browser.close();
console.log('DONE');
