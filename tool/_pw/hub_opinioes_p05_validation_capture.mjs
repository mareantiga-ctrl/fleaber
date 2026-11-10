import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const root = path.join(repo, '05-opinioes-validacao-final/SCREENSHOTS');
fs.mkdirSync(root, { recursive: true });

const viewports = [
  { name: '390', width: 390, height: 844 },
  { name: '430', width: 430, height: 932 },
  { name: '768', width: 768, height: 1024 },
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

async function settle(page) {
  await page.waitForSelector('flt-glass-pane, canvas, flutter-view', {
    timeout: 90000,
  });
  await page.waitForTimeout(4500);
  await dismissCookies(page);
  await page.waitForTimeout(1200);
}

async function semanticsText(page) {
  return page.evaluate(() => {
    const t = document.body?.innerText || '';
    const sem = [...document.querySelectorAll('flt-semantics')]
      .map((e) => e.innerText || e.getAttribute('aria-label') || '')
      .join(' ');
    return `${t}\n${sem}`;
  });
}

const report = {
  base,
  started: new Date().toISOString(),
  shots: [],
  functional: {},
};

const browser = await chromium.launch({ headless: true });
try {
  // Viewport matrix — seller with 60 reviews
  for (const vp of viewports) {
    const page = await browser.newPage({
      viewport: { width: vp.width, height: vp.height },
    });
    await page.goto(`${base}/fleahub-demo-ux/reviews`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await settle(page);
    const text = await semanticsText(page);
    const file = path.join(root, `reviews_60_${vp.name}.png`);
    await page.screenshot({ path: file, fullPage: true });
    report.shots.push({
      case: 'seller_60',
      viewport: vp.name,
      file: path.relative(repo, file),
      hasVerMais: /Ver mais avalia/i.test(text),
      hasOpinioes: /Opini/i.test(text) || /Avalia/i.test(text),
      has60: text.includes('60'),
      snippet: text.replace(/\s+/g, ' ').slice(0, 280),
    });
    console.log(
      `60@${vp.name} verMais=${/Ver mais avalia/i.test(text)} has60=${text.includes('60')}`,
    );
    await page.close();
  }

  // Load more + ler mais
  {
    const page = await browser.newPage({
      viewport: { width: 1280, height: 800 },
    });
    await page.goto(`${base}/fleahub-demo-ux/reviews`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await settle(page);
    const before = await semanticsText(page);
    await page.screenshot({
      path: path.join(root, 'loadmore_before_1280.png'),
      fullPage: true,
    });

    // Click «Ver mais» via Flutter semantics / text
    let clicked = false;
    const verMais = page.getByText(/Ver mais avalia/i);
    if (await verMais.count()) {
      try {
        await verMais.first().click({ timeout: 5000 });
        clicked = true;
      } catch (_) {}
    }
    if (!clicked) {
      // fallback: click bottom-center area where button sits
      await page.mouse.click(640, 720);
    }
    await page.waitForTimeout(3500);
    const after = await semanticsText(page);
    await page.screenshot({
      path: path.join(root, 'loadmore_after_1280.png'),
      fullPage: true,
    });

    const lerMais = page.getByText(/Ler mais/i);
    let lerMaisOk = false;
    if (await lerMais.count()) {
      try {
        await lerMais.first().click({ timeout: 4000 });
        await page.waitForTimeout(800);
        const expanded = await semanticsText(page);
        lerMaisOk = /Mostrar menos/i.test(expanded);
        await page.screenshot({
          path: path.join(root, 'ler_mais_1280.png'),
          fullPage: true,
        });
      } catch (_) {}
    }

    report.functional.loadMore = {
      clicked,
      beforeHasVerMais: /Ver mais avalia/i.test(before),
      afterHasVerMais: /Ver mais avalia/i.test(after),
      beforeHasQaPage: before.includes('QA-P05-PAGE'),
      afterLonger: after.length >= before.length,
      lerMaisOk,
    };
    console.log('loadMore', report.functional.loadMore);
    await page.close();
  }

  // Empty seller
  {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
    });
    await page.goto(`${base}/joao84/reviews`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await settle(page);
    const text = await semanticsText(page);
    await page.screenshot({
      path: path.join(root, 'empty_joao84_390.png'),
      fullPage: true,
    });
    report.functional.empty = {
      hasEmptyCopy: /Ainda sem avalia/i.test(text),
      snippet: text.replace(/\s+/g, ' ').slice(0, 220),
    };
    console.log('empty', report.functional.empty);
    await page.close();
  }

  // 1–10 seller
  {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
    });
    await page.goto(`${base}/vendora-muxb-0913/reviews`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await settle(page);
    const text = await semanticsText(page);
    await page.screenshot({
      path: path.join(root, 'small_5_muxb_390.png'),
      fullPage: true,
    });
    report.functional.small5 = {
      hasVerMais: /Ver mais avalia/i.test(text),
      hasCount: /5 avalia/i.test(text) || text.includes('5'),
      snippet: text.replace(/\s+/g, ' ').slice(0, 220),
    };
    console.log('small5', report.functional.small5);
    await page.close();
  }

  // Filter chip smoke (desktop)
  {
    const page = await browser.newPage({
      viewport: { width: 1440, height: 900 },
    });
    await page.goto(`${base}/fleahub-demo-ux/reviews`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await settle(page);
    const chip = page.getByText('5 ★');
    if (await chip.count()) {
      try {
        await chip.first().click({ timeout: 4000 });
        await page.waitForTimeout(2500);
      } catch (_) {}
    }
    await page.screenshot({
      path: path.join(root, 'filter_5star_1440.png'),
      fullPage: true,
    });
    const text = await semanticsText(page);
    report.functional.filter5 = {
      snippet: text.replace(/\s+/g, ' ').slice(0, 220),
    };
    await page.close();
  }
} finally {
  await browser.close();
}

report.finished = new Date().toISOString();
fs.writeFileSync(
  path.join(root, 'CAPTURE_REPORT.json'),
  JSON.stringify(report, null, 2),
);
console.log('Wrote', path.join(root, 'CAPTURE_REPORT.json'));
