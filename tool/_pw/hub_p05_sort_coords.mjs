import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const base = 'http://127.0.0.1:8799';
const shots = path.join(
  repo,
  '06-not-found-implementacao-e-auditoria/SCREENSHOTS',
);

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto(`${base}/fleahub-demo-ux/reviews`, {
  waitUntil: 'networkidle',
  timeout: 120000,
});
await page.waitForTimeout(6000);
const aceitar = page.locator('text=Aceitar').first();
if (await aceitar.count()) await aceitar.click({ force: true }).catch(() => {});
await page.waitForTimeout(500);

// Dropdown is under filter chips — approx (430, 198) for "Mais recentes"
async function pick(indexFromTop /* 0=Mais recentes … */) {
  await page.mouse.click(430, 198);
  await page.waitForTimeout(800);
  // Overlay items roughly 36px apart below the button
  const y = 240 + indexFromTop * 40;
  await page.mouse.click(430, y);
  await page.waitForTimeout(3000);
}

const report = [];
// Menu order in code: newest, oldest, highest, lowest
await pick(1); // oldest
await page.screenshot({
  path: path.join(shots, 'p05_sort_oldest_coords_1440.png'),
});
report.push({ pick: 'oldest_index1' });

await pick(2); // highest
await page.screenshot({
  path: path.join(shots, 'p05_sort_highest_coords_1440.png'),
});
report.push({ pick: 'highest_index2' });

await pick(3); // lowest
await page.screenshot({
  path: path.join(shots, 'p05_sort_lowest_coords_1440.png'),
});
report.push({ pick: 'lowest_index3' });

await pick(0); // newest
await page.screenshot({
  path: path.join(shots, 'p05_sort_newest_coords_1440.png'),
});
report.push({ pick: 'newest_index0' });

await browser.close();
fs.writeFileSync(
  path.join(repo, '06-not-found-implementacao-e-auditoria/P05_SORT_COORDS.json'),
  JSON.stringify(report, null, 2),
);
console.log('done');
