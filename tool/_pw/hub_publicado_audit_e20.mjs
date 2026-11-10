/**
 * Entrega 20 — capturas responsivas do Hub publicado (fleaber.pt).
 * Usa playwright de tool/_pw/node_modules.
 */
import { chromium } from './node_modules/playwright/index.mjs';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(__dirname, '../reports/hub_publicado_e20/screenshots');
const EVIDENCE = path.resolve(__dirname, '../reports/hub_publicado_e20/EVIDENCE.json');

const BASE = 'https://fleaber.pt/fleahub/index.html#';
const PAGES = [
  { id: 'P08-login', path: '/login?returnTo=/fleahub' },
  { id: 'P08-login-returnTo', path: '/login?returnTo=/mariana-prod' },
  { id: 'P09-registo', path: '/registo?returnTo=/fleahub' },
  { id: 'P06-not-found', path: '/handle-inexistente-e20-audit' },
  { id: 'P05-reviews', path: '/mariana-prod/reviews' },
  { id: 'P02-profile', path: '/mariana-prod' },
  { id: 'P01-landing', path: '/fleahub' },
];

const VIEWPORTS = [
  { name: 'd1920', width: 1920, height: 1080 },
  { name: 'd1440', width: 1440, height: 900 },
  { name: 'd1280', width: 1280, height: 800 },
  { name: 'd1024', width: 1024, height: 768 },
  { name: 't768', width: 768, height: 1024 },
  { name: 'm390x667', width: 390, height: 667 },
  { name: 'm390x844', width: 390, height: 844 },
];

fs.mkdirSync(OUT, { recursive: true });

function analyze(pageText, html) {
  const t = (pageText || '').toLowerCase();
  const h = (html || '').toLowerCase();
  return {
    has_google_button_text:
      t.includes('entrar com google') || t.includes('continuar com google'),
    has_facebook: t.includes('facebook'),
    has_senha_br: /\bsenha\b/.test(t) && !t.includes('palavra-passe'),
    has_palavra_passe: t.includes('palavra-passe'),
    has_cadastre: t.includes('cadastre'),
    has_criar_conta: t.includes('criar conta') || t.includes('cria a tua conta'),
    has_registar: t.includes('registar') || t.includes('registo'),
    has_cookie: t.includes('cookie') || t.includes('cookies'),
    has_acesso_fleahub: t.includes('fleahub') || t.includes('acesso ao fleahub'),
    has_not_found:
      t.includes('não encontr') ||
      t.includes('nao encontr') ||
      t.includes('página não') ||
      t.includes('pagina nao'),
  };
}

async function settle(page) {
  await page.waitForTimeout(2800);
  // dismiss cookie if present (click best-effort)
  try {
    const btn = page.getByRole('button', {
      name: /aceitar|concordar|ok|entendi|continuar/i,
    });
    if (await btn.first().isVisible({ timeout: 800 })) {
      await btn.first().click({ timeout: 1000 });
      await page.waitForTimeout(400);
    }
  } catch (_) {}
}

const report = {
  generated_at: new Date().toISOString(),
  base: BASE,
  shots: [],
  defects: [],
  summary: {},
};

const browser = await chromium.launch({ headless: true });

for (const vp of VIEWPORTS) {
  const context = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();

  for (const pg of PAGES) {
    const url = `${BASE}${pg.path}`;
    const file = `${pg.id}_${vp.name}.png`;
    const dest = path.join(OUT, file);
    let err = null;
    let flags = {};
    let overflowX = false;
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
      await settle(page);
      const bodyText = await page.evaluate(() => document.body?.innerText || '');
      const html = await page.content();
      flags = analyze(bodyText, html);
      overflowX = await page.evaluate(() => {
        const doc = document.documentElement;
        return doc.scrollWidth > doc.clientWidth + 2;
      });
      // scroll bottom capture for mobile login/registo
      if (pg.id.startsWith('P08') || pg.id.startsWith('P09')) {
        await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
        await page.waitForTimeout(400);
      }
      await page.screenshot({ path: dest, fullPage: true });
      if (overflowX) {
        report.defects.push({
          page: pg.id,
          viewport: vp.name,
          issue: 'overflow_x',
        });
      }
      // Google should not appear as functional option on approved P08/P09
      if (
        (pg.id.startsWith('P08') || pg.id.startsWith('P09')) &&
        flags.has_google_button_text
      ) {
        report.defects.push({
          page: pg.id,
          viewport: vp.name,
          issue: 'google_button_visible',
        });
      }
      if (
        (pg.id.startsWith('P08') || pg.id.startsWith('P09')) &&
        flags.has_senha_br &&
        !flags.has_palavra_passe
      ) {
        report.defects.push({
          page: pg.id,
          viewport: vp.name,
          issue: 'pt_br_senha_instead_of_palavra_passe',
        });
      }
      if (pg.id.startsWith('P09') && flags.has_cadastre) {
        report.defects.push({
          page: pg.id,
          viewport: vp.name,
          issue: 'pt_br_cadastre',
        });
      }
    } catch (e) {
      err = String(e);
      report.defects.push({
        page: pg.id,
        viewport: vp.name,
        issue: 'capture_error',
        detail: err.slice(0, 300),
      });
    }
    report.shots.push({
      page: pg.id,
      viewport: vp.name,
      file,
      url,
      ok: !err && fs.existsSync(dest),
      overflowX,
      flags,
      error: err,
    });
    console.log(`${file} ok=${!err} overflowX=${overflowX}`);
  }
  await context.close();
}

await browser.close();

const byIssue = {};
for (const d of report.defects) {
  byIssue[d.issue] = (byIssue[d.issue] || 0) + 1;
}
report.summary = {
  shots_total: report.shots.length,
  shots_ok: report.shots.filter((s) => s.ok).length,
  defects_count: report.defects.length,
  defects_by_issue: byIssue,
  result:
    report.defects.length === 0
      ? 'PASS'
      : report.shots.filter((s) => s.ok).length > 0
        ? 'PASS_COM_AVISO_OU_FAIL'
        : 'FAIL',
};

fs.writeFileSync(EVIDENCE, JSON.stringify(report, null, 2));
console.log('EVIDENCE', EVIDENCE);
console.log('result', report.summary);
