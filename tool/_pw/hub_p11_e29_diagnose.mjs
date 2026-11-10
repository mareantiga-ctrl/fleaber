/**
 * E29 — Diagnóstico funcional P11: sessão, 4 destinos, nome (rede).
 * Não imprime tokens nem e-mails completos.
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../reports/hub_p11_e29');
const SHOT = path.join(ROOT, 'screenshots');
const LOG = path.join(ROOT, 'logs');
const base = process.env.P11_BASE || 'http://127.0.0.1:8798';
const email = process.env.P11_EMAIL || 'axinoqua@axinoquaa.pt';
const password = process.env.P11_PASSWORD || 'testeteste';

for (const d of ['nav', 'session', 'name']) {
  fs.mkdirSync(path.join(SHOT, d), { recursive: true });
}
fs.mkdirSync(LOG, { recursive: true });

function redactEmail(e) {
  if (!e || !e.includes('@')) return e ? '[redacted]' : '';
  const [u, d] = e.split('@');
  return `${u.slice(0, 2)}***@${d}`;
}

async function settle(page, ms = 8000) {
  await page.waitForSelector('flt-glass-pane, flutter-view, canvas', {
    timeout: 180000,
  });
  await page.waitForTimeout(ms);
  await page
    .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
    .catch(() => {});
  const a = page.getByText('Aceitar').first();
  if (await a.count()) await a.click({ force: true }).catch(() => {});
  await page.waitForTimeout(300);
}

async function text(page) {
  return page.evaluate(() => document.body?.innerText || '');
}

async function tapExact(page, label) {
  for (let i = 0; i < 10; i++) {
    const hit = await page.evaluate((lbl) => {
      const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      let n;
      while ((n = w.nextNode())) {
        if ((n.textContent || '').trim() === lbl) {
          const el = n.parentElement;
          if (!el) continue;
          const r = el.getBoundingClientRect();
          if (r.width > 0 && r.height > 0) {
            return { x: r.x + r.width / 2, y: r.y + r.height / 2, top: r.top };
          }
        }
      }
      return null;
    }, label);
    if (hit) {
      if (hit.top < 60 || hit.top > 820) {
        await page.mouse.wheel(0, hit.top < 60 ? -280 : 320);
        await page.waitForTimeout(350);
        continue;
      }
      await page.mouse.click(hit.x, hit.y);
      return { ok: true, x: hit.x, y: hit.y };
    }
    await page.mouse.wheel(0, 380);
    await page.waitForTimeout(400);
  }
  return { ok: false };
}

/** Sessão Supabase no storage — só metadados, sem valores. */
async function sessionProbe(page) {
  return page.evaluate(() => {
    const keys = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (!k) continue;
      if (/auth|supabase|sb-/i.test(k)) {
        const v = localStorage.getItem(k) || '';
        keys.push({
          key: k.replace(/eyJ[\w.-]+/g, '[jwt]'),
          bytes: v.length,
          looksJson: v.trim().startsWith('{'),
          hasAccessTokenHint: /access_token|refresh_token/.test(v),
        });
      }
    }
    return {
      authStorageKeys: keys.length,
      keys,
      hash: location.hash,
      hrefPath: location.pathname + location.hash,
    };
  });
}

function classifyPage(t, hash) {
  const login = /Bem-vindo de volta|Palavra-passe|Entrar com Facebook/i.test(t);
  const perfil = /Terminar Sessão|Conta pessoal|Definições de conta/i.test(t);
  const favoritos = /Favoritos/i.test(t) && !perfil && !login;
  const encomendas =
    /Encomenda|Minhas encomendas|Compras/i.test(t) && !perfil && !login;
  const mensagens =
    /Mensagens|Notifica|conversa|Nova contra/i.test(t) && !login;
  const home =
    (/Início|Para ti|Diretos|Explorar/i.test(t) || /homePage/i.test(hash)) &&
    !login &&
    !perfil;
  return { login, perfil, favoritos, encomendas, mensagens, home, hash };
}

function displayNameHint(t) {
  if (/Maria S\./i.test(t)) return 'Maria S.';
  if (/Utilizador Fleaber/i.test(t)) return 'Utilizador Fleaber';
  if (/axinoqua/i.test(t)) return 'email-local';
  return 'unknown';
}

