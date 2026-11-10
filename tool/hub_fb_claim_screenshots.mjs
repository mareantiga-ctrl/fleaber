// Screenshots guest CTA Facebook claim — Hub Live
// node tool/hub_fb_claim_screenshots.mjs [baseUrl]
import fs from 'fs';
import path from 'path';
import puppeteer from 'puppeteer';

const base =
  process.argv[2] ??
  'http://localhost:8791/#/vendedora-prod/live?liveId=d4b2b649-aa7b-43c5-8717-b80c934c5a4a';
const root = path.resolve('03-live-facebook-claim-fix/SCREENSHOTS');

const viewports = [
  { name: '390', width: 390, height: 844 },
  { name: '1440', width: 1440, height: 900 },
  { name: '1920', width: 1920, height: 1080 },
];

const browser = await puppeteer.launch({
  headless: true,
  defaultViewport: null,
  args: ['--no-sandbox'],
});

for (const vp of viewports) {
  const dir = path.join(root, vp.name);
  fs.mkdirSync(dir, { recursive: true });
  const page = await browser.newPage();
  await page.setViewport({
    width: vp.width,
    height: vp.height,
    deviceScaleFactor: 1,
  });
  console.log(`[${vp.name}] ${base}`);
  await page.goto(base, { waitUntil: 'networkidle2', timeout: 180000 });
  await new Promise((r) => setTimeout(r, 8000));
  const first = path.join(dir, '01_first_fold_guest.png');
  await page.screenshot({ path: first, fullPage: false });
  console.log(`OK ${first}`);

  // Mobile: scroll a bit to show loginPrompt below fold as well
  if (vp.name === '390') {
    for (let i = 0; i < 12; i++) {
      await page.mouse.wheel({ deltaY: 240 });
      await new Promise((r) => setTimeout(r, 100));
    }
    await new Promise((r) => setTimeout(r, 1500));
    const scroll = path.join(dir, '02_scroll_login_prompt.png');
    await page.screenshot({ path: scroll, fullPage: false });
    console.log(`OK ${scroll}`);
  }

  await page.close();
}

await browser.close();
console.log('done');
