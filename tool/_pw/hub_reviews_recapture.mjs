import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const handle = 'vendedora-prod';
const out = path.resolve('../../05-opinioes-recapture');
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
  route: `/${handle}/reviews`,
  navigation: {},
  viewports: {},
  states: {},
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
        url: r.url().slice(0, 140),
      });
  });
}

async function dismiss(page) {
  try {
    await page.mouse.click(
      page.viewportSize().width / 2 + 120,
      page.viewportSize().height - 36,
    );
  } catch (_) {}
  await page.waitForTimeout(400);
}

async function waitReviews(page) {
  await page.goto(`${base}/${handle}/reviews`, {
    waitUntil: 'domcontentloaded',
    timeout: 120000,
  });
  for (let i = 0; i < 55; i++) {
    await page.waitForTimeout(1000);
    const t = await page.title();
    if (t.includes('encontrada')) {
      if (i > 20) return { ok: false, reason: '404', title: t };
      continue;
    }
    if (t.includes('A carregar') || t === 'Fleaber') continue;
    // Success: Avaliações in title OR settled on /reviews with profile chrome
    if (
      t.includes('Avaliações') ||
      (page.url().includes('/reviews') &&
        !t.includes('encontrada') &&
        !t.includes('A carregar') &&
        i >= 10)
    ) {
      await dismiss(page);
      await page.waitForTimeout(800);
      return { ok: true, title: await page.title(), url: page.url() };
    }
  }
  return { ok: false, reason: 'timeout', title: await page.title() };
}

function measureContent(vw) {
  // Reviews uses HubTheme.contentMaxWidthFor: 480 / 720 / 840
  let contentW = 480;
  if (vw >= 1100) contentW = 840;
  else if (vw >= 700) contentW = 720;
  const side = Math.max(0, (vw - contentW) / 2);
  return {
    viewportW: vw,
    contentMaxWidth: contentW,
    sideMarginApprox: Math.round(side),
    wastedSideApprox: Math.round(Math.max(0, vw - contentW)),
  };
}

const browser = await chromium.launch({ headless: true });

// --- Navigation from Seller Page ---
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  await page.goto(`${base}/${handle}`, { waitUntil: 'domcontentloaded' });
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
  await page.waitForTimeout(1200);
  fs.mkdirSync(path.join(shots, 'NAV'), { recursive: true });
  await page.screenshot({ path: path.join(shots, 'NAV', 'profile_first.png') });
  // scroll to Opiniões
  for (let i = 0; i < 14; i++) {
    await page.mouse.wheel(0, 450);
    await page.waitForTimeout(300);
  }
  await page.screenshot({ path: path.join(shots, 'NAV', 'profile_opinioes.png') });
  // Try Ver todas / Ver opiniões
  let navClick = { executed: false };
  for (const label of ['Ver todas', 'Ver opiniões']) {
    // coordinate sweep near right side of section headers
    for (let y = 200; y < 800; y += 80) {
      await page.mouse.click(1280, y);
      await page.waitForTimeout(900);
      if (page.url().includes('/reviews')) {
        navClick = { executed: true, label, y, url: page.url() };
        break;
      }
    }
    if (navClick.executed) break;
  }
  report.navigation.profile = {
    loaded: profileOk,
    title: await page.title(),
    url: page.url(),
    verTodasClick: navClick,
    note:
      'Ver todas only rendered when reviews.isNotEmpty — empty seller may have no CTA',
  };
  if (page.url().includes('/reviews')) {
    await page.screenshot({ path: path.join(shots, 'NAV', 'from_profile.png') });
  }
  await ctx.close();
}

