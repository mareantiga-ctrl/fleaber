import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const out = path.join(repo, '14-p09-fecho-visual/SCREENSHOTS');
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
  await page.waitForTimeout(700);
}

async function acceptCookiesIfAny(page) {
  const aceitar = page.getByText('Aceitar').first();
  if (await aceitar.count()) {
    await aceitar.click({ force: true }).catch(() => {});
    await page.waitForTimeout(800);
    return true;
  }
  return false;
}

async function findTextRect(page, label) {
  return page.evaluate((lbl) => {
    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
    );
    let n;
    while ((n = walker.nextNode())) {
      if ((n.textContent || '').includes(lbl)) {
        const el = n.parentElement;
        const r = el?.getBoundingClientRect();
        if (!r) return null;
        return { top: r.top, bottom: r.bottom, vh: window.innerHeight };
      }
    }
    return null;
  }, label);
}

async function scrollUntilVisible(page, label, maxSteps = 12) {
  for (let i = 0; i < maxSteps; i++) {
    const r = await findTextRect(page, label);
    if (r && r.top >= 0 && r.bottom <= r.vh - 8) {
      return { ok: true, steps: i, ...r };
    }
    await page.mouse.wheel(0, 320);
    await page.waitForTimeout(250);
  }
  const last = await findTextRect(page, label);
  return { ok: !!(last && last.bottom > 0 && last.top < last.vh), steps: maxSteps, ...last };
}

const report = {
  registo: [],
  loginRegression: {},
  googleHidden: true,
  texts: {},
  notRun: [
    'Registo + confirmação e-mail com conta de teste',
    'SMS telemóvel',
    'returnTo pós-registo autenticado',
  ],
};

const browser = await chromium.launch({ headless: true });
const viewports = [
  ['390x667', 390, 667],
  ['390x844', 390, 844],
  ['768', 768, 1024],
  ['1024', 1024, 768],
  ['1280', 1280, 800],
  ['1440', 1440, 900],
  ['1920', 1920, 1080],
];

for (const [name, w, h] of viewports) {
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  await page.goto(`${BASE}/registo?returnTo=%2Ffleahub`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  const cookieBefore = (await page.getByText('Aceitar').count()) > 0;
  await page.screenshot({
    path: path.join(out, `registo_${name}_cookies_before.png`),
    fullPage: false,
  });
  const google = (await page.getByText(/Entrar com Google/i).count()) > 0;
  if (google) report.googleHidden = false;

  // Scroll com cookies ainda visíveis até «Criar conta» / links
  const criarReachCookies = await scrollUntilVisible(page, 'Criar conta');
  await page.screenshot({
    path: path.join(out, `registo_${name}_scroll_criar_cookies.png`),
    fullPage: false,
  });
  const legalReachCookies = await scrollUntilVisible(page, 'Privacidade');
  await page.screenshot({
    path: path.join(out, `registo_${name}_scroll_fim_cookies.png`),
    fullPage: false,
  });

  await acceptCookiesIfAny(page);
  await page.screenshot({
    path: path.join(out, `registo_${name}.png`),
    fullPage: false,
  });
  const criarAfter = await scrollUntilVisible(page, 'Criar conta');
  const explorarAfter = await scrollUntilVisible(page, 'Explorar FleaHub');

  const body = await page.evaluate(() => document.body?.innerText || '');
  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth + 2,
  );

  // Teclado simulado (view inset) — Flutter web usa resize; aproximação via CDP
  let keyboardShot = null;
  if (name === '390x667' || name === '390x844') {
    await page.evaluate(() => {
      window.scrollTo(0, 0);
    });
    await page.getByText('E-mail').first().click({ force: true }).catch(() => {});
    await page.waitForTimeout(400);
    await page.keyboard.type('qa@example.com');
    await page.waitForTimeout(600);
    await page.screenshot({
      path: path.join(out, `registo_${name}_teclado.png`),
      fullPage: false,
    });
    keyboardShot = true;
    const criarKb = await scrollUntilVisible(page, 'Criar conta');
    keyboardShot = { typed: true, criarReach: criarKb };
  }

  report.registo.push({
    name,
    w,
    h,
    cookieBefore,
    google,
    criarReachCookies,
    legalReachCookies,
    criarAfter,
    explorarAfter,
    hasCriaTuaConta: /Cria a tua conta/i.test(body),
    hasJuntaTe: /Junta-te à Fleaber/i.test(body),
    hasEntraParaContinuares: /Entra para continuares para o FleaHub/i.test(body),
    horizontalOverflow: overflow,
    keyboardShot,
  });
  console.log(name, 'overflow', overflow, 'criarCookies', criarReachCookies.ok);
  await page.close();
}

// P08 smoke
{
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(`${BASE}/login?returnTo=%2Ffleahub`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  await acceptCookiesIfAny(page);
  await page.screenshot({
    path: path.join(out, 'login_p08_regressao.png'),
    fullPage: false,
  });
  const body = await page.evaluate(() => document.body?.innerText || '');
  report.loginRegression = {
    hasFacebook: /Entrar com Facebook/i.test(body),
    hasRegistarSe: /Registar-se/i.test(body),
    hasPalavraPasse: /Palavra-passe/i.test(body),
    hasGoogle: /Entrar com Google/i.test(body),
  };
  await page.close();
}

report.texts = {
  noLoginCopyOnRegisto: report.registo.every((r) => !r.hasEntraParaContinuares),
  allHaveCriaTuaConta: report.registo.every((r) => r.hasCriaTuaConta),
};

await browser.close();
fs.writeFileSync(
  path.join(repo, '14-p09-fecho-visual/EVIDENCE.json'),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
