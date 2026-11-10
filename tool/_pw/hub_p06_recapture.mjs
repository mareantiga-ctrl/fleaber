import { chromium } from 'playwright';
import path from 'path';
import { fileURLToPath } from 'url';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const shots = path.resolve(__dirname, '../../06-not-found-implementacao-e-auditoria/SCREENSHOTS');
const browser = await chromium.launch({ headless: true });
const results = [];
for (const w of [390,768,1280,1440,1920]) {
  const page = await browser.newPage({ viewport: { width: w, height: w < 768 ? 844 : 900 } });
  await page.goto('http://127.0.0.1:8799/this-handle-does-not-exist-xyz-404', { waitUntil: 'networkidle', timeout: 120000 });
  await page.waitForTimeout(4500);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()).catch(()=>{});
  const aceitar = page.locator('text=Aceitar').first();
  if (await aceitar.count()) await aceitar.click({ force: true }).catch(()=>{});
  await page.waitForTimeout(600);
  await page.screenshot({ path: path.join(shots, 'p06_404_'+w+'.png'), fullPage: false });
  const body = await page.evaluate(() => document.body?.innerText || '');
  results.push({ w, incorreto: body.includes('incorreto'), incorrecto: body.includes('incorrecto'), cta: body.includes('Ir para o início'), headline: body.includes('Esta página não existe') });
  console.log(JSON.stringify(results.at(-1)));
  await page.close();
}
await browser.close();