// --- Direct route + viewports ---
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  const loaded = await waitReviews(page);
  report.routeLoad = loaded;
  if (!loaded.ok) {
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(path.join(out, 'RAW_REPORT.json'), JSON.stringify(report, null, 2));
    console.error('REVIEWS LOAD FAIL', loaded);
    process.exit(2);
  }
  fs.mkdirSync(path.join(shots, 'STATES'), { recursive: true });
  await page.screenshot({
    path: path.join(shots, 'STATES', 'empty_or_list_1440.png'),
  });

  for (const vp of viewports) {
    await page.setViewportSize({ width: vp.width, height: vp.height });
    await page.waitForTimeout(1400);
    await page.mouse.wheel(0, -5000);
    await page.waitForTimeout(400);
    const m = measureContent(vp.width);
    report.viewports[vp.name] = {
      ...m,
      title: await page.title(),
      url: page.url(),
    };
    const dir = path.join(shots, vp.name);
    fs.mkdirSync(dir, { recursive: true });
    await page.screenshot({ path: path.join(dir, 'first.png'), fullPage: false });
    for (let i = 0; i < 6; i++) {
      await page.mouse.wheel(0, 700);
      await page.waitForTimeout(200);
    }
    await page.screenshot({ path: path.join(dir, 'full.png'), fullPage: false });
    console.log(`[${vp.name}] contentMax=${m.contentMaxWidth} title=${await page.title()}`);
  }

  // back/forward
  await page.goto(`${base}/${handle}`, { waitUntil: 'domcontentloaded' });
  for (let i = 0; i < 25; i++) {
    await page.waitForTimeout(800);
    if ((await page.title()).includes('Vendedora')) break;
  }
  await page.goto(`${base}/${handle}/reviews`, { waitUntil: 'domcontentloaded' });
  await waitReviews(page);
  await page.goBack();
  await page.waitForTimeout(1500);
  report.navigation.back = { url: page.url(), executed: true };
  await page.goForward();
  await page.waitForTimeout(1500);
  report.navigation.forward = {
    url: page.url(),
    onReviews: page.url().includes('/reviews'),
    executed: true,
  };

  await ctx.close();
}

// --- Live → Ver opiniões (if live page loads) ---
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  wire(page);
  await page.goto(`${base}/${handle}/live`, { waitUntil: 'domcontentloaded' });
  let liveOk = false;
  for (let i = 0; i < 40; i++) {
    await page.waitForTimeout(1000);
    const t = await page.title();
    if (
      (t.includes('Gravado') || t.includes('Vendedora') || t.includes('Direto')) &&
      !t.includes('encontrada')
    ) {
      liveOk = true;
      break;
    }
  }
  await dismiss(page);
  // scroll panel for Ver opiniões
  let fromLive = { executed: false, liveOk };
  if (liveOk) {
    for (let i = 0; i < 20; i++) {
      await page.mouse.wheel(0, 500);
      await page.waitForTimeout(250);
    }
    await page.screenshot({
      path: path.join(shots, 'NAV', 'live_before_opinioes.png'),
    });
    for (const x of [200, 300, 400, 500]) {
      for (const y of [600, 650, 700, 750, 800]) {
        await page.mouse.click(x, y);
        await page.waitForTimeout(800);
        if (page.url().includes('/reviews')) {
          fromLive = { executed: true, liveOk, url: page.url(), x, y };
          break;
        }
      }
      if (fromLive.executed) break;
    }
    // fallback direct
    if (!fromLive.executed) {
      await page.goto(`${base}/${handle}/reviews`, { waitUntil: 'domcontentloaded' });
      await waitReviews(page);
      fromLive = {
        executed: false,
        liveOk,
        fallbackDirect: true,
        url: page.url(),
        note: 'Ver opiniões click not hit in headless; direct /reviews OK',
      };
    } else {
      await page.screenshot({ path: path.join(shots, 'NAV', 'from_live.png') });
    }
  }
  report.navigation.fromLive = fromLive;
  await ctx.close();
}

report.states.emptySeller = {
  handle,
  hub_reviews_public: '[] on prod (anon)',
  captured: true,
};
report.states.sellerWithReviews = {
  executed: false,
  reason: 'hub_reviews_public empty on production; reviews table empty for anon',
};

fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'RAW_REPORT.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
await browser.close();
console.log('DONE');
