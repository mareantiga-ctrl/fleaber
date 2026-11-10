import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const out = path.join(repo, '08-login-conta-implementacao/SCREENSHOTS');
fs.mkdirSync(out, { recursive: true });
const BASE = 'http://127.0.0.1:8799';

async function wipeConsent(page) {
  await page.evaluate(async () => {
    try {
      localStorage.clear();
      sessionStorage.clear();
    } catch (_) {}
    try {
      if (indexedDB.databases) {
        const dbs = await indexedDB.databases();
        for (const d of dbs) {
          if (d.name) indexedDB.deleteDatabase(d.name);
        }
      }
    } catch (_) {}
  });
}

async function settle(page) {
  await page.waitForSelector('flt-glass-pane, canvas, flutter-view', {
    timeout: 90000,
  });
  await page.waitForTimeout(5000);
  await page
    .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
    .catch(() => {});
  await page.waitForTimeout(700);
}

async function bodyText(page) {
  return page.evaluate(() => {
    const sem = [...document.querySelectorAll('flt-semantics')]
      .map((e) => e.innerText || e.getAttribute('aria-label') || '')
      .join('\n');
    return `${document.body?.innerText || ''}\n${sem}`;
  });
}

const browser = await chromium.launch({ headless: true });
const report = { viewports: [], cookies: {}, keyboard: {}, notes: [] };

const viewports = [
  ['390', 390, 844],
  ['768', 768, 1024],
  ['1024', 1024, 768],
  ['1280', 1280, 800],
  ['1440', 1440, 900],
  ['1920', 1920, 1080],
];

for (const [name, w, h] of viewports) {
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  await page.goto(`${BASE}/login?returnTo=%2Ffleahub`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await wipeConsent(page);
  await page.reload({ waitUntil: 'networkidle' });
  await settle(page);

  let text = await bodyText(page);
  const beforeCookie = /cookies essenciais/i.test(text);
  await page.screenshot({
    path: path.join(out, `login_${name}_cookies_before.png`),
    fullPage: false,
  });

  const aceitar = page.getByText('Aceitar').first();
  if (await aceitar.count()) {
    await aceitar.click({ force: true }).catch(() => {});
    await page.waitForTimeout(900);
  }
  text = await bodyText(page);
  const afterCookie = /cookies essenciais/i.test(text);
  await page.screenshot({
    path: path.join(out, `login_${name}.png`),
    fullPage: false,
  });

  // overflow check
  const overflow = await page.evaluate(() => {
    const doc = document.documentElement;
    return {
      scrollWidth: doc.scrollWidth,
      clientWidth: doc.clientWidth,
      horizontalOverflow: doc.scrollWidth > doc.clientWidth + 2,
    };
  });

  report.viewports.push({
    name,
    w,
    h,
    cookieBefore: beforeCookie,
    cookieAfterGone: !afterCookie || beforeCookie === false,
    hasGoogleUnavailable: /Google \(indisponível\)|indisponível/i.test(text),
    hasNo123: !/\b123\b/.test(text.replace(/cookies|essential/gi, '')),
    hasFleaHub: /FleaHub|FLEAHUB|Acesso ao FleaHub/i.test(text),
    hasEntrar: /Entrar/i.test(text),
    hasFacebook: /Facebook/i.test(text),
    overflow,
  });
  console.log(
    name,
    'cookieBefore',
    beforeCookie,
    'googleOff',
    report.viewports.at(-1).hasGoogleUnavailable,
    'overflow',
    overflow.horizontalOverflow,
  );
  await page.close();
}

// Keyboard / focus mobile
{
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto(`${BASE}/login?returnTo=%2Ffleahub`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  const aceitar = page.getByText('Aceitar').first();
  if (await aceitar.count()) await aceitar.click({ force: true }).catch(() => {});
  await page.waitForTimeout(500);
  // tap email field via semantics
  const email = page.getByText('E-mail', { exact: true }).first();
  if (await email.count()) {
    await email.click({ force: true }).catch(() => {});
  }
  await page.keyboard.type('qa@example.com');
  await page.waitForTimeout(400);
  await page.screenshot({
    path: path.join(out, 'login_390_keyboard_email.png'),
    fullPage: false,
  });
  const overflowK = await page.evaluate(
    () => document.documentElement.scrollWidth > document.documentElement.clientWidth + 2,
  );
  report.keyboard = {
    viewport: 390,
    typed: true,
    horizontalOverflow: overflowK,
    shot: 'login_390_keyboard_email.png',
  };
  await page.close();
}

// Navigation: Explorar FleaHub
{
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(`${BASE}/login?returnTo=%2Ffleahub`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  const aceitar = page.getByText('Aceitar').first();
  if (await aceitar.count()) await aceitar.click({ force: true }).catch(() => {});
  const explorar = page.getByText('Explorar FleaHub').first();
  if (await explorar.count()) {
    await explorar.click({ force: true });
    await page.waitForTimeout(3500);
  }
  report.nav = {
    afterExplorar: page.url(),
    onFleahub: page.url().includes('/fleahub'),
  };
  await page.screenshot({
    path: path.join(out, 'login_nav_explorar_1280.png'),
    fullPage: false,
  });
  await page.close();
}

await browser.close();
fs.writeFileSync(
  path.join(repo, '08-login-conta-implementacao/EVIDENCE.json'),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