const browser = await chromium.launch({
  headless: true,
  args: ['--use-gl=angle', '--enable-webgl', '--ignore-gpu-blocklist'],
});
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

const netProfiles = [];
page.on('response', async (res) => {
  const u = res.url();
  if (!/\/rest\/v1\/profiles/i.test(u)) return;
  let bodyMeta = { parseOk: false, rowCount: null, hasFullName: null };
  try {
    const j = await res.json();
    if (Array.isArray(j)) {
      bodyMeta = {
        parseOk: true,
        rowCount: j.length,
        hasFullName: j.some(
          (r) => r && typeof r.full_name === 'string' && r.full_name.trim(),
        ),
        fullNameLen: j[0]?.full_name ? String(j[0].full_name).length : 0,
      };
    }
  } catch (_) {
    bodyMeta.parseOk = false;
  }
  netProfiles.push({
    at: new Date().toISOString(),
    status: res.status(),
    ok: res.ok(),
    // query string only — strip keys
    urlPath: u.split('?')[0].replace(/https?:\/\/[^/]+/, ''),
    hasSelect: /select=/i.test(u),
    ...bodyMeta,
  });
});

const report = {
  at: new Date().toISOString(),
  emailUsed: redactEmail(email),
  session: {},
  destinations: [],
  name: {},
  requireAuthNote: {
    Favoritos: true,
    MinhasEncomendas: true,
    Perfil: false,
    HomePage: false,
    ListaConversas: false,
  },
};

// --- LOGIN ---
await page.goto(`${base}/#/login?returnTo=/perfil`, {
  waitUntil: 'domcontentloaded',
  timeout: 180000,
});
await settle(page, 9000);
const inputs = page.locator('input');
if ((await inputs.count()) >= 2) {
  await inputs.nth(0).fill(email);
  await inputs.nth(1).fill(password);
}
await tapExact(page, 'Entrar');
await page.waitForTimeout(12000);
await settle(page, 5000);

await page.goto(`${base}/#/perfil`, { waitUntil: 'domcontentloaded' });
await settle(page, 10000);
await page.waitForTimeout(2000);

const tPerfil = await text(page);
const sessBefore = await sessionProbe(page);
report.session.beforeMenus = {
  probe: sessBefore,
  pageClass: classifyPage(tPerfil, sessBefore.hash),
  displayName: displayNameHint(tPerfil),
  hasTerminarSessao: /Terminar Sessão/i.test(tPerfil),
  hasOwnerMenus: /Favoritos|O meu Saldo|Definições de conta/i.test(tPerfil),
};
await page.screenshot({
  path: path.join(SHOT, 'session', 'P11-session_before_menus.png'),
  fullPage: true,
});

console.log(
  'session before',
  JSON.stringify(report.session.beforeMenus, null, 2),
);

async function ensurePerfil() {
  await page.goto(`${base}/#/perfil`, { waitUntil: 'domcontentloaded' });
  await settle(page, 8000);
  await page.waitForTimeout(1500);
}

/**
 * mode: 'click' | 'hash'
 */
