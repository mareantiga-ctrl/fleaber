import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const base = process.argv[2] ?? 'http://localhost:8796';
const handle = 'vendedora-prod';
const shopUrl = `${base}/${handle}/shop`;
const profileUrl = `${base}/${handle}`;
const liveUrl = `${base}/${handle}/live`;
const outRoot = path.resolve('../../04-marketplace-final-validation/SCREENSHOTS');

const viewports = [
  { name: '390', width: 390, height: 844 },
  { name: '768', width: 768, height: 1024 },
  { name: '1024', width: 1024, height: 768 },
  { name: '1280', width: 1280, height: 800 },
  { name: '1440', width: 1440, height: 900 },
  { name: '1920', width: 1920, height: 1080 },
];

async function dismissCookies(page) {
  try {
    const accept = page.getByRole('button', { name: 'Aceitar' });
    if (await accept.count()) await accept.first().click({ timeout: 1500 });
  } catch (_) {}
}

async function waitShop(page) {
  for (let attempt = 0; attempt < 4; attempt++) {
    await page.goto(shopUrl, { waitUntil: 'domcontentloaded', timeout: 120000 });
    // Hub resolve pode mostrar 404 breve — esperar até 45s na mesma navegação.
    for (let i = 0; i < 45; i++) {
      await page.waitForTimeout(1000);
      const t = await page.title();
      const text = await page.innerText('body').catch(() => '');
      if (
        t.includes('Marketplace') ||
        text.includes('TESTE') ||
        text.includes('Cachecol') ||
        text.includes('@vendedora-prod · Marketplace')
      ) {
        await dismissCookies(page);
        // esperar produtos no a11y
        for (let j = 0; j < 15; j++) {
          const n = await page
            .locator('[role=button]')
            .filter({ hasText: '€' })
            .count();
          if (n > 0) break;
          await page.waitForTimeout(500);
        }
        await page.waitForTimeout(500);
        return true;
      }
    }
    await page.waitForTimeout(2000);
  }
  return false;
}

async function waitProfile(page) {
  await page.goto(profileUrl, { waitUntil: 'domcontentloaded', timeout: 120000 });
  for (let i = 0; i < 35; i++) {
    await page.waitForTimeout(1000);
    const text = await page.innerText('body').catch(() => '');
    const t = await page.title();
    if (
      text.includes('Marketplace') ||
      text.includes('Ver loja') ||
      text.includes('vendedora') ||
      t.includes('Vendedora')
    ) {
      await dismissCookies(page);
      return true;
    }
    if (t.includes('encontrada') && i > 10) break;
  }
  return false;
}

async function measureGrid(page) {
  return page.evaluate(() => {
    const cards = [...document.querySelectorAll('[role=button],button')]
      .map((b) => {
        const n = b.getAttribute('aria-label') || b.innerText || '';
        const r = b.getBoundingClientRect();
        return {
          n,
          w: Math.round(r.width),
          h: Math.round(r.height),
          x: Math.round(r.x),
          y: Math.round(r.y),
        };
      })
      .filter((b) => b.n.includes('€') && b.h > 60);
    if (!cards.length) {
      return {
        cols: 0,
        cards: 0,
        vw: innerWidth,
        vh: innerHeight,
        title: document.title,
      };
    }
    const y = Math.min(...cards.map((c) => c.y));
    const row = cards
      .filter((c) => Math.abs(c.y - y) < 50)
      .sort((a, b) => a.x - b.x);
    const gutters = [];
    for (let i = 1; i < row.length; i++) {
      gutters.push(row[i].x - (row[i - 1].x + row[i - 1].w));
    }
    return {
      cols: row.length,
      cardsVisible: cards.length,
      cardW: row[0]?.w,
      cardH: row[0]?.h,
      contentLeft: row[0]?.x,
      contentRight: row.at(-1).x + row.at(-1).w,
      contentWidth: row.at(-1).x + row.at(-1).w - row[0].x,
      gutters,
      sideMarginLeft: row[0]?.x,
      sideMarginRight: innerWidth - (row.at(-1).x + row.at(-1).w),
      vw: innerWidth,
      vh: innerHeight,
      title: document.title,
      sampleTitles: row.map((r) => r.n.split('\n')[0].slice(0, 40)),
    };
  });
}

