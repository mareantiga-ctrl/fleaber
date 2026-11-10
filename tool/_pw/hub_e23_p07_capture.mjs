/**
 * Capturas P07 hub-dev — requer servidor local Flutter web.
 * Uso: node hub_e23_p07_capture.mjs [baseUrl]
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(__dirname, '../reports/hub_e23_p07/screenshots');
fs.mkdirSync(OUT, { recursive: true });

const base =
  process.argv[2] ||
  'http://127.0.0.1:8765/#/hub-dev';

const viewports = [
  { name: 'm390x844', width: 390, height: 844 },
  { name: 't768', width: 768, height: 1024 },
  { name: 'd1280', width: 1280, height: 800 },
  { name: 'd1440', width: 1440, height: 900 },
  { name: 'd1920', width: 1920, height: 1080 },
];

async function settle(page) {
  await page.waitForSelector('flt-glass-pane, canvas, flutter-view', {
    timeout: 120000,
  });
  await page.waitForTimeout(6000);
  await page
    .evaluate(() =>
      document.querySelector('flt-semantics-placeholder')?.click(),
    )
    .catch(() => {});
  await page.waitForTimeout(800);
  // Cookie banner (Aceitar) — force click se existir no DOM de acessibilidade
  const aceitar = page.getByText('Aceitar').first();
  if (await aceitar.count()) {
    await aceitar.click({ force: true }).catch(() => {});
    await page.waitForTimeout(600);
  }
}

const browser = await chromium.launch({ headless: true });
const shots = [];
for (const vp of viewports) {
  const context = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  try {
    await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 180000 });
    await settle(page);
    // Extra settle for larger canvases
    if (vp.width >= 1280) {
      await page.waitForTimeout(4000);
    }
    const file = path.join(OUT, `P07-hub-dev_${vp.name}.png`);
    await page.screenshot({ path: file, fullPage: false });
    const bytes = fs.statSync(file).size;
    const text = await page.evaluate(() => document.body?.innerText || '');
    shots.push({
      ...vp,
      file,
      bytes,
      ok: bytes > 15000,
      textSample: text.slice(0, 240),
    });
  } catch (e) {
    shots.push({ ...vp, ok: false, error: String(e) });
  }
  await context.close();
}
await browser.close();
fs.writeFileSync(
  path.resolve(OUT, '../EVIDENCE.json'),
  JSON.stringify({ base, shots, at: new Date().toISOString() }, null, 2),
);
console.log(
  JSON.stringify(
    {
      shots: shots.length,
      ok: shots.filter((s) => s.ok).length,
      detail: shots.map((s) => ({
        name: s.name,
        bytes: s.bytes,
        ok: s.ok,
      })),
    },
    null,
    2,
  ),
);
process.exit(shots.every((s) => s.ok) ? 0 : 2);
