import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const out = path.join(repo, '09-registo-implementacao/SCREENSHOTS');
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

async function scrollReach(page, label) {
  return page.evaluate((lbl) => {
    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
    );
    let n;
    while ((n = walker.nextNode())) {
      if ((n.textContent || '').includes(lbl)) {
        const el = n.parentElement;
        el?.scrollIntoView({ block: 'center', behavior: 'instant' });
        const r = el?.getBoundingClientRect();
        const vh = window.innerHeight;
        if (!r) return { ok: false, reason: 'no rect' };
        return {
          ok: r.bottom > 0 && r.top < vh,
          visible: r.top >= 0 && r.bottom <= vh - 40,
          top: r.top,
          bottom: r.bottom,
          vh,
        };
      }
    }
    return { ok: false, reason: 'not found' };
  }, label);
}

const report = {
  registo: [],
  authSmoke: {},
  googleHidden: {},
  loginPtPt: {},
  notRun: [
    'Criação de conta com e-mail real / confirmação de e-mail',
    'Verificação SMS telemóvel',
    'Sessão autenticada pós-registo + returnTo completo',
    'Google OAuth (botão oculto de propósito)',
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
  const googleVisible = await page.getByText(/Entrar com Google/i).count();
  await acceptCookiesIfAny(page);
  await page.screenshot({
    path: path.join(out, `registo_${name}.png`),
    fullPage: false,
  });
  await page.mouse.wheel(0, 5000);
  await page.waitForTimeout(400);
  const entrarReach = await scrollReach(page, 'Entrar');
  const explorarReach = await scrollReach(page, 'Explorar FleaHub');
  const legalReach = await scrollReach(page, 'Privacidade');
  const body = await page.evaluate(() => document.body?.innerText || '');
  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth + 2,
  );
  report.registo.push({
    name,
    w,
    h,
    cookieBefore,
    googleButtonVisible: googleVisible > 0,
    hasCriarConta: /Criar conta/i.test(body),
    hasPalavraPasse: /Palavra-passe/i.test(body),
    hasCadastre: /Cadastre/i.test(body),
    entrarReach,
    explorarReach,
    legalReach,
    horizontalOverflow: overflow,
    splitExpected: w >= 1024,
  });
  console.log(name, 'google', googleVisible, 'overflow', overflow);
  await page.close();
}

// Auth smoke without credentials
{
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(`${BASE}/registo`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  await acceptCookiesIfAny(page);
  report.authSmoke.googleHidden =
    (await page.getByText(/Entrar com Google/i).count()) === 0;
  await page.getByText('Criar conta', { exact: true }).first().click({
    force: true,
  });
  await page.waitForTimeout(1200);
  await page.screenshot({
    path: path.join(out, 'registo_empty_submit.png'),
    fullPage: false,
  });
  // validation may keep focus on fields without dialog — just capture
  report.authSmoke.emptySubmitCaptured = true;

  await page.goto(`${BASE}/login`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  await acceptCookiesIfAny(page);
  const loginBody = await page.evaluate(() => document.body?.innerText || '');
  report.loginPtPt = {
    hasRegistarSe: /Registar-se/.test(loginBody),
    hasCadastreSe: /Cadastre-se/.test(loginBody),
    hasPalavraPasse: /Palavra-passe/.test(loginBody),
    hasSenhaLabel: /(^|\n)Senha(\n|$)/.test(loginBody),
  };
  await page.screenshot({
    path: path.join(out, 'login_ptpt_check.png'),
    fullPage: false,
  });
  await page.close();
}

report.googleHidden.pass = report.registo.every((r) => !r.googleButtonVisible);

await browser.close();
fs.writeFileSync(
  path.join(repo, '09-registo-implementacao/EVIDENCE.json'),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