async function scrollSemantics(page, y) {
  await page.evaluate((target) => {
    const el = [...document.querySelectorAll('flt-semantics')].find(
      (e) => e.scrollHeight > e.clientHeight + 20,
    );
    if (el) el.scrollTop = target;
    else window.scrollTo(0, target);
  }, y);
  await page.waitForTimeout(700);
}

async function collectConsole(page, bag) {
  page.on('console', (msg) => {
    if (msg.type() === 'error') bag.consoleErrors.push(msg.text());
  });
  page.on('pageerror', (err) => {
    bag.pageErrors.push(String(err));
  });
  page.on('response', (res) => {
    if (res.status() >= 400) {
      bag.failedRequests.push({
        status: res.status(),
        url: res.url().slice(0, 160),
      });
    }
  });
}

const browser = await chromium.launch({ headless: true });
const report = {
  viewports: {},
  functional: {},
  regression02: {},
  regression03: {},
  console: { consoleErrors: [], pageErrors: [], failedRequests: [] },
};

// --- Viewport suite: load once at 390 then resize (avoids resolve flakiness)
{
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
  });
  const page = await context.newPage();
  collectConsole(page, report.console);
  const ok = await waitShop(page);
  report.viewports.loadOk = ok;
  report.viewports.loadTitle = await page.title();
  if (!ok) {
    console.error('SHOP LOAD FAILED');
    fs.writeFileSync(
      path.join(outRoot, '..', 'RAW_REPORT.json'),
      JSON.stringify(report, null, 2),
    );
    await browser.close();
    process.exit(2);
  }

  for (const vp of viewports) {
    await page.setViewportSize({ width: vp.width, height: vp.height });
    await page.waitForTimeout(1800);
    await scrollSemantics(page, 0);
    await page.waitForTimeout(500);
    const m = await measureGrid(page);
    report.viewports[vp.name] = m;
    const dir = path.join(outRoot, vp.name);
    fs.mkdirSync(dir, { recursive: true });
    await page.screenshot({
      path: path.join(dir, 'first.png'),
      fullPage: false,
    });
    await scrollSemantics(page, 99999);
    await page.waitForTimeout(600);
    await page.screenshot({
      path: path.join(dir, 'full.png'),
      fullPage: false,
    });
    await scrollSemantics(page, 0);
    console.log(`[${vp.name}] cols=${m.cols} card=${m.cardW}x${m.cardH}`);
  }
  await context.close();
}

