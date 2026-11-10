import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const base = 'http://localhost:8798';
const out = path.resolve('../../04-marketplace-final-validation');
const shots = path.join(out, 'SCREENSHOTS');
const report = { steps: [], regression02: {}, regression03: {}, console: { consoleErrors: [], pageErrors: [], failed: [] } };

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

page.on('console', (m) => { if (m.type() === 'error') report.console.consoleErrors.push(m.text()); });
page.on('pageerror', (e) => report.console.pageErrors.push(String(e)));
page.on('response', async (r) => {
  const u = r.url();
  if (u.includes('supabase') || u.includes('batata') || u.includes('rpc') || r.status() >= 400) {
    let body = '';
    try { body = (await r.text()).slice(0, 180); } catch (_) {}
    report.console.failed.push({ status: r.status(), url: u.slice(0, 180), body });
  }
});

async function dismiss() {
  try { await page.getByRole('button', { name: 'Aceitar' }).click({ timeout: 1200 }); } catch (_) {}
}

async function waitShop() {
  await page.goto(`${base}/vendedora-prod/shop`, { waitUntil: 'domcontentloaded', timeout: 120000 });
  for (let i = 0; i < 50; i++) {
    await page.waitForTimeout(1000);
    const t = await page.title();
    const text = await page.innerText('body').catch(() => '');
    if (t.includes('Marketplace') || text.includes('TESTE')) { await dismiss(); return true; }
  }
  return false;
}

const shopOk = await waitShop();
report.steps.push({ step: 'shop', ok: shopOk, title: await page.title(), url: page.url() });
await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', 'from_shop_baseline.png') });

// Click back arrow / FleaHub brand to seller page if possible
let wentProfile = false;
for (const name of ['Voltar', 'Back', 'FleaHub']) {
  const el = page.getByRole('button', { name: new RegExp(name, 'i') });
  if (await el.count()) {
    await el.first().click();
    await page.waitForTimeout(3000);
    wentProfile = true;
    break;
  }
}
// also try first back icon via aria
if (!wentProfile) {
  const backs = page.locator('[aria-label*="Back"], [aria-label*="Voltar"], [aria-label*="back"]');
  if (await backs.count()) {
    await backs.first().click();
    await page.waitForTimeout(3000);
    wentProfile = true;
  }
}

// Client-side navigation via history / push
if (!page.url().endsWith('/vendedora-prod') && !page.url().match(/\/vendedora-prod$/)) {
  await page.evaluate(() => history.pushState({}, '', '/vendedora-prod'));
  // Flutter may need a popstate or direct go_router
  await page.goto(`${base}/vendedora-prod`, { waitUntil: 'domcontentloaded' });
}

let profileOk = false;
for (let i = 0; i < 55; i++) {
  await page.waitForTimeout(1000);
  const t = await page.title();
  const text = await page.innerText('body').catch(() => '');
  report.steps.push({ i, t, hasVer: text.includes('Ver loja'), hasMkt: text.includes('Marketplace'), snippet: text.replace(/\s+/g,' ').slice(0,120) });
  if ((text.includes('Ver loja') || text.includes('Marketplace') || (t.includes('Vendedora') && !t.includes('encontrada')))) {
    profileOk = true;
    await dismiss();
    break;
  }
}

report.regression02 = {
  loaded: profileOk,
  title: await page.title(),
  url: page.url(),
  hasMarketplaceSection: (await page.innerText('body').catch(()=>'') ).includes('Marketplace'),
  hasVerLoja: (await page.innerText('body').catch(()=>'') ).includes('Ver loja'),
  wentProfileViaUi: wentProfile,
};
fs.mkdirSync(path.join(shots, 'REGRESSION_PAGE02'), { recursive: true });
await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', '1440_first.png') });
for (let i = 0; i < 14; i++) {
  await page.evaluate((y) => {
    const el = [...document.querySelectorAll('flt-semantics')].find((e) => e.scrollHeight > e.clientHeight + 20);
    if (el) el.scrollTop = y; else window.scrollTo(0, y);
  }, i * 450);
  await page.waitForTimeout(350);
  if ((await page.innerText('body').catch(()=>'') ).includes('Ver loja')) break;
}
await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', '1440_marketplace.png') });
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(1200);
await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', '390_first.png') });
report.regression02.mobileOk = profileOk;

// Live via client route from profile or direct
await page.setViewportSize({ width: 1440, height: 900 });
await page.goto(`${base}/vendedora-prod/live`, { waitUntil: 'domcontentloaded' });
let liveOk = false;
for (let i = 0; i < 55; i++) {
  await page.waitForTimeout(1000);
  const t = await page.title();
  const text = await page.innerText('body').catch(() => '');
  if (t.includes('Gravado') || text.includes('Saco') || text.includes('Chat') || text.includes('Produtos') || text.includes('Em direto') || (t.includes('Vendedora') && !t.includes('encontrada'))) {
    liveOk = true;
    await dismiss();
    break;
  }
}
const liveText = await page.innerText('body').catch(() => '');
report.regression03 = {
  loaded: liveOk,
  title: await page.title(),
  url: page.url(),
  hasProdutos: liveText.includes('Produtos'),
  hasChat: liveText.includes('Chat'),
  hasSaco: liveText.includes('Saco'),
  bodySample: liveText.replace(/\s+/g,' ').slice(0,280),
};
fs.mkdirSync(path.join(shots, 'REGRESSION_PAGE03'), { recursive: true });
await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE03', '1440_first.png') });
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(1200);
await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE03', '390_first.png') });

const prev = JSON.parse(fs.readFileSync(path.join(out, 'RAW_REPORT.json'), 'utf8'));
prev.regression02 = report.regression02;
prev.regression03 = report.regression03;
prev.diag = { steps: report.steps.slice(0, 8), networkSample: report.console.failed.slice(0, 30) };
prev.console = {
  consoleErrors: [...new Set([...(prev.console.consoleErrors||[]), ...report.console.consoleErrors])],
  pageErrors: [...new Set([...(prev.console.pageErrors||[]), ...report.console.pageErrors])],
  failedRequests: [...(prev.console.failedRequests||[]), ...report.console.failed.filter(f => f.status>=400)].slice(0, 40),
};
fs.writeFileSync(path.join(out, 'RAW_REPORT.json'), JSON.stringify(prev, null, 2));
console.log(JSON.stringify({ regression02: report.regression02, regression03: report.regression03, net: report.console.failed.slice(0,20), steps: report.steps.slice(0,6) }, null, 2));
await browser.close();
console.log('DONE');
