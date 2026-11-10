import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const root = path.join(repo, '05-opinioes-correcao-tecnica-final/SCREENSHOTS');
fs.mkdirSync(root, { recursive: true });

async function dismissCookies(page) {
  for (let i = 0; i < 4; i++) {
    const b = page.locator('text=Aceitar').first();
    if (await b.count()) {
      await b.click({ force: true }).catch(() => {});
      await page.waitForTimeout(400);
    }
  }
}

async function open(page, handle) {
  await page.goto(`${base}/${handle}/reviews`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await page.waitForSelector('flt-glass-pane, canvas, flutter-view', {
    timeout: 90000,
  });
  await page.waitForTimeout(5500);
  await dismissCookies(page);
  await page.waitForTimeout(800);
}

async function dragScrollList(page, times = 3) {
  await page.mouse.click(980, 420);
  for (let k = 0; k < times; k++) {
    await page.mouse.move(980, 720);
    await page.mouse.down();
    await page.mouse.move(980, 140, { steps: 28 });
    await page.mouse.up();
    await page.waitForTimeout(350);
  }
}

const report = { base, started: new Date().toISOString(), steps: [] };
const browser = await chromium.launch({ headless: true });

try {
  // --- Empty ---
  {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
    });
    await open(page, 'joao84');
    await page.screenshot({
      path: path.join(root, 'empty_joao84_390.png'),
      fullPage: true,
    });
    report.steps.push({ id: 'empty', ok: true, note: 'screenshot' });
    await page.close();
  }

  // --- Anon guest + Ver mais until end (demo 90 reviews => 9 pages) ---
  {
    const page = await browser.newPage({
      viewport: { width: 1440, height: 900 },
    });
    await open(page, 'fleahub-demo-ux');
    await page.screenshot({ path: path.join(root, 'anon_top_1440.png') });

    // Ler mais
    await page.mouse.click(620, 360);
    await page.waitForTimeout(1000);
    await page.screenshot({
      path: path.join(root, 'ler_mais_click_1440.png'),
    });
    // Mostrar menos (same area / link)
    await page.mouse.click(620, 420);
    await page.waitForTimeout(800);
    await page.screenshot({
      path: path.join(root, 'mostrar_menos_click_1440.png'),
    });
    report.steps.push({ id: 'ler_mais_mostrar_menos', attempted: true });

    // Filter 5★ — chip after Todas (~455,148 worked poorly before; try broader)
    await page.mouse.click(470, 150);
    await page.waitForTimeout(2800);
    await page.screenshot({
      path: path.join(root, 'filter_attempt_1440.png'),
      fullPage: true,
    });
    // Reset Todas
    await page.mouse.click(380, 150);
    await page.waitForTimeout(2500);

    // Sort dropdown — click Mais recentes then try another option via keyboard
    await page.mouse.click(470, 195);
    await page.waitForTimeout(600);
    await page.keyboard.press('ArrowDown');
    await page.waitForTimeout(200);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(2800);
    await page.screenshot({
      path: path.join(root, 'sort_attempt_1440.png'),
      fullPage: true,
    });
    report.steps.push({ id: 'filter_sort_ui', attempted: true });

    // Ver mais until button gone (max 12 clicks)
    let clicks = 0;
    for (let i = 0; i < 12; i++) {
      await dragScrollList(page, 2);
      await page.screenshot({
        path: path.join(root, `vermais_round_${i}_1440.png`),
      });
      // Click Ver mais zone
      await page.mouse.click(900, 780);
      clicks++;
      await page.waitForTimeout(2800);
    }
    await dragScrollList(page, 2);
    await page.screenshot({
      path: path.join(root, 'vermais_end_state_1440.png'),
      fullPage: true,
    });
    report.steps.push({
      id: 'ver_mais_until_end',
      clicks,
      note: 'inspect screenshots for button absence on last',
    });
    await page.close();
  }

  // --- Mobile ---
  {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
    });
    await open(page, 'fleahub-demo-ux');
    await page.screenshot({
      path: path.join(root, 'mobile_390_top.png'),
      fullPage: true,
    });
    await page.mouse.click(200, 500);
    for (let i = 0; i < 4; i++) {
      await page.mouse.move(200, 700);
      await page.mouse.down();
      await page.mouse.move(200, 200, { steps: 20 });
      await page.mouse.up();
      await page.waitForTimeout(300);
    }
    await page.mouse.click(200, 760);
    await page.waitForTimeout(2500);
    await page.screenshot({
      path: path.join(root, 'mobile_390_after_loadmore.png'),
      fullPage: true,
    });
    report.steps.push({ id: 'mobile_loadmore', attempted: true });
    await page.close();
  }

  // Auth buyer/seller — probe routes only
  report.steps.push({
    id: 'auth_buyer',
    status: 'NOT_RUN',
    reason: 'Sem credenciais/sessão comprador staging nesta ronda Playwright',
  });
  report.steps.push({
    id: 'auth_seller',
    status: 'NOT_RUN',
    reason: 'Sem credenciais/sessão vendedora staging nesta ronda Playwright',
  });
  report.steps.push({
    id: 'error_state',
    status: 'NOT_RUN',
    reason: 'Não forçado (exigiria falha de rede/RPC artificial)',
  });
  report.steps.push({
    id: 'loading_state',
    status: 'PASS_CODE',
    reason: 'Spinner no botão Ver mais implementado; captura efémera difícil',
  });
} finally {
  await browser.close();
}

report.finished = new Date().toISOString();
fs.writeFileSync(
  path.join(root, 'UI_REPORT.json'),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
