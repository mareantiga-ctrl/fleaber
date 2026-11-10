/**
 * E21 P08 — Aceitar cookies no Hub publicado (mobile 390×844).
 * PASS só com clique real que persiste após reload.
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const OUT = path.resolve('tool/reports/hub_e21/p08');
const URL = 'https://fleaber.pt/fleahub/index.html#/login?returnTo=/fleahub';
const KEY = 'fleaber_cookie_consent_v1';
const VIEWPORT = { width: 390, height: 844 };

fs.mkdirSync(OUT, { recursive: true });

async function dumpPrefs(page) {
  return page.evaluate((key) => {
    const all = {};
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      all[k] = localStorage.getItem(k);
    }
    const cookieish = {};
    for (const [k, v] of Object.entries(all)) {
      if (/cookie|fleaber|consent/i.test(k)) cookieish[k] = v;
    }
    return {
      direct: localStorage.getItem(key),
      flutter: localStorage.getItem('flutter.' + key),
      cookieish,
      allKeys: Object.keys(all),
    };
  }, KEY);
}

function isAccepted(p) {
  const vals = [p.direct, p.flutter, ...Object.values(p.cookieish || {})];
  return vals.some((v) => v === 'true' || v === '1' || v === true);
}

async function clearConsent(page) {
  await page.evaluate((key) => {
    for (const k of [...Object.keys(localStorage)]) {
      if (k.includes(key) || /cookie|consent/i.test(k)) {
        localStorage.removeItem(k);
      }
    }
  }, KEY);
}

async function tryLocatorClick(page) {
  const makers = [
    () => page.getByRole('button', { name: 'Aceitar' }),
    () => page.getByText('Aceitar', { exact: true }),
    () => page.locator('flt-semantics >> text=Aceitar'),
    () => page.locator('[aria-label="Aceitar"]'),
  ];
  for (let i = 0; i < makers.length; i++) {
    try {
      const loc = makers[i]();
      const n = await loc.count();
      if (n > 0) {
        await loc.first().click({ timeout: 4000, force: true });
        return 'locator_' + i;
      }
    } catch {
      /* next */
    }
  }
  return null;
}

async function tryCoordClick(page) {
  const points = [
    [320, 780],
    [330, 800],
    [340, 820],
    [300, 790],
    [350, 810],
    [280, 770],
    [360, 830],
    [310, 760],
  ];
  for (const [x, y] of points) {
    await page.mouse.click(x, y);
    await page.waitForTimeout(700);
    const d = await dumpPrefs(page);
    if (isAccepted(d)) return `coords_${x}_${y}`;
  }
  return null;
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: VIEWPORT,
  deviceScaleFactor: 2,
  locale: 'pt-PT',
});
const page = await context.newPage();
const ev = {
  generated_at: new Date().toISOString(),
  url: URL,
  viewport: VIEWPORT,
  prefs_key: KEY,
  steps: [],
  result: 'FAIL',
};

try {
  await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 90000 });
  await page.waitForTimeout(6000);
  await clearConsent(page);
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: path.join(OUT, '01_before_accept.png') });
  ev.steps.push({ step: 'before', prefs: await dumpPrefs(page) });

  let clickMethod = await tryLocatorClick(page);
  if (!clickMethod) clickMethod = await tryCoordClick(page);

  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(OUT, '03_after_click.png') });
  const afterClick = await dumpPrefs(page);
  ev.steps.push({ step: 'after_click', clickMethod, prefs: afterClick });

  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: path.join(OUT, '05_after_reload.png') });
  const afterReload = await dumpPrefs(page);
  ev.steps.push({ step: 'after_reload', prefs: afterReload });

  const genuine =
    !!clickMethod && isAccepted(afterClick) && isAccepted(afterReload);
  ev.result = genuine ? 'PASS' : 'FAIL';
  ev.note = genuine
    ? 'Aceitar dispensou e persistiu após reload'
    : `clickMethod=${clickMethod}; consent não persistiu de forma verificável após clique real`;

  // Accessibility after: capture that login chrome still renders
  await page.screenshot({ path: path.join(OUT, '06_form_state.png') });
} catch (e) {
  ev.error = String(e);
  ev.result = 'FAIL';
} finally {
  fs.writeFileSync(path.join(OUT, 'EVIDENCE.json'), JSON.stringify(ev, null, 2));
  console.log(
    JSON.stringify(
      {
        result: ev.result,
        note: ev.note,
        clickMethod: ev.steps.find((s) => s.step === 'after_click')?.clickMethod,
        error: ev.error,
      },
      null,
      2,
    ),
  );
  await browser.close();
  process.exit(ev.result === 'PASS' ? 0 : 2);
}
