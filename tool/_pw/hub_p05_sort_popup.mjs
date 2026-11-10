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
const base = 'http://127.0.0.1:8799';

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto(`${base}/fleahub-demo-ux/reviews`, {
  waitUntil: 'networkidle',
  timeout: 120000,
});
await page.waitForTimeout(6500);
const aceitar = page.locator('text=Aceitar').first();
if (await aceitar.count()) await aceitar.click({ force: true }).catch(() => {});
await page
  .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
  .catch(() => {});
await page.waitForTimeout(1000);

const steps = [];
for (const label of ['Mais antigas', 'Melhor nota', 'Pior nota', 'Mais recentes']) {
  const tip = page.locator('[aria-label="Ordenar avaliações"]');
  if (await tip.count()) {
    await tip.first().click({ force: true });
  } else {
    await page
      .getByText(/Mais (recentes|antigas)|Melhor nota|Pior nota/)
      .first()
      .click({ force: true })
      .catch(() => {});
  }
  await page.waitForTimeout(700);
  const item = page.getByText(label, { exact: true });
  const n = await item.count();
  if (n > 0) await item.nth(n - 1).click({ force: true });
  await page.waitForTimeout(3200);
  const key = label.includes('antigas')
    ? 'oldest'
    : label.includes('Melhor')
      ? 'highest'
      : label.includes('Pior')
        ? 'lowest'
        : 'newest';
  await page.screenshot({
    path: path.join(shots, `p05_sort_${key}_final_1440.png`),
    fullPage: false,
  });
  // Read first date-ish from semantics
  const snap = await page.evaluate(() => {
    const sem = [...document.querySelectorAll('flt-semantics')]
      .map((e) => e.innerText || e.getAttribute('aria-label') || '')
      .join('\n');
    return sem.slice(0, 800);
  });
  steps.push({
    label,
    itemCount: n,
    hasLabelInSem: snap.includes(label),
    hasMay: /mai/i.test(snap),
    hasOct: /out/i.test(snap),
    snippet: snap.replace(/\s+/g, ' ').slice(0, 200),
  });
  console.log(label, 'items', n, 'labelInSem', snap.includes(label));
}

await browser.close();
fs.writeFileSync(
  path.join(repo, '06-not-found-implementacao-e-auditoria/P05_SORT_FINAL.json'),
  JSON.stringify({ steps }, null, 2),
);
