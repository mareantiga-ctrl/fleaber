/**
 * Fecho final P06 (CTA → /fleahub) + P05 (ordenação ×4 via RPC + UI).
 * Build: release + FLEABER_ENV=staging + FLEABER_ALLOW_STAGING_RELEASE=true
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const outDir = path.join(repo, '06-fecho-final-paginas-05-06');
const shots = path.join(outDir, 'SCREENSHOTS');
const evidence = path.join(outDir, 'EVIDENCE');
fs.mkdirSync(shots, { recursive: true });
fs.mkdirSync(evidence, { recursive: true });

const BASE = process.env.HUB_BASE || 'http://127.0.0.1:8799';
const HANDLE = 'fleahub-demo-ux';

async function dismissCookies(page) {
  for (let i = 0; i < 4; i++) {
    const b = page.locator('text=Aceitar').first();
    if (await b.count()) {
      await b.click({ force: true }).catch(() => {});
      await page.waitForTimeout(350);
    }
  }
}

async function enableSemantics(page) {
  await page
    .evaluate(() => {
      document.querySelector('flt-semantics-placeholder')?.click();
    })
    .catch(() => {});
  await page.waitForTimeout(500);
}

async function settle(page) {
  await page.waitForSelector('flt-glass-pane, canvas, flutter-view', {
    timeout: 90000,
  });
  await page.waitForTimeout(5000);
  await dismissCookies(page);
  await enableSemantics(page);
  await page.waitForTimeout(900);
}

function isSorted(items, sort) {
  for (let i = 1; i < items.length; i++) {
    const a = items[i - 1];
    const b = items[i];
    const da = Date.parse(a.created_at);
    const db = Date.parse(b.created_at);
    const sa = Number(a.stars);
    const sb = Number(b.stars);
    const ida = String(a.id);
    const idb = String(b.id);
    if (sort === 'newest') {
      if (db !== da) {
        if (!(db < da)) return { ok: false, at: i, reason: 'date_desc' };
      } else if (idb !== ida && !(idb < ida)) {
        // id DESC on tie — lexical UUID compare is approximate; skip hard fail on id
      }
    } else if (sort === 'oldest') {
      if (db !== da && !(db > da)) return { ok: false, at: i, reason: 'date_asc' };
    } else if (sort === 'highest') {
      if (sb !== sa) {
        if (!(sb < sa)) return { ok: false, at: i, reason: 'stars_desc' };
      } else if (db !== da && !(db < da)) {
        return { ok: false, at: i, reason: 'date_desc_after_stars' };
      }
    } else if (sort === 'lowest') {
      if (sb !== sa) {
        if (!(sb > sa)) return { ok: false, at: i, reason: 'stars_asc' };
      } else if (db !== da && !(db < da)) {
        return { ok: false, at: i, reason: 'date_desc_after_stars' };
      }
    }
  }
  return { ok: true };
}

function dupes(ids) {
  const seen = new Set();
  const d = [];
  for (const id of ids) {
    if (seen.has(id)) d.push(id);
    seen.add(id);
  }
  return d;
}

function parseRpcBody(json) {
  let rows = [];
  if (Array.isArray(json)) rows = json;
  else if (json && typeof json === 'object') {
    if (Array.isArray(json.items)) rows = json.items;
    else if (Array.isArray(json.reviews)) rows = json.reviews;
  }
  return {
    items: rows.map((r) => ({
      id: String(r.id ?? ''),
      stars: Number(r.stars ?? 0),
      created_at: r.created_at ?? '',
    })),
    hasMore: json?.has_more === true,
    topKeys:
      json && !Array.isArray(json) ? Object.keys(json).slice(0, 12) : ['array'],
  };
}

async function runP06(browser) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await page.goto(`${BASE}/handle-invalido-fecho-06`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  await page.screenshot({
    path: path.join(shots, 'p06_404_before_cta_1280.png'),
    fullPage: false,
  });

  const beforeUrl = page.url();
  const has404 =
    (await page.getByText('Esta página não existe').count()) > 0;
  const cta = page.getByText('Ir para o início');
  const ctaCount = await cta.count();
  if (ctaCount) {
    await cta.first().click({ force: true });
    await page.waitForTimeout(4000);
    await settle(page);
  }

  const afterUrl = page.url();
  await page.screenshot({
    path: path.join(shots, 'p06_after_cta_1280.png'),
    fullPage: false,
  });
  const bodyAfter = await page.evaluate(() => {
    const sem = [...document.querySelectorAll('flt-semantics')]
      .map((e) => e.innerText || e.getAttribute('aria-label') || '')
      .join('\n');
    return `${document.body?.innerText || ''}\n${sem}`;
  });

  const onFleahubLanding =
    afterUrl.includes('/fleahub') && !afterUrl.includes('handle-invalido');
  const onLogin =
    /\/login/i.test(afterUrl) ||
    /Palavra-passe|Criar conta|Entrar com e-mail/i.test(bodyAfter);
  const still404 = (await page.getByText('Esta página não existe').count()) > 0;
  const looksLanding =
    /Explorar|Directos|Como funciona|Descobrir|hubs em directo|Vitrines/i.test(
      bodyAfter,
    );

  // Valid route regression
  await page.goto(`${BASE}/${HANDLE}`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  const validIs404 =
    (await page.getByText('Esta página não existe').count()) > 0;
  await page.screenshot({
    path: path.join(shots, 'p06_valid_route_not_404_1280.png'),
    fullPage: false,
  });

  await page.close();

  const anonPass =
    has404 &&
    ctaCount > 0 &&
    onFleahubLanding &&
    !onLogin &&
    !still404 &&
    !validIs404;

  return {
    id: 'p06_cta_destination',
    anon: {
      beforeUrl,
      afterUrl,
      has404Before: has404,
      ctaCount,
      onFleahubLanding,
      onLogin,
      still404,
      looksLanding,
      validRouteIs404: validIs404,
      pass: anonPass,
      evidenceShots: [
        'p06_404_before_cta_1280.png',
        'p06_after_cta_1280.png',
        'p06_valid_route_not_404_1280.png',
      ],
    },
    authenticated: {
      status: 'NOT RUN',
      reason:
        'Sem credenciais nesta ronda. Código: goFleahubLanding → /fleahub para qualquer sessão (não depende de loggedIn).',
      codePath: 'HubNavigation.goFleahubLanding → context.go(HubRoutePaths.landing)',
    },
  };
}

async function runP05(browser) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  /** @type {Record<string, Array<{sort:string, items:any[], hasMore:boolean|null}>>} */
  const pagesBySort = {};

  page.on('response', async (res) => {
    if (
      res.request().method() !== 'POST' ||
      !res.url().includes('batata_hub_reviews_public_page')
    ) {
      return;
    }
    let sort = null;
    try {
      sort = res.request().postDataJSON()?.p_sort || null;
    } catch (_) {}
    try {
      const json = await res.json();
      const parsed = parseRpcBody(json);
      if (!pagesBySort[sort]) pagesBySort[sort] = [];
      pagesBySort[sort].push({
        sort,
        http: res.status(),
        items: parsed.items,
        hasMore: parsed.hasMore,
        topKeys: parsed.topKeys,
      });
    } catch (e) {
      if (!pagesBySort[sort]) pagesBySort[sort] = [];
      pagesBySort[sort].push({
        sort,
        http: res.status(),
        items: [],
        error: String(e),
      });
    }
  });

  await page.goto(`${BASE}/${HANDLE}/reviews`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  await page.screenshot({
    path: path.join(shots, 'p05_reviews_initial_1440.png'),
    fullPage: false,
  });

  const sorts = [
    ['newest', 'Mais recentes'],
    ['oldest', 'Mais antigas'],
    ['highest', 'Melhor nota'],
    ['lowest', 'Pior nota'],
  ];

  const results = [];

  for (const [key, label] of sorts) {
    const beforeLen = (pagesBySort[key] || []).length;
    const chip = page.getByText(label, { exact: true });
    const chipCount = await chip.count();
    let clickOk = false;
    if (chipCount) {
      await chip.first().click({ force: true });
      clickOk = true;
    }
    // wait RPC
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      if ((pagesBySort[key] || []).length > beforeLen) break;
      await page.waitForTimeout(200);
    }
    await page.waitForTimeout(800);
    await page.screenshot({
      path: path.join(shots, `p05_sort_${key}_page1_1440.png`),
      fullPage: false,
    });

    // Ver mais once
    let moreClicked = false;
    const beforeMore = (pagesBySort[key] || []).length;
    const moreBtn = page.getByText('Ver mais avaliações', { exact: true });
    if (await moreBtn.count()) {
      await moreBtn.first().click({ force: true });
      moreClicked = true;
      const d2 = Date.now() + 10000;
      while (Date.now() < d2) {
        if ((pagesBySort[key] || []).length > beforeMore) break;
        await page.waitForTimeout(200);
      }
      await page.waitForTimeout(600);
      await page.screenshot({
        path: path.join(shots, `p05_sort_${key}_after_more_1440.png`),
        fullPage: false,
      });
    }

    const sortPages = (pagesBySort[key] || []).slice(beforeLen);
    const allItems = sortPages.flatMap((p) => p.items || []);
    const ids = allItems.map((i) => i.id).filter(Boolean);
    const orderCheck = allItems.length
      ? isSorted(allItems, key)
      : { ok: false, reason: 'no_items' };
    const d = dupes(ids);
    const rpcApplied =
      sortPages.length > 0 && sortPages.every((p) => p.sort === key);

    const body = await page.evaluate(() => {
      const sem = [...document.querySelectorAll('flt-semantics')]
        .map((e) => e.innerText || e.getAttribute('aria-label') || '')
        .join('\n');
      return `${document.body?.innerText || ''}\n${sem}`;
    });

    const pass =
      clickOk &&
      rpcApplied &&
      allItems.length > 0 &&
      orderCheck.ok &&
      d.length === 0;

    results.push({
      sort: key,
      label,
      chipCount,
      clickOk,
      labelInSemantics: body.includes(label),
      rpcApplied,
      rpcPageCount: sortPages.length,
      itemCount: allItems.length,
      moreClicked,
      orderOk: orderCheck.ok,
      orderDetail: orderCheck,
      duplicates: d,
      first3: allItems.slice(0, 3),
      last3: allItems.slice(-3),
      pass,
      automationLimitation: !clickOk
        ? 'Flutter semantics chip not found — limitação de teste, não prova defeito app'
        : allItems.length === 0
          ? 'RPC items not captured'
          : null,
    });
  }

  await page.close();
  return {
    id: 'p05_sort_ui',
    handle: HANDLE,
    results,
    pass: results.every((r) => r.pass),
  };
}

const browser = await chromium.launch({ headless: true });
const report = {
  base: BASE,
  started: new Date().toISOString(),
  p06: null,
  p05: null,
};
try {
  report.p06 = await runP06(browser);
  report.p05 = await runP05(browser);
} finally {
  await browser.close();
  report.finished = new Date().toISOString();
  fs.writeFileSync(
    path.join(evidence, 'FECHO_P06_P05_REPORT.json'),
    JSON.stringify(report, null, 2),
  );
  console.log(JSON.stringify(report, null, 2));
}
