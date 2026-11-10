import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const base = 'http://localhost:8798';
const handle = 'vendedora-prod';
const out = path.resolve('../../04-marketplace-final-validation');
const shots = path.join(out, 'SCREENSHOTS');
const report = { regression02: {}, regression03: {}, console: { consoleErrors: [], pageErrors: [], failedRequests: [] } };

function wire(page) {
  page.on('console', (m) => { if (m.type() === 'error') report.console.consoleErrors.push(m.text()); });
  page.on('pageerror', (e) => report.console.pageErrors.push(String(e)));
  page.on('response', (r) => { if (r.status() >= 400) report.console.failedRequests.push({ status: r.status(), url: r.url().slice(0,160) }); });
}

async function dismiss(page) {
  try { await page.getByRole('button', { name: 'Aceitar' }).click({ timeout: 1500 }); } catch (_) {}
}

async function scrollSem(page, y) {
  await page.evaluate((target) => {
    const el = [...document.querySelectorAll('flt-semantics')].find((e) => e.scrollHeight > e.clientHeight + 20);
    if (el) el.scrollTop = target; else window.scrollTo(0, target);
  }, y);
  await page.waitForTimeout(400);
}

async function load(page, url, okPred) {
  for (let attempt = 0; attempt < 6; attempt++) {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120000 });
    for (let i = 0; i < 60; i++) {
      await page.waitForTimeout(1000);
      const t = await page.title();
      const text = await page.innerText('body').catch(() => '');
      if (okPred(t, text)) { await dismiss(page); return { ok: true, t, text }; }
      // known transient 404 while resolve runs — keep waiting same navigation
      if (t.includes('encontrada') && i < 25) continue;
      if (t.includes('encontrada') && i >= 25) break;
    }
    await page.waitForTimeout(1500);
  }
  return { ok: false, t: await page.title(), text: await page.innerText('body').catch(() => '') };
}

const browser = await chromium.launch({ headless: true });

{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  const r = await load(page, `${base}/${handle}`, (t, text) =>
    text.includes('Ver loja') || text.includes('Marketplace') || (t.includes('Vendedora') && !t.includes('encontrada'))
  );
  report.regression02 = {
    loaded: r.ok,
    title: r.t,
    url: page.url(),
    hasMarketplaceSection: (r.text||'').includes('Marketplace'),
    hasVerLoja: (r.text||'').includes('Ver loja'),
  };
  fs.mkdirSync(path.join(shots, 'REGRESSION_PAGE02'), { recursive: true });
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', '1440_first.png') });
  for (let i = 0; i < 12; i++) {
    await scrollSem(page, i * 450);
    if ((await page.innerText('body').catch(()=>'') ).includes('Ver loja')) break;
  }
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', '1440_marketplace.png') });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(1500);
  await scrollSem(page, 0);
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE02', '390_first.png') });
  report.regression02.mobileOk = r.ok && !(await page.title()).includes('encontrada');
  await ctx.close();
}

{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  // warm via profile first (reduces resolve flake)
  await load(page, `${base}/${handle}`, (t, text) => text.includes('Marketplace') || t.includes('Vendedora'));
  const r = await load(page, `${base}/${handle}/live`, (t, text) =>
    t.includes('Gravado') || text.includes('Saco') || text.includes('Chat') || text.includes('Produtos') ||
    text.includes('Em direto') || text.includes('Gravação') || (t.includes('Vendedora') && !t.includes('encontrada'))
  );
  report.regression03 = {
    loaded: r.ok,
    title: r.t,
    url: page.url(),
    hasProdutos: (r.text||'').includes('Produtos'),
    hasChat: (r.text||'').includes('Chat'),
    hasSaco: (r.text||'').includes('Saco'),
    bodySample: (r.text||'').replace(/\s+/g,' ').slice(0,280),
  };
  fs.mkdirSync(path.join(shots, 'REGRESSION_PAGE03'), { recursive: true });
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE03', '1440_first.png') });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(shots, 'REGRESSION_PAGE03', '390_first.png') });
  await ctx.close();
}

const prev = JSON.parse(fs.readFileSync(path.join(out, 'RAW_REPORT.json'), 'utf8'));
prev.regression02 = report.regression02;
prev.regression03 = report.regression03;
prev.console.consoleErrors = [...(prev.console.consoleErrors||[]), ...report.console.consoleErrors];
prev.console.pageErrors = [...(prev.console.pageErrors||[]), ...report.console.pageErrors];
prev.console.failedRequests = [...(prev.console.failedRequests||[]), ...report.console.failedRequests];
prev.meta = { ...(prev.meta||{}), regressionRetestAt: new Date().toISOString() };
fs.writeFileSync(path.join(out, 'RAW_REPORT.json'), JSON.stringify(prev, null, 2));
console.log(JSON.stringify(report, null, 2));
await browser.close();
console.log('DONE');
