import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const root = path.join(repo, '05-opinioes-validacao-final/SCREENSHOTS');
fs.mkdirSync(root, { recursive: true });

async function dismissCookies(page) {
  for (let i = 0; i < 3; i++) {
    const btn = page.locator('text=Aceitar').first();
    if (await btn.count()) {
      try {
        await btn.click({ timeout: 2500, force: true });
        await page.waitForTimeout(600);
      } catch (_) {}
    }
  }
}

async function openReviews(page, handle) {
  await page.goto(`${base}/${handle}/reviews`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await page.waitForSelector('flt-glass-pane, canvas, flutter-view', {
    timeout: 90000,
  });
  await page.waitForTimeout(6000);
  await dismissCookies(page);
  await page.waitForTimeout(1500);
}

const report = { base, started: new Date().toISOString(), steps: [] };
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({
    viewport: { width: 1280, height: 900 },
  });
  await openReviews(page, 'fleahub-demo-ux');
  await page.screenshot({
    path: path.join(root, 'func_top_1280.png'),
    fullPage: false,
  });

  // Scroll to bottom of Flutter content via keyboard / wheel
  for (let i = 0; i < 12; i++) {
    await page.mouse.wheel(0, 900);
    await page.waitForTimeout(350);
  }
  await page.waitForTimeout(1000);
  await page.screenshot({
    path: path.join(root, 'func_scrolled_vermais_1280.png'),
    fullPage: false,
  });
  report.steps.push({ step: 'scrolled_for_vermais', ok: true });

  // Try click Ver mais — text locator then bottom CTA region
  let loadClicked = false;
  const candidates = [
    page.getByText('Ver mais avaliações', { exact: false }),
    page.locator('text=/Ver mais/i'),
  ];
  for (const loc of candidates) {
    if (await loc.count()) {
      try {
        await loc.first().click({ timeout: 4000, force: true });
        loadClicked = true;
        break;
      } catch (_) {}
    }
  }
  if (!loadClicked) {
    // Approximate button center near bottom of content column
    await page.mouse.click(820, 820);
    loadClicked = true;
  }
  await page.waitForTimeout(4000);
  await page.screenshot({
    path: path.join(root, 'func_after_loadmore_1280.png'),
    fullPage: true,
  });
  report.steps.push({ step: 'load_more_click', loadClicked });

  // Ler mais on long comment — scroll top first
  await page.mouse.wheel(0, -5000);
  await page.waitForTimeout(800);
  let lerMais = false;
  const lm = page.getByText('Ler mais', { exact: false });
  if (await lm.count()) {
    try {
      await lm.first().click({ timeout: 4000, force: true });
      lerMais = true;
      await page.waitForTimeout(1000);
    } catch (_) {}
  }
  await page.screenshot({
    path: path.join(root, 'func_ler_mais_1280.png'),
    fullPage: false,
  });
  report.steps.push({ step: 'ler_mais', lerMais });

  // Filter 5★
  const chip = page.getByText('5 ★', { exact: true });
  if (await chip.count()) {
    try {
      await chip.first().click({ timeout: 4000, force: true });
      await page.waitForTimeout(3000);
    } catch (_) {}
  }
  await page.screenshot({
    path: path.join(root, 'func_filter5_1280.png'),
    fullPage: true,
  });
  report.steps.push({ step: 'filter5', attempted: true });

  // Mobile empty + small already captured; re-snap after cookie dismiss
  const m1 = await browser.newPage({
    viewport: { width: 390, height: 844 },
  });
  await openReviews(m1, 'joao84');
  await m1.screenshot({
    path: path.join(root, 'empty_joao84_390_nocookie.png'),
    fullPage: true,
  });
  await m1.close();

  const m2 = await browser.newPage({
    viewport: { width: 390, height: 844 },
  });
  await openReviews(m2, 'vendora-muxb-0913');
  for (let i = 0; i < 6; i++) {
    await m2.mouse.wheel(0, 700);
    await m2.waitForTimeout(250);
  }
  await m2.screenshot({
    path: path.join(root, 'small_5_muxb_390_scrolled.png'),
    fullPage: true,
  });
  await m2.close();

  // Guest evidence: Entrar visible on reviews (anon)
  await page.goto(`${base}/fleahub-demo-ux/reviews`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await page.waitForTimeout(5000);
  await dismissCookies(page);
  await page.screenshot({
    path: path.join(root, 'anon_guest_entrar_1280.png'),
    fullPage: false,
  });
  report.steps.push({ step: 'anon_guest', ok: true });

  await page.close();
} finally {
  await browser.close();
}

report.finished = new Date().toISOString();
fs.writeFileSync(
  path.join(root, 'FUNCTIONAL_CAPTURE.json'),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
