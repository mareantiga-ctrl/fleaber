import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '../..');
const base = 'http://127.0.0.1:8799';
const handle = 'fleahub-demo-ux';
const out = path.join(root, '05-opinioes-qa-seed');
const email = 'axinoquaa@axinoquaa.pt';
const password = 'testeteste';

const viewports = [
  { name: '390', width: 390, height: 844 },
  { name: '768', width: 768, height: 1024 },
  { name: '1024', width: 1024, height: 768 },
  { name: '1280', width: 1280, height: 800 },
  { name: '1440', width: 1440, height: 900 },
  { name: '1920', width: 1920, height: 1080 },
];

const report = {
  meta: { base, handle, at: new Date().toISOString(), method: 'maestroAutologin' },
  navigation: {},
  page05: {},
  page02: {},
  uiValidation: {},
  network: [],
};

async function dismissCookies(page) {
  for (let i = 0; i < 6; i++) {
    try {
      const btn = page.getByText('Aceitar', { exact: true }).first();
      if (await btn.isVisible({ timeout: 800 })) {
        await btn.click({ force: true });
        await page.waitForTimeout(600);
        return true;
      }
    } catch (_) {}
    const vp = page.viewportSize();
    if (vp) await page.mouse.click(Math.floor(vp.width * 0.72), vp.height - 36);
    await page.waitForTimeout(400);
  }
  return false;
}

async function waitContent(page, { minSec = 8, maxSec = 55 } = {}) {
  let lastTitle = '';
  for (let i = 0; i < maxSec; i++) {
    await page.waitForTimeout(1000);
    lastTitle = await page.title();
    if (lastTitle.includes('encontrada')) return { ok: false, reason: '404', title: lastTitle };
    if (i + 1 < minSec) continue;
    if (lastTitle.includes('A carregar') || lastTitle === 'Fleaber') continue;
    await dismissCookies(page);
    await page.waitForTimeout(800);
    return { ok: true, title: await page.title(), url: page.url(), waited: i + 1 };
  }
  return { ok: false, reason: 'timeout', title: lastTitle, url: page.url() };
}

async function loginAndGo(page, nextPath) {
  const next = encodeURIComponent(nextPath);
  const url = `${base}/maestroAutologin?email=${encodeURIComponent(email)}&password=${encodeURIComponent(password)}&next=${next}`;
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await dismissCookies(page);
  // wait redirect away from autologin
  for (let i = 0; i < 35; i++) {
    await page.waitForTimeout(1000);
    await dismissCookies(page);
    if (!page.url().includes('maestroAutologin')) break;
  }
  return waitContent(page);
}

function measure(vw) {
  let contentW = 480;
  if (vw >= 1100) contentW = 840;
  else if (vw >= 700) contentW = 720;
  return {
    viewportW: vw,
    contentMaxWidthToken: contentW,
    sideMarginApprox: Math.round(Math.max(0, (vw - contentW) / 2)),
    wastedSideApprox: Math.round(Math.max(0, vw - contentW)),
  };
}

const browser = await chromium.launch({ headless: true });

// Probe network on first load
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  page.on('response', async (r) => {
    const u = r.url();
    if (u.includes('hub_reviews') || u.includes('hub_profiles') || u.includes('token')) {
      let preview = '';
      try { preview = (await r.text()).slice(0, 200); } catch (_) {}
      report.network.push({ status: r.status(), url: u.slice(0, 180), preview });
    }
  });
  const ready = await loginAndGo(page, `/${handle}/reviews`);
  report.uiValidation.probeReviews = ready;
  await page.screenshot({ path: path.join(out, 'SCREENSHOTS/STATES/probe_autologin_reviews.png'), fullPage: true });
  console.log('probe', ready, page.url());
  console.log('network sample', report.network.slice(0, 8));
  await ctx.close();
}

// Navigation: seller → Ver todas
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  const sellerReady = await loginAndGo(page, `/${handle}`);
  report.navigation.sellerPage = sellerReady;
  const p02 = path.join(out, 'SCREENSHOTS/PAGE02/1440');
  fs.mkdirSync(p02, { recursive: true });
  await page.screenshot({ path: path.join(p02, 'first.png'), fullPage: false });
  await page.screenshot({ path: path.join(p02, 'full.png'), fullPage: true });

  let verTodas = { ok: false };
  try {
    // Flutter web: coordinate scan for "Ver todas" area is hard; try text engine if available
    const clicked = await page.evaluate(() => false);
    // Prefer semantic if present
    const el = page.locator('flt-semantics').filter({ hasText: /Ver todas/i });
    if (await el.count()) {
      await el.first().click({ timeout: 5000 });
      await page.waitForTimeout(2000);
      const after = await waitContent(page);
      verTodas = { ok: page.url().includes('/reviews'), ...after, method: 'semantics' };
    }
  } catch (e) {
    verTodas = { ok: false, error: String(e) };
  }
  if (!verTodas.ok) {
    await page.goto(`${base}/${handle}/reviews`, { waitUntil: 'domcontentloaded', timeout: 120000 });
    await dismissCookies(page);
    const after = await waitContent(page);
    verTodas = { ...after, method: 'direct_fallback', url: page.url() };
  }
  report.navigation.verTodas = verTodas;

  await page.goBack();
  await page.waitForTimeout(1500);
  report.navigation.backUrl = page.url();
  await page.goForward();
  await page.waitForTimeout(2000);
  await dismissCookies(page);
  report.navigation.forwardUrl = page.url();
  report.navigation.forwardOnReviews = page.url().includes('/reviews');
  await ctx.close();
}

// Capture all PAGE05
for (const vp of viewports) {
  const ctx = await browser.newContext({ viewport: { width: vp.width, height: vp.height } });
  const page = await ctx.newPage();
  const ready = await loginAndGo(page, `/${handle}/reviews`);
  // Extra settle for canvas paint
  await page.waitForTimeout(2000);
  await dismissCookies(page);
  const dir = path.join(out, 'SCREENSHOTS/PAGE05', vp.name);
  fs.mkdirSync(dir, { recursive: true });
  await page.screenshot({ path: path.join(dir, 'first.png'), fullPage: false });
  await page.screenshot({ path: path.join(dir, 'full.png'), fullPage: true });
  report.page05[vp.name] = { ready, measure: measure(vp.width), url: page.url(), title: await page.title() };
  console.log(`P05 ${vp.name}`, ready.title, ready.ok);
  await ctx.close();
}

// PAGE02 390
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  const ready = await loginAndGo(page, `/${handle}`);
  await page.waitForTimeout(2000);
  await dismissCookies(page);
  const dir = path.join(out, 'SCREENSHOTS/PAGE02/390');
  fs.mkdirSync(dir, { recursive: true });
  await page.screenshot({ path: path.join(dir, 'first.png'), fullPage: false });
  await page.screenshot({ path: path.join(dir, 'full.png'), fullPage: true });
  report.page02['390'] = { ready, url: page.url(), title: await page.title() };
  await ctx.close();
}

// Anon control
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await ctx.newPage();
  await page.goto(`${base}/${handle}/reviews`, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await dismissCookies(page);
  const ready = await waitContent(page);
  const dir = path.join(out, 'SCREENSHOTS/STATES');
  fs.mkdirSync(dir, { recursive: true });
  await page.screenshot({ path: path.join(dir, 'anon_guest.png'), fullPage: true });
  report.uiValidation.anon = ready;
  console.log('ANON', ready);
  await ctx.close();
}

fs.writeFileSync(path.join(out, 'RAW_CAPTURE.json'), JSON.stringify(report, null, 2));
console.log('DONE');
await browser.close();
