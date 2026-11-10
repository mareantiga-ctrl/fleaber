import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const base = process.argv[2] ?? 'http://localhost:8794';
const url = `${base}/vendedora-prod/shop`;
const outRoot = path.resolve(
  '../../04-marketplace-recapture/SCREENSHOTS/AFTER_DESKTOP_GRID',
);

const viewports = [
  { name: '390', width: 390, height: 844 },
  { name: '1440', width: 1440, height: 900 },
  { name: '1920', width: 1920, height: 1080 },
];

async function waitShop(page) {
  await page.waitForFunction(
    () => {
      const t = document.title || '';
      const text = document.body?.innerText || '';
      return (
        t.includes('Marketplace') ||
        text.includes('@vendedora-prod · Marketplace') ||
        text.includes('TESTE')
      );
    },
    { timeout: 90000 },
  );
  await page.waitForTimeout(2000);
  const accept = page.getByRole('button', { name: 'Aceitar' });
  if (await accept.count()) {
    try {
      await accept.first().click({ timeout: 1500 });
    } catch (_) {}
  }
}

async function measureCols(page) {
  return page.evaluate(() => {
    const cards = [...document.querySelectorAll('[role=button],button')]
      .map((b) => {
        const n = b.getAttribute('aria-label') || b.innerText || '';
        const r = b.getBoundingClientRect();
        return {
          n,
          w: Math.round(r.width),
          h: Math.round(r.height),
          x: Math.round(r.x),
          y: Math.round(r.y),
        };
      })
      .filter((b) => b.n.includes('€') && b.h > 80);
    if (!cards.length) return { cols: 0, cards: 0 };
    const rowY = Math.min(...cards.map((c) => c.y));
    const row = cards.filter((c) => Math.abs(c.y - rowY) < 40);
    row.sort((a, b) => a.x - b.x);
    return {
      cols: row.length,
      cards: cards.length,
      cardW: row[0]?.w,
      cardH: row[0]?.h,
      firstX: row[0]?.x,
      lastX: row[row.length - 1] ? row[row.length - 1].x + row[row.length - 1].w : null,
      vw: innerWidth,
    };
  });
}

const browser = await chromium.launch({ headless: true });
const report = {};
fs.mkdirSync(outRoot, { recursive: true });

for (const vp of viewports) {
  const dir = path.join(outRoot, vp.name);
  fs.mkdirSync(dir, { recursive: true });
  const context = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  console.log(`[${vp.name}] ${url}`);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await waitShop(page);
  const m = await measureCols(page);
  report[vp.name] = m;
  await page.screenshot({
    path: path.join(dir, '01_first.png'),
    fullPage: false,
  });
  console.log(`[${vp.name}]`, m);
  await context.close();
}

fs.writeFileSync(
  path.join(outRoot, 'MEASUREMENTS.json'),
  JSON.stringify(report, null, 2),
);
console.log('DONE', outRoot);
await browser.close();
