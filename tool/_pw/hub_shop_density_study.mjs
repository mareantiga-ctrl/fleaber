import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { createCanvas, loadImage } from 'canvas';

const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const out = path.resolve('../../04-marketplace-density-study');
const shots = path.join(out, 'SCREENSHOTS');

const viewports = [
  { name: '1024', width: 1024, height: 768 },
  { name: '1280', width: 1280, height: 800 },
  { name: '1440', width: 1440, height: 900 },
  { name: '1920', width: 1920, height: 1080 },
];

async function waitShop(page) {
  await page.goto(`${base}/vendedora-prod/shop`, {
    waitUntil: 'domcontentloaded',
    timeout: 120000,
  });
  for (let i = 0; i < 50; i++) {
    await page.waitForTimeout(1000);
    const t = await page.title();
    if (t.includes('encontrada')) continue;
    if (t.includes('A carregar') || t === 'Fleaber') continue;
    // Shop UI can keep profile document.title briefly; URL + settled chrome is enough.
    if (page.url().includes('/shop') && i >= 10) {
      try {
        await page.mouse.click(
          page.viewportSize().width / 2 + 140,
          page.viewportSize().height - 36,
        );
      } catch (_) {}
      await page.waitForTimeout(1200);
      return true;
    }
  }
  return page.url().includes('/shop');
}

async function measure(page) {
  // Theoretical from prototype constants (release has weak a11y).
  const theory = page.evaluate(() => {
    const vw = innerWidth;
    const shopMinCardWidth = 210;
    const shopGridGap = 10;
    const shopGridPadding = 12;
    const shopMaxContentWidth = 1680;
    let contentW;
    if (vw < 700) contentW = 480;
    else if (vw < 1000) contentW = Math.min(vw - 48, 900);
    else contentW = Math.min(vw - 64, shopMaxContentWidth);
    let cols;
    if (vw < 1000) cols = 2;
    else {
      const inner = contentW - shopGridPadding * 2;
      cols = Math.floor((inner + shopGridGap) / (shopMinCardWidth + shopGridGap));
      cols = Math.max(3, Math.min(7, cols));
    }
    const inner = contentW - shopGridPadding * 2;
    const cardW =
      cols > 0 ? (inner - shopGridGap * (cols - 1)) / cols : 0;
    const side = (vw - contentW) / 2;
    return {
      cols,
      cardW: Math.round(cardW),
      cardH: Math.round(cardW / 0.58),
      gutters: shopGridGap,
      contentWidth: Math.round(contentW),
      gridInnerWidth: Math.round(inner),
      sideMarginLeft: Math.round(side),
      sideMarginRight: Math.round(side),
      vw,
      vh: innerHeight,
      method: 'prototype-formula',
    };
  });
  return theory;
}

async function sideBySide(currentPath, compactPath, outPath, label) {
  const a = await loadImage(currentPath);
  const b = await loadImage(compactPath);
  const pad = 24;
  const labelH = 52;
  const gap = 20;
  const targetH = 700;
  const scaleA = targetH / a.height;
  const scaleB = targetH / b.height;
  const wA = Math.round(a.width * scaleA);
  const wB = Math.round(b.width * scaleB);
  const canvas = createCanvas(wA + wB + gap + pad * 2, targetH + labelH + pad * 2);
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#0d1117';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = '#8b949e';
  ctx.font = '16px sans-serif';
  ctx.fillText('ATUAL', pad, pad + 18);
  ctx.fillText('COMPACTO (protótipo)', pad + wA + gap, pad + 18);
  ctx.fillStyle = '#e6edf3';
  ctx.font = 'bold 26px sans-serif';
  ctx.fillText(label, pad, pad + 44);
  ctx.fillText(label, pad + wA + gap, pad + 44);
  ctx.drawImage(a, pad, pad + labelH, wA, targetH);
  ctx.drawImage(b, pad + wA + gap, pad + labelH, wB, targetH);
  // divider
  ctx.fillStyle = '#30363d';
  ctx.fillRect(pad + wA + gap / 2 - 1, pad + labelH, 2, targetH);
  fs.writeFileSync(outPath, canvas.toBuffer('image/png'));
}

const report = { compact: {}, meta: { base, at: new Date().toISOString() } };
const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();
const ok = await waitShop(page);
report.loadOk = ok;
report.loadTitle = await page.title();
report.loadUrl = page.url();
console.log('loaded', report.loadTitle, report.loadUrl);

if (!ok) {
  console.error('SHOP LOAD FAIL');
  process.exit(2);
}

for (const vp of viewports) {
  await page.setViewportSize({ width: vp.width, height: vp.height });
  await page.waitForTimeout(1800);
  await page.mouse.wheel(0, -5000);
  await page.waitForTimeout(500);
  const m = await measure(page);
  report.compact[vp.name] = m;
  const dir = path.join(shots, 'COMPACT', vp.name);
  fs.mkdirSync(dir, { recursive: true });
  await page.screenshot({ path: path.join(dir, 'first.png'), fullPage: false });
  await page.mouse.wheel(0, Math.round(vp.height * 0.35));
  await page.waitForTimeout(400);
  await page.screenshot({ path: path.join(dir, 'first_scrolled.png'), fullPage: false });
  console.log(`[COMPACT ${vp.name}] cols=${m.cols} card≈${m.cardW}x${m.cardH}`);
}

await browser.close();

for (const name of ['1280', '1440', '1920']) {
  const cur = path.join(shots, 'CURRENT', name, 'first.png');
  const cmp = path.join(shots, 'COMPACT', name, 'first.png');
  const outP = path.join(shots, 'COMPARISON', name, 'side_by_side.png');
  fs.mkdirSync(path.dirname(outP), { recursive: true });
  if (fs.existsSync(cur) && fs.existsSync(cmp)) {
    await sideBySide(cur, cmp, outP, name + 'px');
    console.log('comparison', name);
  }
}

// Also copy CURRENT 1024 from validation if exists for docs reference
const cur1024 = path.resolve('../../04-marketplace-final-validation/SCREENSHOTS/1024/first.png');
if (fs.existsSync(cur1024)) {
  fs.mkdirSync(path.join(shots, 'CURRENT', '1024'), { recursive: true });
  fs.copyFileSync(cur1024, path.join(shots, 'CURRENT', '1024', 'first.png'));
}

fs.writeFileSync(path.join(out, 'MEASUREMENTS.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
console.log('DONE');
