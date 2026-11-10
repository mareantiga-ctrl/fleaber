import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
const base = 'http://127.0.0.1:8798';
const out = path.resolve('../../04-marketplace-final-validation');
const shots = path.join(out, 'SCREENSHOTS', 'FUNCTIONAL');
const browser = await chromium.launch({ headless: true });
const page = await (await browser.newContext({ viewport: { width: 1440, height: 900 } })).newPage();
await page.goto(`${base}/vendedora-prod`, { waitUntil: 'domcontentloaded' });
for (let i = 0; i < 40; i++) {
  await page.waitForTimeout(1000);
  const t = await page.title();
  if (t.includes('Vendedora') && !t.includes('encontrada')) break;
}
await page.waitForTimeout(2500);
// dismiss cookies
await page.mouse.click(900, 820);
await page.waitForTimeout(500);
await page.screenshot({ path: path.join(shots, 'before_ver_loja.png') });
// Ver loja is on Marketplace row right — from P02 shot roughly y~520, x~1280
const candidates = [
  [1280, 520], [1250, 500], [1300, 540], [1200, 480], [1280, 560],
  [1100, 520], [1280, 600], [1000, 700],
];
let hit = null;
for (const [x, y] of candidates) {
  await page.mouse.click(x, y);
  await page.waitForTimeout(1500);
  if (page.url().includes('/shop')) { hit = { x, y, url: page.url() }; break; }
  // if navigated away from profile, go back
  if (!page.url().endsWith('/vendedora-prod') && !page.url().match(/\/vendedora-prod$/)) {
    await page.goto(`${base}/vendedora-prod`, { waitUntil: 'domcontentloaded' });
    for (let i = 0; i < 25; i++) {
      await page.waitForTimeout(800);
      if ((await page.title()).includes('Vendedora')) break;
    }
    await page.waitForTimeout(1500);
  }
}
const report = { hit, url: page.url(), title: await page.title() };
await page.screenshot({ path: path.join(shots, 'after_ver_loja_click.png') });
const prev = JSON.parse(fs.readFileSync(path.join(out, 'RAW_REPORT.json'), 'utf8'));
if (hit) {
  prev.functional.verLoja = { executed: true, url: hit.url, onShop: true, method: `click@${hit.x},${hit.y}` };
}
fs.writeFileSync(path.join(out, 'RAW_REPORT.json'), JSON.stringify(prev, null, 2));
console.log(JSON.stringify(report, null, 2));
await browser.close();