async function testDest({ id, label, hash, expectClass, mode }) {
  await ensurePerfil();
  const beforeT = await text(page);
  const beforeProbe = await sessionProbe(page);
  const beforeShot = path.join(SHOT, 'nav', `P11-${id}_before_${mode}.png`);
  await page.screenshot({ path: beforeShot, fullPage: false });

  const sessionValidBefore =
    report.session.beforeMenus.hasTerminarSessao &&
    beforeProbe.authStorageKeys > 0 &&
    /Terminar Sessão|Conta pessoal|Definições/i.test(beforeT);

  let clicked = false;
  let clickMeta = null;
  if (mode === 'click') {
    clickMeta = await tapExact(page, label);
    clicked = clickMeta.ok;
  } else {
    await page.goto(`${base}/#${hash}`, { waitUntil: 'domcontentloaded' });
    clicked = true; // navigation issued
  }
  await page.waitForTimeout(6000);
  await settle(page, 4000);
  const afterT = await text(page);
  const afterProbe = await sessionProbe(page);
  const afterShot = path.join(SHOT, 'nav', `P11-${id}_after_${mode}.png`);
  await page.screenshot({ path: afterShot, fullPage: false });

  const cls = classifyPage(afterT, afterProbe.hash);
  let result = 'FAIL';
  if (!sessionValidBefore && mode === 'click') {
    result = 'BLOCKED';
  } else if (mode === 'click' && !clicked) {
    result = 'BLOCKED';
  } else if (cls.login && expectClass !== 'login') {
    result = 'FAIL';
  } else if (cls[expectClass]) {
    result = 'PASS';
  } else if (
    expectClass === 'home' &&
    /homePage/i.test(afterProbe.hash) &&
    !cls.login
  ) {
    result = 'PASS';
  } else if (
    expectClass === 'mensagens' &&
    /listaConversas/i.test(afterProbe.hash) &&
    !cls.login
  ) {
    result = 'PASS';
  } else if (
    expectClass === 'favoritos' &&
    /favoritos/i.test(afterProbe.hash) &&
    !cls.login
  ) {
    result = 'PASS';
  } else if (
    expectClass === 'encomendas' &&
    /minhasEncomendas/i.test(afterProbe.hash) &&
    !cls.login
  ) {
    result = 'PASS';
  }

  const row = {
    id,
    label,
    mode,
    expectedRoute: hash,
    expectedClass: expectClass,
    sessionValidBefore,
    authStorageKeysBefore: beforeProbe.authStorageKeys,
    authStorageKeysAfter: afterProbe.authStorageKeys,
    clickExecuted: clicked,
    clickMeta,
    routeBefore: beforeProbe.hrefPath,
    routeAfter: afterProbe.hrefPath,
    pageClassAfter: cls,
    result,
    sampleAfter: afterT.slice(0, 100).replace(/\s+/g, ' '),
  };
  report.destinations.push(row);
  console.log(id, mode, result, row.routeAfter, cls);
  return row;
}

// --- 4 destinos: click then hash (same browser session) ---
const dests = [
  {
    id: 'favoritos',
    label: 'Favoritos',
    hash: '/favoritos',
    expectClass: 'favoritos',
  },
  {
    id: 'encomendas',
    label: 'Encomendas e Compras',
    hash: '/minhasEncomendas',
    expectClass: 'encomendas',
  },
  { id: 'inicio', label: 'Início', hash: '/homePage', expectClass: 'home' },
  {
    id: 'mensagens',
    label: 'Mensagens',
    hash: '/listaConversas',
    expectClass: 'mensagens',
  },
];

for (const d of dests) {
  await testDest({ ...d, mode: 'click' });
  await testDest({ ...d, mode: 'hash' });
}

// --- Nome: timeline + network ---
netProfiles.length = 0;
await page.goto(`${base}/#/homePage`, { waitUntil: 'domcontentloaded' });
await settle(page, 5000);
const nameTimeline = [];
const t0 = Date.now();
await page.goto(`${base}/#/perfil`, { waitUntil: 'domcontentloaded' });
for (const wait of [500, 2000, 5000, 10000, 14000]) {
  const elapsed = Date.now() - t0;
  if (elapsed < wait) await page.waitForTimeout(wait - elapsed);
  const t = await text(page);
  const probe = await sessionProbe(page);
  nameTimeline.push({
    waitMs: Date.now() - t0,
    targetMs: wait,
    displayName: displayNameHint(t),
    degradedBanner: /Não foi possível actualizar os dados do perfil/i.test(t),
    authStorageKeys: probe.authStorageKeys,
    loadingSpinnerHint: t.trim().length < 40,
  });
  await page.screenshot({
    path: path.join(SHOT, 'name', `P11-name_t${wait}.png`),
    fullPage: false,
  });
}
report.name = {
  timeline: nameTimeline,
  profilesNetwork: netProfiles.slice(-10),
  interpretation:
    'Ver 03-DIAGNOSTICO-NOME.md — correlacionar hasFullName na rede com displayName na timeline.',
};

await page.screenshot({
  path: path.join(SHOT, 'name', 'P11-name_final.png'),
  fullPage: true,
});

report.session.afterAll = await sessionProbe(page);

fs.writeFileSync(path.join(LOG, 'diagnose.json'), JSON.stringify(report, null, 2));
fs.writeFileSync(
  path.join(LOG, 'profiles_network.json'),
  JSON.stringify(netProfiles, null, 2),
);
console.log('name timeline', nameTimeline);
console.log('profiles net', netProfiles.slice(-5));
await browser.close();
console.log('done e29');
