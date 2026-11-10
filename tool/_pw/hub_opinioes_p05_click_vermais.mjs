import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const root = path.join(repo, '05-opinioes-validacao-final/SCREENSHOTS');

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto(`${base}/fleahub-demo-ux/reviews`, {
  waitUntil: 'networkidle',
  timeout: 120000,
});
await page.waitForTimeout(6500);

// Dismiss cookies first so it doesn't steal clicks
for (let i = 0; i < 3; i++) {
  const b = page.locator('text=Aceitar').first();
  if (await b.count()) {
    await b.click({ force: true }).catch(() => {});
    await page.waitForTimeout(500);
  }
}
await page.waitForTimeout(800);
await page.screenshot({ path: path.join(root, 'nocookie_top_1440.png') });

// Focus list + drag to bottom
await page.mouse.click(980, 420);
for (let k = 0; k < 3; k++) {
  await page.mouse.move(980, 720);
  await page.mouse.down();
  await page.mouse.move(980, 140, { steps: 30 });
  await page.mouse.up();
  await page.waitForTimeout(400);
}
await page.screenshot({
  path: path.join(root, 'ready_vermais_nocookie_1440.png'),
});

// Click Ver mais (above where cookie was)
await page.mouse.click(900, 780);
await page.waitForTimeout(4000);
await page.screenshot({
  path: path.join(root, 'loaded_page2_1440.png'),
  fullPage: true,
});

// Scroll a bit to show appended items
await page.mouse.move(980, 720);
await page.mouse.down();
await page.mouse.move(980, 200, { steps: 20 });
await page.mouse.up();
await page.waitForTimeout(600);
await page.screenshot({
  path: path.join(root, 'loaded_page2_scrolled_1440.png'),
});

// Back to top for Ler mais
for (let k = 0; k < 4; k++) {
  await page.mouse.move(980, 180);
  await page.mouse.down();
  await page.mouse.move(980, 780, { steps: 25 });
  await page.mouse.up();
  await page.waitForTimeout(300);
}
await page.screenshot({ path: path.join(root, 'back_top_1440.png') });
// Click Ler mais approx under first review body
await page.mouse.click(620, 360);
await page.waitForTimeout(1200);
await page.screenshot({
  path: path.join(root, 'ler_mais_expanded_1440.png'),
});

// Filter 5★ — chip roughly after Todas
await page.mouse.click(455, 148);
await page.waitForTimeout(3000);
await page.screenshot({
  path: path.join(root, 'filter5_active_1440.png'),
  fullPage: true,
});

await browser.close();
console.log('done');
