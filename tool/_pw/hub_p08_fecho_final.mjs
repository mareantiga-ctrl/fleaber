import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const out = path.join(repo, '08-login-conta-fecho-final/SCREENSHOTS');
fs.mkdirSync(out, { recursive: true });
fs.mkdirSync(path.join(repo, '08-login-conta-fecho-final/SCREENSHOTS_ANTES'), {
  recursive: true,
});
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
        const cookieH = 220;
        if (!r) return { ok: false, reason: 'no rect' };
        const visible = r.top >= 0 && r.bottom <= vh - 40;
        const aboveCookie = r.bottom <= vh - cookieH || r.top < vh * 0.5;
        return {
          ok: r.bottom > 0 && r.top < vh,
          visible,
          aboveCookie,
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
  login: [],
  registo: [],
  cookies: [],
  authSmoke: {},
  googleHidden: {},
  notRun: [
    'Login e-mail/senha com credenciais reais',
    'Facebook OAuth redirect completo',
    'Google OAuth (botão oculto de propósito)',
    'Sessão autenticada pós-login',
  ],
};

const browser = await chromium.launch({ headless: true });

// Copy ANTES from prior pack if exists
const antesSrc = path.join(
  repo,
  '08-login-conta-implementacao/SCREENSHOTS/login_1920.png',
);
if (fs.existsSync(antesSrc)) {
  fs.copyFileSync(
    antesSrc,
    path.join(repo, '08-login-conta-fecho-final/SCREENSHOTS_ANTES/login_1920_antes.png'),
  );
  fs.copyFileSync(
    path.join(repo, '08-login-conta-implementacao/SCREENSHOTS/login_390.png'),
    path.join(repo, '08-login-conta-fecho-final/SCREENSHOTS_ANTES/login_390_antes.png'),
  );
}

const loginVps = [
  ['390', 390, 844],
  ['390x667', 390, 667],
  ['768', 768, 1024],
  ['1280', 1280, 800],
  ['1920', 1920, 1080],
];

for (const [name, w, h] of loginVps) {
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  await page.goto(`${BASE}/login?returnTo=%2Ffleahub`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  const hadCookie = (await page.getByText('Aceitar').count()) > 0;
  await page.screenshot({
    path: path.join(out, `login_${name}_cookies_before.png`),
    fullPage: false,
  });
  const googleVisible = await page.getByText(/Google/i).count();
  const reachBefore = await scrollReach(page, 'Cadastre-se');
  await acceptCookiesIfAny(page);
  await page.screenshot({
    path: path.join(out, `login_${name}_depois.png`),
    fullPage: false,
  });
  const reachAfter = await scrollReach(page, 'Cadastre-se');
  await page.mouse.wheel(0, 4000);
  await page.waitForTimeout(400);
  const reachScroll = await scrollReach(page, 'Explorar FleaHub');
  const legal = await scrollReach(page, 'Privacidade');
  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth + 2,
  );
  report.login.push({
    name,
    w,
    h,
    cookieBefore: hadCookie,
    googleButtonVisible: googleVisible > 0,
    cadastreReachBefore: reachBefore,
    cadastreReachAfter: reachAfter,
    explorarReach: reachScroll,
    legalReach: legal,
    horizontalOverflow: overflow,
  });
  console.log(name, 'google', googleVisible, 'cookie', hadCookie);
  await page.close();
}

// Registo
for (const [name, w, h] of [
  ['390', 390, 844],
  ['768', 768, 1024],
  ['1280', 1280, 800],
  ['1920', 1920, 1080],
]) {
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  await page.goto(`${BASE}/registo?returnTo=%2Ffleahub`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  await acceptCookiesIfAny(page);
  await page.screenshot({
    path: path.join(out, `registo_${name}.png`),
    fullPage: false,
  });
  const body = await page.evaluate(() => document.body?.innerText || '');
  report.registo.push({
    name,
    hasHeader: /Fleaber|Acesso ao FleaHub|Crie sua conta/i.test(body),
    hasGoogleStub: /Entrar com Google/i.test(body),
    overflow: await page.evaluate(
      () =>
        document.documentElement.scrollWidth >
        document.documentElement.clientWidth + 2,
    ),
  });
  await page.close();
}

// Auth smoke (no credentials)
{
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(`${BASE}/login`, { waitUntil: 'networkidle', timeout: 120000 });
  await settle(page);
  await acceptCookiesIfAny(page);
  report.authSmoke.facebookPresent =
    (await page.getByText('Entrar com Facebook').count()) > 0;
  await page.getByText('Entrar', { exact: true }).first().click({ force: true });
  await page.waitForTimeout(1500);
  const errDialog = await page.getByText(/E-mail inválido|Erro/i).count();
  await page.screenshot({
    path: path.join(out, 'auth_empty_submit.png'),
    fullPage: false,
  });
  report.authSmoke.emptySubmitShowsError = errDialog > 0;
  await page.keyboard.press('Escape').catch(() => {});
  await page.waitForTimeout(300);
  await page.goto(`${BASE}/login`, { waitUntil: 'networkidle', timeout: 120000 });
  await settle(page);
  await acceptCookiesIfAny(page);
  const esqueci = page.getByText('Esqueceu a senha?');
  if (await esqueci.count()) {
    await esqueci.first().click({ force: true });
    await page.waitForTimeout(2500);
    report.authSmoke.esqueciNavigated = page.url().includes('esqueci');
    await page.screenshot({
      path: path.join(out, 'auth_esqueci_senha.png'),
      fullPage: false,
    });
  }
  await page.close();
}

report.googleHidden.pass = report.login.every((r) => !r.googleButtonVisible);

await browser.close();
fs.writeFileSync(
  path.join(repo, '08-login-conta-fecho-final/EVIDENCE.json'),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
