import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
const out = path.resolve('../../05-opinioes-recapture/SCREENSHOTS/NAV');
const browser = await chromium.launch({ headless: true });
const page = await (await browser.newContext({ viewport: { width: 1440, height: 900 } })).newPage();
await page.goto('http://127.0.0.1:8799/vendedora-prod', { waitUntil: 'domcontentloaded' });
for (let i = 0; i < 40; i++) {
  await page.waitForTimeout(1000);
  if ((await page.title()).includes('Vendedora')) break;
}
// dismiss cookies
await page.mouse.click(900, 850);
await page.waitForTimeout(500);
// heavy scroll - marketplace has many tall cards
for (let i = 0; i < 60; i++) {
  await page.mouse.wheel(0, 800);
  await page.waitForTimeout(150);
}
await page.screenshot({ path: path.join(out, 'profile_opinioes_deep.png') });
await browser.close();
console.log('DONE');
