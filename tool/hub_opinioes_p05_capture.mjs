import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const root = path.resolve('05-opinioes-implementacao-final/SCREENSHOTS');
const afterDir = path.join(root, 'AFTER');
fs.mkdirSync(afterDir, { recursive: true });

const viewports = [
  { name: '390', width: 390, height: 844 },
  { name: '430', width: 430, height: 932 },
  { name: '768', width: 768, height: 1024 },
  { name: '1024', width: 1024, height: 768 },
  { name: '1280', width: 1280, height: 800 },
  { name: '1440', width: 1440, height: 900 },
  { name: '1920', width: 1920, height: 1080 },
];

async function dismissCookies(page) {
  const accept = page.getByRole('button', { name: /Aceitar/i });
  if (await accept.count()) {
    try {
      await accept.first().click({ timeout: 2000 });
    } catch (_) {}
  }
}

async function waitReviews(page) {
  await page.waitForFunction(
    () => {
      const t = document.body?.innerText || '';
      return (
        t.includes('Avaliações') ||
        t.includes('avaliações') ||
        t.includes('Ainda sem avaliações')
      );
    },
    { timeout: 90000 },
  );
  await page.waitForTimeout(2000);
  await dismissCookies(page);
  await page.waitForTimeout(800);
}

async function measure(page) {
  return page.evaluate(() => {
    const text = document.body?.innerText || '';
    return {
      vw: innerWidth,
      vh: innerHeight,
      scrollWidth: document.documentElement.scrollWidth,
      hasOverflowX: document.documentElement.scrollWidth > innerWidth + 2,
      title: document.title,
      hasAverage: /\d\.\d/.test(text),
      hasOpinioesLabel: text.includes('Opiniões') || text.includes('Avaliações'),
      hasEmpty: text.includes('Ainda sem avaliações'),
      hasQaMarker: text.includes('[QA-P05-20261004]'),
      snippet: text.replace(/\s+/g, ' ').slice(0, 280),
    };
  });
}

const report = { base, started: new Date().toISOString(), shots: [] };

const browser = await chromium.launch({ headless: true });
try {
  for (const vp of viewports) {
    const page = await browser.newPage({
      viewport: { width: vp.width, height: vp.height },
    });
    const url = `${base}/fleahub-demo-ux/reviews`;
    await page.goto(url, { waitUntil: 'networkidle', timeout: 120000 });
    await waitReviews(page);
    const m = await measure(page);
    const file = path.join(afterDir, `reviews_${vp.name}.png`);
    await page.screenshot({ path: file, fullPage: true });
    report.shots.push({ viewport: vp.name, file, ...m });
    console.log(`${vp.name} → overflowX=${m.hasOverflowX} marker=${m.hasQaMarker}`);
    await page.close();
  }

  // Empty-ish control: unknown handle → not found or empty
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(`${base}/fleahub-demo-ux`, { waitUntil: 'networkidle', timeout: 120000 });
  await page.waitForTimeout(2500);
  await dismissCookies(page);
  await page.screenshot({
    path: path.join(afterDir, 'seller_page_1280.png'),
    fullPage: true,
  });
  await page.close();
} finally {
  await browser.close();
}

report.finished = new Date().toISOString();
fs.writeFileSync(
  path.join(root, 'CAPTURE_REPORT.json'),
  JSON.stringify(report, null, 2),
);
console.log('Wrote', path.join(root, 'CAPTURE_REPORT.json'));
