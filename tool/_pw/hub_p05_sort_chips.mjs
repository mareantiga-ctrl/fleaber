import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const shots = path.join(
  repo,
  '06-not-found-implementacao-e-auditoria/SCREENSHOTS',
);

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto('http://127.0.0.1:8799/fleahub-demo-ux/reviews', {
  waitUntil: 'networkidle',
  timeout: 120000,
});
await page.waitForTimeout(6500);
const aceitar = page.locator('text=Aceitar').first();
if (await aceitar.count()) await aceitar.click({ force: true }).catch(() => {});
await page
  .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
  .catch(() => {});
await page.waitForTimeout(800);

const steps = [];
for (const [key, label] of [
  ['oldest', 'Mais antigas'],
  ['highest', 'Melhor nota'],
  ['lowest', 'Pior nota'],
  ['newest', 'Mais recentes'],
]) {
  const chip = page.getByText(label, { exact: true });
  const n = await chip.count();
  if (n) await chip.first().click({ force: true });
  await page.waitForTimeout(3200);
  await page.screenshot({
    path: path.join(shots, `p05_sort_${key}_chips_1440.png`),
    fullPage: false,
  });
  const body = await page.evaluate(() => {
    const sem = [...document.querySelectorAll('flt-semantics')]
      .map((e) => e.innerText || e.getAttribute('aria-label') || '')
      .join('\n');
    return `${document.body?.innerText || ''}\n${sem}`;
  });
  steps.push({
    key,
    label,
    chipCount: n,
    hasMay: /mai\.?\s*2026|5 mai/i.test(body),
    hasOct: /out\.?\s*2026/i.test(body),
    firstStarsHint: body.includes('1 ★') || /★/.test(body),
  });
  console.log(key, 'chips', n, 'may', steps.at(-1).hasMay, 'oct', steps.at(-1).hasOct);
}

await browser.close();
fs.writeFileSync(
  path.join(repo, '06-not-found-implementacao-e-auditoria/P05_SORT_CHIPS.json'),
  JSON.stringify({ steps }, null, 2),
);
