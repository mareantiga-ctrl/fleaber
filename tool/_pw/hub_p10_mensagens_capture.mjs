/**
 * P10 Mensagens — login staging + capturas lista/conversa.
 * Uso: node hub_p10_mensagens_capture.mjs [base] [before|after]
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const phase = process.argv[3] || 'before';
const OUT = path.resolve(
  __dirname,
  `../reports/hub_p10_mensagens/screenshots/${phase}`,
);
fs.mkdirSync(OUT, { recursive: true });

const base = process.argv[2] || 'http://127.0.0.1:8798';
const email = process.env.P10_EMAIL || 'axinoqua@axinoquaa.pt';
const password = process.env.P10_PASSWORD || 'testeteste';

const viewports = [
  ['m390', 390, 844],
  ['t768', 768, 1024],
  ['d1024', 1024, 768],
  ['d1280', 1280, 800],
  ['d1440', 1440, 900],
  ['d1920', 1920, 1080],
];

async function settle(page) {
  await page.waitForSelector('flt-glass-pane, flutter-view, canvas', {
    timeout: 120000,
  });
  await page.waitForTimeout(5000);
  await page
    .evaluate(() =>
      document.querySelector('flt-semantics-placeholder')?.click(),
    )
    .catch(() => {});
  await page.waitForTimeout(600);
  const aceitar = page.getByText('Aceitar').first();
  if (await aceitar.count()) {
    await aceitar.click({ force: true }).catch(() => {});
    await page.waitForTimeout(500);
  }
}

async function bodyText(page) {
  return page.evaluate(() => document.body?.innerText || '');
}

async function waitForText(page, re, ms = 45000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    const t = await bodyText(page);
    if (re.test(t)) return t;
    await page.waitForTimeout(1000);
  }
  return bodyText(page);
}

async function tapByText(page, label) {
  const hit = await page.evaluate((lbl) => {
    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
    );
    let n;
    while ((n = walker.nextNode())) {
      if ((n.textContent || '').trim() === lbl) {
        const el = n.parentElement;
        if (!el) continue;
        const r = el.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) {
          return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
        }
      }
    }
    return null;
  }, label);
  if (!hit) return false;
  await page.mouse.click(hit.x, hit.y);
  return true;
}

async function fillLogin(page) {
  // Prefer semantics / inputs if present
  const inputs = page.locator('input');
  const count = await inputs.count();
  if (count >= 2) {
    await inputs.nth(0).fill(email);
    await inputs.nth(1).fill(password);
    return true;
  }
  // CanvasKit: click fields by label then type
  await tapByText(page, 'E-mail');
  await page.keyboard.type(email, { delay: 20 });
  await tapByText(page, 'Palavra-passe');
  await page.keyboard.type(password, { delay: 20 });
  return true;
}

const browser = await chromium.launch({
  headless: true,
  args: ['--use-gl=angle', '--enable-webgl', '--ignore-gpu-blocklist'],
});

const report = { phase, base, email, shots: [], loginOk: false, notes: [] };

// One authenticated context at 1280, then resize for list shots + open chat
{
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const logs = [];
  page.on('console', (m) => {
    if (/ERROR|Exception|401|permission/i.test(m.text())) {
      logs.push(m.text().slice(0, 160));
    }
  });

  await page.goto(`${base}/#/login?returnTo=/listaConversas`, {
    waitUntil: 'domcontentloaded',
    timeout: 120000,
  });
  await settle(page);
  let text = await waitForText(page, /Entrar|E-mail|Palavra-passe|Mensagens/i);
  report.notes.push({ step: 'login_land', text: text.slice(0, 200) });

  if (/Mensagens|Notificações|Ainda não tens conversas/i.test(text)) {
    report.loginOk = true;
    report.notes.push({ step: 'already_session' });
  } else {
    await fillLogin(page);
    await page.waitForTimeout(400);
    const tapped = await tapByText(page, 'Entrar');
    report.notes.push({ step: 'tap_entrar', tapped });
    await page.waitForTimeout(8000);
    text = await waitForText(
      page,
      /Mensagens|Notificações|Ainda não tens conversas|Utilizador|Proposta/i,
      60000,
    );
    report.loginOk = /Mensagens|Notificações|Ainda não tens conversas|Utilizador/i.test(
      text,
    );
    report.notes.push({ step: 'after_login', text: text.slice(0, 240) });
  }

  if (!report.loginOk) {
    // Force navigate in case returnTo failed
    await page.goto(`${base}/#/listaConversas`, {
      waitUntil: 'domcontentloaded',
      timeout: 60000,
    });
    await settle(page);
    text = await waitForText(
      page,
      /Mensagens|Notificações|Ainda não tens conversas|login|Entrar/i,
      30000,
    );
    report.loginOk = /Mensagens|Notificações|Ainda não tens conversas/i.test(
      text,
    );
    report.notes.push({ step: 'force_lista', text: text.slice(0, 240) });
  }

  // Capture list at each viewport (same session)
  for (const [name, w, h] of viewports) {
    await page.setViewportSize({ width: w, height: h });
    await page.waitForTimeout(2500);
    await page.goto(`${base}/#/listaConversas`, {
      waitUntil: 'domcontentloaded',
      timeout: 60000,
    });
    await settle(page);
    await waitForText(
      page,
      /Mensagens|Notificações|Ainda não tens conversas|Utilizador|Proposta|Entrar/i,
      40000,
    );
    const file = path.join(OUT, `P10-lista_${name}.png`);
    await page.screenshot({ path: file, fullPage: false });
    const t = await bodyText(page);
    report.shots.push({
      name: `lista_${name}`,
      bytes: fs.statSync(file).size,
      ok: fs.statSync(file).size > 20000,
      hasList: /Mensagens|Ainda não tens conversas|Utilizador|Proposta/i.test(t),
      loadingOnly: /loading|CircularProgress|a carregar/i.test(t) && t.length < 40,
      textSample: t.slice(0, 180),
    });
  }

  // Open first conversation if possible (desktop)
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto(`${base}/#/listaConversas`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  await settle(page);
  await waitForText(page, /Mensagens|Utilizador|Proposta|Ainda não/i, 40000);

  // Click roughly first conversation row area (below tabs)
  await page.mouse.click(320, 220);
  await page.waitForTimeout(6000);
  let chatText = await bodyText(page);
  if (!/Chat|Escreve|Enviar|proposta|Artigo|arrow/i.test(chatText)) {
    // try deeper click
    await page.mouse.click(340, 280);
    await page.waitForTimeout(6000);
    chatText = await bodyText(page);
  }
  const chatFile = path.join(OUT, 'P10-conversa_d1280.png');
  await page.screenshot({ path: chatFile, fullPage: false });
  report.shots.push({
    name: 'conversa_d1280',
    bytes: fs.statSync(chatFile).size,
    ok: fs.statSync(chatFile).size > 20000,
    open: !/Ainda não tens conversas/.test(chatText) &&
      chatText.length > 20,
    textSample: chatText.slice(0, 240),
  });

  // Mobile list + open
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${base}/#/listaConversas`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  await settle(page);
  await page.mouse.click(200, 240);
  await page.waitForTimeout(6000);
  const mChat = path.join(OUT, 'P10-conversa_m390.png');
  await page.screenshot({ path: mChat, fullPage: false });
  report.shots.push({
    name: 'conversa_m390',
    bytes: fs.statSync(mChat).size,
    textSample: (await bodyText(page)).slice(0, 200),
  });

  report.logs = logs.slice(0, 12);
  await context.close();
}

await browser.close();
fs.writeFileSync(
  path.resolve(OUT, `../../EVIDENCE_${phase}.json`),
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify({
  phase,
  loginOk: report.loginOk,
  shots: report.shots.map((s) => ({
    name: s.name,
    bytes: s.bytes,
    ok: s.ok,
    hasList: s.hasList,
  })),
  notes: report.notes,
}, null, 2));
process.exit(report.loginOk ? 0 : 2);
