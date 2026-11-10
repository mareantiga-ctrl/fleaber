import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const root = path.join(repo, '05-opinioes-validacao-final/SCREENSHOTS');
fs.mkdirSync(root, { recursive: true });

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto(`${base}/fleahub-demo-ux/reviews`, {
  waitUntil: 'networkidle',
  timeout: 120000,
});
await page.waitForTimeout(6000);
const aceitar = page.locator('text=Aceitar').first();
if (await aceitar.count()) {
  await aceitar.click({ force: true }).catch(() => {});
  await page.waitForTimeout(800);
}

// Focus Flutter glass pane, then Tab into list and PageDown
await page.locator('flt-glass-pane, flutter-view, canvas').first().click({
  position: { x: 900, y: 400 },
  force: true,
});
await page.waitForTimeout(400);

for (let i = 0; i < 20; i++) {
  await page.keyboard.press('PageDown');
  await page.waitForTimeout(200);
}
await page.waitForTimeout(800);
await page.screenshot({
  path: path.join(root, 'scroll_pagedown_vermais_1440.png'),
  fullPage: false,
});

// Try ArrowDown spam
for (let i = 0; i < 40; i++) {
  await page.keyboard.press('ArrowDown');
  await page.waitForTimeout(80);
}
await page.screenshot({
  path: path.join(root, 'scroll_arrow_vermais_1440.png'),
  fullPage: false,
});

// Drag scroll gesture on right column
await page.mouse.move(980, 700);
await page.mouse.down();
await page.mouse.move(980, 120, { steps: 25 });
await page.mouse.up();
await page.waitForTimeout(600);
await page.mouse.move(980, 700);
await page.mouse.down();
await page.mouse.move(980, 120, { steps: 25 });
await page.mouse.up();
await page.waitForTimeout(800);
await page.screenshot({
  path: path.join(root, 'scroll_drag_vermais_1440.png'),
  fullPage: false,
});

// Click likely Ver mais zone + screenshot
await page.mouse.click(980, 820);
await page.waitForTimeout(3500);
await page.screenshot({
  path: path.join(root, 'after_vermais_click_1440.png'),
  fullPage: true,
});

// Ler mais near top — scroll up
await page.mouse.move(980, 200);
await page.mouse.down();
await page.mouse.move(980, 800, { steps: 20 });
await page.mouse.up();
await page.waitForTimeout(500);
await page.mouse.click(700, 380);
await page.waitForTimeout(1000);
await page.screenshot({
  path: path.join(root, 'after_ler_mais_click_1440.png'),
  fullPage: false,
});

// Filter: click around 5★ chip area (after Todas)
await page.mouse.click(520, 150);
await page.waitForTimeout(2500);
await page.screenshot({
  path: path.join(root, 'after_filter_chip_1440.png'),
  fullPage: false,
});

await browser.close();
console.log('scroll/loadmore shots written');
