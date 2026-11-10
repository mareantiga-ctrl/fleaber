import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const base = process.argv[2] ?? 'http://localhost:8793';
const url = `${base}/vendedora-prod/shop`;
const root = path.resolve('04-marketplace-recapture/SCREENSHOTS');

const viewports = [
  { name: '390', width: 390, height: 844, mobile: true },
  { name: '768', width: 768, height: 1024, mobile: true },
  { name: '1024', width: 1024, height: 768, mobile: false },
  { name: '1280', width: 1280, height: 800, mobile: false },
  { name: '1440', width: 1440, height: 900, mobile: false },
  { name: '1920', width: 1920, height: 1080, mobile: false },
];

async function waitShop(page) {
  await page.waitForFunction(
    () =>
      (document.body?.innerText || '').includes('@vendedora-prod · Marketplace') ||
      (document.body?.innerText || '').includes('TESTE'),
    { timeout: 60000 },
  );
  await page.waitForTimeout(1500);
  const accept = page.getByRole('button', { name: 'Aceitar' });
  if (await accept.count()) {
    try {
      await accept.first().click({ timeout: 2000 });
    } catch (_) {}
  }
}

async function scrollSemantics(page, y) {
  await page.evaluate((target) => {
    const el = [...document.querySelectorAll('flt-semantics')].find(
      (e) => e.scrollHeight > e.clientHeight + 20,
    );
    if (el) el.scrollTop = target;
  }, y);
  await page.waitForTimeout(600);
}

async function measure(page) {
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
      .filter((b) => b.n.includes('€') && b.h > 40);
    const first = cards[0];
    const second = cards[1];
    return {
      vw: innerWidth,
      vh: innerHeight,
      nVisible: cards.length,
      cardW: first?.w ?? null,
      cardH: first?.h ?? null,
      gap:
        first && second
          ? Math.round(second.x - (first.x + first.w))
          : null,
      contentLeft: first?.x ?? null,
      contentRight: second
        ? second.x + second.w
        : first
          ? first.x + first.w
          : null,
      title: document.title,
    };
  });
}

const browser = await chromium.launch({ headless: true });
const measures = {};

for (const vp of viewports) {
  const dir = path.join(root, vp.name);
  fs.mkdirSync(dir, { recursive: true });
  const context = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    isMobile: vp.mobile,
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  console.log(`[${vp.name}] ${url}`);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await waitShop(page);
  measures[vp.name] = await measure(page);
  await page.screenshot({
    path: path.join(dir, '01_first.png'),
    fullPage: false,
  });
  // mid + bottom via semantics scroll
  await scrollSemantics(page, 1200);
  await page.screenshot({
    path: path.join(dir, '02_mid.png'),
    fullPage: false,
  });
  await scrollSemantics(page, 99999);
  await page.screenshot({
    path: path.join(dir, '03_full.png'),
    fullPage: false,
  });
  console.log(`[${vp.name}] OK`, measures[vp.name]);
  await context.close();
}

fs.writeFileSync(
  path.join(root, 'MEASUREMENTS.json'),
  JSON.stringify(measures, null, 2),
);
console.log('DONE', path.resolve(root));
await browser.close();
