import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const shots = path.join(
  repo,
  '06-not-found-implementacao-e-auditoria/SCREENSHOTS',
);

async function prep(page) {
  await page.waitForSelector('flt-glass-pane, canvas, flutter-view', {
    timeout: 90000,
  });
  await page.waitForTimeout(5000);
  const aceitar = page.locator('text=Aceitar').first();
  if (await aceitar.count()) await aceitar.click({ force: true }).catch(() => {});
  await page
    .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
    .catch(() => {});
  await page.waitForTimeout(800);
}

async function selectSort(page, label) {
  // Click current sort label
  for (const t of ['Mais recentes', 'Mais antigas', 'Melhor nota', 'Pior nota']) {
    const cur = page.getByText(t, { exact: true });
    if (await cur.count()) {
      await cur.first().click({ force: true });
      await page.waitForTimeout(700);
      break;
    }
  }
  // Prefer menu item; last match is often the overlay item
  const items = page.getByRole('menuitem', { name: label });
  if (await items.count()) {
    await items.last().click({ force: true });
  } else {
    const opt = page.getByText(label, { exact: true });
    const n = await opt.count();
    if (n) await opt.nth(n - 1).click({ force: true });
  }
  await page.waitForTimeout(3200);
}

function textHas(page, re) {
  return page.evaluate((pattern) => {
    const t = document.body?.innerText || '';
    const sem = [...document.querySelectorAll('flt-semantics')]
      .map((e) => e.innerText || e.getAttribute('aria-label') || '')
      .join(' ');
    return new RegExp(pattern, 'i').test(`${t}\n${sem}`);
  }, re);
}

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const report = { steps: [] };

await page.goto(`${base}/fleahub-demo-ux/reviews`, {
  waitUntil: 'networkidle',
  timeout: 120000,
});
await prep(page);

await selectSort(page, 'Mais antigas');
await page.screenshot({
  path: path.join(shots, 'p05_sort_oldest_verified_1440.png'),
  fullPage: false,
});
const oldestOk =
  (await textHas(page, 'Mais antigas')) &&
  ((await textHas(page, 'mai\\.? 2026')) || (await textHas(page, '5 mai')));
report.steps.push({ sort: 'oldest', uiLabelOk: await textHas(page, 'Mais antigas'), oldestOk });

await selectSort(page, 'Melhor nota');
await page.screenshot({
  path: path.join(shots, 'p05_sort_highest_verified_1440.png'),
  fullPage: false,
});
report.steps.push({
  sort: 'highest',
  uiLabelOk: await textHas(page, 'Melhor nota'),
});

await selectSort(page, 'Pior nota');
await page.screenshot({
  path: path.join(shots, 'p05_sort_lowest_verified_1440.png'),
  fullPage: false,
});
report.steps.push({
  sort: 'lowest',
  uiLabelOk: await textHas(page, 'Pior nota'),
});

await selectSort(page, 'Mais recentes');
await page.screenshot({
  path: path.join(shots, 'p05_sort_newest_verified_1440.png'),
  fullPage: false,
});
report.steps.push({
  sort: 'newest',
  uiLabelOk: await textHas(page, 'Mais recentes'),
});

await browser.close();
fs.writeFileSync(
  path.join(
    repo,
    '06-not-found-implementacao-e-auditoria/P05_SORT_VERIFY.json',
  ),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
