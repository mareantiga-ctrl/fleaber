import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const out = path.join(repo, '08-login-conta-proposta/SCREENSHOTS_ATUAL');
fs.mkdirSync(out, { recursive: true });
const BASE = 'http://127.0.0.1:8799';

async function settle(page) {
  await page.waitForSelector('flt-glass-pane, canvas, flutter-view', {
    timeout: 90000,
  });
  await page.waitForTimeout(4500);
  await page
    .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
    .catch(() => {});
  await page.waitForTimeout(600);
}

const browser = await chromium.launch({ headless: true });
const viewports = [
  { name: '390', w: 390, h: 844 },
  { name: '768', w: 768, h: 1024 },
  { name: '1024', w: 1024, h: 768 },
  { name: '1280', w: 1280, h: 800 },
  { name: '1440', w: 1440, h: 900 },
  { name: '1920', w: 1920, h: 1080 },
];

const report = { shots: [], notes: [] };

for (const vp of viewports) {
  const page = await browser.newPage({
    viewport: { width: vp.w, height: vp.h },
  });
  // Force cookie banner: clear prefs before load
  await page.goto(`${BASE}/login?returnTo=%2Ffleahub`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await page.evaluate(() => {
    try {
      localStorage.clear();
      // shared_preferences web often uses localStorage keys
      for (const k of Object.keys(localStorage)) {
        if (k.toLowerCase().includes('cookie') || k.includes('fleaber')) {
          localStorage.removeItem(k);
        }
      }
    } catch (_) {}
  });
  await page.reload({ waitUntil: 'networkidle' });
  await settle(page);

  const body = await page.evaluate(() => {
    const sem = [...document.querySelectorAll('flt-semantics')]
      .map((e) => e.innerText || e.getAttribute('aria-label') || '')
      .join('\n');
    return `${document.body?.innerText || ''}\n${sem}`;
  });

  await page.screenshot({
    path: path.join(out, `login_atual_${vp.name}_cookies.png`),
    fullPage: false,
  });

  // Accept cookies and reshoot
  const aceitar = page.getByText('Aceitar').first();
  if (await aceitar.count()) {
    await aceitar.click({ force: true }).catch(() => {});
    await page.waitForTimeout(800);
  }
  await page.screenshot({
    path: path.join(out, `login_atual_${vp.name}.png`),
    fullPage: false,
  });

  report.shots.push({
    viewport: vp.name,
    hasGoogle123:
      body.includes('123') || /onetwothree|Entrar com Google/i.test(body),
    hasCookieText: /cookies essenciais/i.test(body),
    hasFleaHubChip: /Acesso ao FleaHub/i.test(body),
    hasEmail: /E-mail|Email/i.test(body),
    formLooksNarrow: vp.w >= 1024,
  });
  console.log(vp.name, 'cookie', report.shots.at(-1).hasCookieText, 'google', report.shots.at(-1).hasGoogle123);
  await page.close();
}

await browser.close();
fs.writeFileSync(
  path.join(repo, '08-login-conta-proposta/EVIDENCE_ATUAL.json'),
  JSON.stringify(report, null, 2),
);
