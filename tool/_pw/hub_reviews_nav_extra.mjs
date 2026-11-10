import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
const base = 'http://127.0.0.1:8799';
const out = path.resolve('../../05-opinioes-recapture/SCREENSHOTS/NAV');
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ headless: true });
const page = await (await browser.newContext({ viewport: { width: 1440, height: 900 } })).newPage();
await page.goto(base + '/vendedora-prod', { waitUntil: 'domcontentloaded' });
for (let i = 0; i < 40; i++) {
  await page.waitForTimeout(1000);
  if ((await page.title()).includes('Vendedora')) break;
}
for (let i = 0; i < 25; i++) {
  await page.mouse.wheel(0, 500);
  await page.waitForTimeout(250);
}
await page.screenshot({ path: path.join(out, 'profile_opinioes_scrolled.png') });
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(1000);
await page.mouse.wheel(0, -8000);
await page.waitForTimeout(400);
for (let i = 0; i < 20; i++) {
  await page.mouse.wheel(0, 500);
  await page.waitForTimeout(200);
}
await page.screenshot({ path: path.join(out, 'profile_opinioes_390.png') });
await browser.close();
console.log('DONE');
