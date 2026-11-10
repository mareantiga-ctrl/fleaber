import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const root = path.join(repo, '05-opinioes-correcao-tecnica-final/SCREENSHOTS');
fs.mkdirSync(root, { recursive: true });

// Read staging env without logging secrets
const envPath = path.join(repo, 'tool/live_ops_staging.env');
const envText = fs.readFileSync(envPath, 'utf8');
const env = Object.fromEntries(
  envText
    .split(/\r?\n/)
    .filter((l) => l && !l.startsWith('#') && l.includes('='))
    .map((l) => {
      const i = l.indexOf('=');
      return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    }),
);

const buyerEmail = env.LIVE_OPS_TEST_BUYER_EMAIL;
const buyerPass = env.LIVE_OPS_TEST_BUYER_PASSWORD;
const sellerEmail = env.LIVE_OPS_TEST_SELLER_EMAIL;
const sellerPass = env.LIVE_OPS_TEST_SELLER_PASSWORD;

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
  await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (ph) ph.click();
    // Flutter web a11y button
    const btn = document.querySelector('[aria-label*="Enable accessibility"], [aria-label*="ativ"]');
    if (btn) btn.click();
  }).catch(() => {});
  await page.waitForTimeout(500);
}

async function autologin(page, email, password, next) {
  const url =
    `${base}/maestroAutologin?email=${encodeURIComponent(email)}` +
    `&password=${encodeURIComponent(password)}` +
    `&next=${encodeURIComponent(next)}`;
  await page.goto(url, { waitUntil: 'networkidle', timeout: 120000 });
  await page.waitForTimeout(8000);
  await dismissCookies(page);
}

const report = { started: new Date().toISOString(), steps: [] };
const browser = await chromium.launch({ headless: true });

try {
  // Buyer authenticated → reviews page
  {
    const page = await browser.newPage({
      viewport: { width: 1280, height: 800 },
    });
    await autologin(
      page,
      buyerEmail,
      buyerPass,
      '/fleahub-demo-ux/reviews',
    );
    await page.waitForTimeout(4000);
    await enableSemantics(page);
    await page.screenshot({
      path: path.join(root, 'auth_buyer_reviews_1280.png'),
      fullPage: true,
    });
    const hasEntrar = await page.locator('text=Entrar').count();
    report.steps.push({
      id: 'auth_buyer',
      status: hasEntrar ? 'FAIL_STILL_GUEST' : 'PASS',
      url: page.url(),
    });
    await page.close();
  }

  // Seller authenticated → own empty-ish? muxc has 10k — use demo as guest view as seller of muxc reviews
  {
    const page = await browser.newPage({
      viewport: { width: 1280, height: 800 },
    });
    await autologin(
      page,
      sellerEmail,
      sellerPass,
      '/vendora-muxc-0921/reviews',
    );
    await page.waitForTimeout(5000);
    await dismissCookies(page);
    await page.screenshot({
      path: path.join(root, 'auth_seller_muxc_reviews_1280.png'),
      fullPage: false,
    });
    const hasEntrar = await page.locator('text=Entrar').count();
    report.steps.push({
      id: 'auth_seller',
      status: hasEntrar ? 'FAIL_STILL_GUEST' : 'PASS',
      url: page.url(),
      note: 'Seller session on own Hub reviews (10k seeded)',
    });
    await page.close();
  }

  // Semantics-assisted Ler mais
  {
    const page = await browser.newPage({
      viewport: { width: 1440, height: 900 },
    });
    await page.goto(`${base}/fleahub-demo-ux/reviews`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await page.waitForTimeout(6000);
    await dismissCookies(page);
    await enableSemantics(page);
    await page.waitForTimeout(1000);
    const ler = page.getByText('Ler mais', { exact: false });
    let expanded = false;
    if (await ler.count()) {
      await ler.first().click({ force: true }).catch(() => {});
      await page.waitForTimeout(1200);
      expanded = (await page.getByText('Mostrar menos', { exact: false }).count()) > 0;
      await page.screenshot({
        path: path.join(root, 'ler_mais_semantics_1440.png'),
      });
      if (expanded) {
        await page.getByText('Mostrar menos', { exact: false }).first().click({ force: true }).catch(() => {});
        await page.waitForTimeout(800);
        await page.screenshot({
          path: path.join(root, 'mostrar_menos_semantics_1440.png'),
        });
      }
    }
    // Filter via semantics
    const chip5 = page.getByText('5 ★', { exact: true });
    let filterOk = false;
    if (await chip5.count()) {
      await chip5.first().click({ force: true }).catch(() => {});
      await page.waitForTimeout(2800);
      await page.screenshot({
        path: path.join(root, 'filter5_semantics_1440.png'),
        fullPage: true,
      });
      // Heuristic: Todas not selected hard to detect; check if 4★ review gone from first items
      filterOk = true;
    }
    report.steps.push({
      id: 'ler_mais_semantics',
      expanded,
      filterAttempted: filterOk,
    });
    await page.close();
  }
} finally {
  await browser.close();
}

report.finished = new Date().toISOString();
fs.writeFileSync(
  path.join(root, 'UI_AUTH_REPORT.json'),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