// --- Functional A–K
{
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
  });
  const page = await context.newPage();
  collectConsole(page, report.console);

  // A/B Ver loja
  const profileOk = await waitProfile(page);
  report.functional.profileLoaded = profileOk;
  let verLoja = null;
  if (profileOk) {
    // scroll to marketplace section
    for (let i = 0; i < 12; i++) {
      await scrollSemantics(page, i * 400);
      await page.waitForTimeout(300);
      const btn = page.getByRole('button', { name: /Ver loja/i });
      if (await btn.count()) {
        verLoja = btn.first();
        break;
      }
      // Flutter sometimes exposes as text button
      const t = page.getByText('Ver loja', { exact: true });
      if (await t.count()) {
        verLoja = t.first();
        break;
      }
    }
    if (verLoja) {
      await verLoja.click();
      await page.waitForTimeout(2500);
      const url = page.url();
      const text = await page.innerText('body').catch(() => '');
      report.functional.verLoja = {
        executed: true,
        url,
        onShop:
          url.includes('/shop') ||
          text.includes('@vendedora-prod · Marketplace') ||
          (await page.title()).includes('Marketplace'),
      };
    } else {
      report.functional.verLoja = {
        executed: false,
        reason: 'Ver loja button not found in a11y tree',
      };
      // fallback navigate
      await waitShop(page);
    }
  } else {
    report.functional.verLoja = { executed: false, reason: 'profile load fail' };
    await waitShop(page);
  }

  // Ensure on shop
  if (!page.url().includes('/shop')) await waitShop(page);

  // C–G product clicks
  const productBtns = page
    .locator('[role=button]')
    .filter({ hasText: '€' });
  const count = await productBtns.count();
  report.functional.productButtons = count;
  if (count >= 1) {
    const label1 = await productBtns.nth(0).innerText().catch(() => '');
    await productBtns.nth(0).click();
    await page.waitForTimeout(2500);
    const url1 = page.url();
    report.functional.clickProduct1 = {
      executed: true,
      label: label1.slice(0, 80),
      url: url1,
      openedProductDetails: url1.includes('productDetails') || url1.includes('product_id'),
    };
    await page.goBack();
    await page.waitForTimeout(2000);
    report.functional.backAfterProduct1 = {
      executed: true,
      url: page.url(),
      backOnShop: page.url().includes('/shop'),
    };
  } else {
    report.functional.clickProduct1 = { executed: false };
  }

  if ((await productBtns.count()) >= 2) {
    const label2 = await productBtns.nth(1).innerText().catch(() => '');
    await productBtns.nth(1).click();
    await page.waitForTimeout(2500);
    const url2 = page.url();
    report.functional.clickProduct2 = {
      executed: true,
      label: label2.slice(0, 80),
      url: url2,
      openedProductDetails: url2.includes('productDetails') || url2.includes('product_id'),
    };
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
      onProduct:
        page.url().includes('productDetails') || page.url().includes('product_id'),
    };
    await page.goBack();
    await page.waitForTimeout(1200);
  } else {
    report.functional.clickProduct2 = { executed: false };
    report.functional.forward = { executed: false };
  }

  // H/I scroll
  await waitShop(page);
  await scrollSemantics(page, 99999);
  await page.waitForTimeout(800);
  const afterScroll = await measureGrid(page);
  report.functional.scrollBottom = {
    executed: true,
    cols: afterScroll.cols,
    cardsVisible: afterScroll.cardsVisible,
  };
  // count product buttons with €
  report.functional.productsAtBottom = await page
    .locator('[role=button]')
    .filter({ hasText: '€' })
    .count();

  await context.close();
}

// --- Regression Page 02
{
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
  });
  const page = await context.newPage();
  collectConsole(page, report.console);
  const ok = await waitProfile(page);
  report.regression02.loaded = ok;
  report.regression02.title = await page.title();
  report.regression02.url = page.url();
  const text = await page.innerText('body').catch(() => '');
  report.regression02.hasMarketplaceSection = text.includes('Marketplace');
  report.regression02.hasVerLoja = text.includes('Ver loja');
  const dir = path.join(outRoot, 'REGRESSION_PAGE02');
  fs.mkdirSync(dir, { recursive: true });
  await page.screenshot({ path: path.join(dir, '1440_first.png') });
  // mobile smoke
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(dir, '390_first.png') });
  report.regression02.mobileOk = !(await page.title()).includes('encontrada');
  await context.close();
}

// --- Regression Page 03 smoke
{
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
  });
  const page = await context.newPage();
  collectConsole(page, report.console);
  await page.goto(liveUrl, { waitUntil: 'domcontentloaded', timeout: 120000 });
  let ok = false;
  for (let i = 0; i < 35; i++) {
    await page.waitForTimeout(1000);
    const t = await page.title();
    const text = await page.innerText('body').catch(() => '');
    if (
      t.includes('Gravado') ||
      t.includes('Vendedora') ||
      text.includes('Produtos') ||
      text.includes('Saco') ||
      text.includes('Chat')
    ) {
      ok = true;
      break;
    }
    if (t.includes('encontrada') && i > 12) break;
  }
  await dismissCookies(page);
  report.regression03.loaded = ok;
  report.regression03.title = await page.title();
  report.regression03.url = page.url();
  const text = await page.innerText('body').catch(() => '');
  report.regression03.hasProdutos = text.includes('Produtos');
  report.regression03.hasChat = text.includes('Chat');
  report.regression03.hasSaco = text.includes('Saco');
  const dir = path.join(outRoot, 'REGRESSION_PAGE03');
  fs.mkdirSync(dir, { recursive: true });
  await page.screenshot({ path: path.join(dir, '1440_first.png') });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(dir, '390_first.png') });
  report.regression03.mobileTitle = await page.title();
  await context.close();
}

fs.writeFileSync(
  path.resolve('../../04-marketplace-final-validation/RAW_REPORT.json'),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
await browser.close();
console.log('DONE');
