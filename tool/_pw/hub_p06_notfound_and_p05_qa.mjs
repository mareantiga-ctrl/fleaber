import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const base = process.argv[2] ?? 'http://127.0.0.1:8799';
const root = path.join(repo, '06-not-found-implementacao-e-auditoria');
const shots = path.join(root, 'SCREENSHOTS');
fs.mkdirSync(shots, { recursive: true });

async function dismissCookies(page) {
  for (let i = 0; i < 4; i++) {
    const b = page.locator('text=Aceitar').first();
    if (await b.count()) {
      await b.click({ force: true }).catch(() => {});
      await page.waitForTimeout(350);
    }
  }
}

async function enableSemantics(page) {
  await page
    .evaluate(() => {
      document.querySelector('flt-semantics-placeholder')?.click();
    })
    .catch(() => {});
  await page.waitForTimeout(500);
}

async function settle(page) {
  await page.waitForSelector('flt-glass-pane, canvas, flutter-view', {
    timeout: 90000,
  });
  await page.waitForTimeout(4500);
  await dismissCookies(page);
  await enableSemantics(page);
  await page.waitForTimeout(800);
}

const report = { base, started: new Date().toISOString(), p06: [], p05: [] };
const browser = await chromium.launch({ headless: true });

try {
  // ========== P06 viewports ==========
  const viewports = [
    { name: '390', width: 390, height: 844 },
    { name: '768', width: 768, height: 1024 },
    { name: '1280', width: 1280, height: 800 },
    { name: '1440', width: 1440, height: 900 },
    { name: '1920', width: 1920, height: 1080 },
  ];
  for (const vp of viewports) {
    const page = await browser.newPage({
      viewport: { width: vp.width, height: vp.height },
    });
    await page.goto(`${base}/esta-loja-nao-existe-xyz-404`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await settle(page);
    const file = path.join(shots, `p06_404_${vp.name}.png`);
    await page.screenshot({ path: file, fullPage: true });
    const hasCta = (await page.getByText('Ir para o início').count()) > 0;
    const hasHeadline =
      (await page.getByText('Esta página não existe').count()) > 0;
    report.p06.push({
      viewport: vp.name,
      hasCta,
      hasHeadline,
      file: path.relative(repo, file),
    });
    console.log(`P06 ${vp.name} cta=${hasCta} headline=${hasHeadline}`);
    await page.close();
  }

  // CTA click
  {
    const page = await browser.newPage({
      viewport: { width: 1280, height: 800 },
    });
    await page.goto(`${base}/handle-invalido-qa-06`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await settle(page);
    const cta = page.getByText('Ir para o início');
    if (await cta.count()) {
      await cta.first().click({ force: true });
      await page.waitForTimeout(3500);
    }
    await page.screenshot({
      path: path.join(shots, 'p06_cta_after_click_1280.png'),
      fullPage: true,
    });
    report.p06.push({
      id: 'cta_click',
      urlAfter: page.url(),
      left404: !page.url().includes('handle-invalido'),
    });
    await page.close();
  }

  // Valid route not broken
  {
    const page = await browser.newPage({
      viewport: { width: 1280, height: 800 },
    });
    await page.goto(`${base}/fleahub-demo-ux`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await settle(page);
    await page.screenshot({
      path: path.join(shots, 'p06_valid_seller_not_404_1280.png'),
      fullPage: false,
    });
    const is404 = (await page.getByText('Esta página não existe').count()) > 0;
    report.p06.push({ id: 'valid_route', is404, url: page.url() });
    await page.close();
  }

  // ========== P05 sort UI ==========
  {
    const page = await browser.newPage({
      viewport: { width: 1440, height: 900 },
    });
    await page.goto(`${base}/fleahub-demo-ux/reviews`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await settle(page);
    await page.screenshot({
      path: path.join(shots, 'p05_sort_newest_1440.png'),
      fullPage: false,
    });

    const sorts = [
      { label: 'Mais antigas', key: 'oldest' },
      { label: 'Melhor nota', key: 'highest' },
      { label: 'Pior nota', key: 'lowest' },
      { label: 'Mais recentes', key: 'newest' },
    ];
    for (const s of sorts) {
      // Open dropdown
      const trigger = page.getByText('Mais recentes').or(page.getByText('Mais antigas')).or(page.getByText('Melhor nota')).or(page.getByText('Pior nota'));
      if (await trigger.count()) {
        await trigger.first().click({ force: true }).catch(() => {});
        await page.waitForTimeout(600);
      }
      const opt = page.getByText(s.label, { exact: true });
      if (await opt.count()) {
        await opt.last().click({ force: true }).catch(() => {});
        await page.waitForTimeout(2800);
      }
      await page.screenshot({
        path: path.join(shots, `p05_sort_${s.key}_1440.png`),
        fullPage: false,
      });
      report.p05.push({
        id: `sort_${s.key}`,
        label: s.label,
        attempted: true,
      });
      console.log('sort', s.key);
    }
    await page.close();
  }

  // ========== P05 Ver mais until gone ==========
  {
    const page = await browser.newPage({
      viewport: { width: 1440, height: 900 },
    });
    await page.goto(`${base}/fleahub-demo-ux/reviews`, {
      waitUntil: 'networkidle',
      timeout: 120000,
    });
    await settle(page);
    let clicks = 0;
    let lastHas = true;
    for (let i = 0; i < 15; i++) {
      await enableSemantics(page);
      // scroll list
      await page.mouse.click(980, 420);
      for (let k = 0; k < 2; k++) {
        await page.mouse.move(980, 720);
        await page.mouse.down();
        await page.mouse.move(980, 140, { steps: 24 });
        await page.mouse.up();
        await page.waitForTimeout(250);
      }
      const btn = page.getByText('Ver mais avaliações', { exact: false });
      const n = await btn.count();
      lastHas = n > 0;
      await page.screenshot({
        path: path.join(shots, `p05_vermais_${i}_1440.png`),
      });
      if (!lastHas) break;
      await btn.first().click({ force: true }).catch(async () => {
        await page.mouse.click(900, 780);
      });
      clicks++;
      await page.waitForTimeout(2600);
    }
    await page.screenshot({
      path: path.join(shots, 'p05_vermais_final_1440.png'),
      fullPage: true,
    });
    report.p05.push({
      id: 'ver_mais_until_end',
      clicks,
      buttonGone: !lastHas,
    });
    console.log('vermais clicks', clicks, 'gone', !lastHas);
    await page.close();
  }

  // ========== P05 error state (network abort) ==========
  {
    const page = await browser.newPage({
      viewport: { width: 1280, height: 800 },
    });
    await page.route('**/rest/v1/rpc/batata_hub_reviews_public_**', (route) =>
      route.abort('failed'),
    );
    await page.goto(`${base}/fleahub-demo-ux/reviews`, {
      waitUntil: 'domcontentloaded',
      timeout: 120000,
    });
    await page.waitForTimeout(7000);
    await dismissCookies(page);
    await enableSemantics(page);
    await page.screenshot({
      path: path.join(shots, 'p05_error_state_1280.png'),
      fullPage: true,
    });
    const hasError =
      (await page.getByText('Não foi possível carregar').count()) > 0 ||
      (await page.getByText('Tentar novamente').count()) > 0;
    // Unblock and retry
    await page.unroute('**/rest/v1/rpc/batata_hub_reviews_public_**');
    const retry = page.getByText('Tentar novamente');
    if (await retry.count()) {
      await retry.first().click({ force: true }).catch(() => {});
      await page.waitForTimeout(5000);
    }
    await page.screenshot({
      path: path.join(shots, 'p05_error_retry_1280.png'),
      fullPage: true,
    });
    const recovered =
      (await page.getByText('Opiniões').count()) > 0 ||
      (await page.getByText('avaliações').count()) > 0;
    report.p05.push({
      id: 'error_state',
      hasError,
      recoveredAfterRetry: recovered,
    });
    console.log('error', hasError, 'recovered', recovered);
    await page.close();
  }
} finally {
  await browser.close();
}

report.finished = new Date().toISOString();
fs.writeFileSync(
  path.join(root, 'QA_P05_AND_P06_REPORT.json'),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
