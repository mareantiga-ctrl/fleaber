import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve('tool/reports/hub_e21/p02');
fs.mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({ headless: true });
const page = await (
  await browser.newContext({ viewport: { width: 1280, height: 800 } })
).newPage();

const urls = [
  ['mariana_prod', 'https://fleaber.pt/fleahub/index.html#/mariana-prod'],
  ['vendedora_prod', 'https://fleaber.pt/fleahub/index.html#/vendedora-prod'],
];

const shots = [];
for (const [name, url] of urls) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 90000 });
  await page.waitForTimeout(7000);
  const file = path.join(OUT, `${name}_d1280.png`);
  await page.screenshot({ path: file, fullPage: false });
  shots.push({ name, url, file });
}

fs.writeFileSync(
  path.join(OUT, 'CAPTURES.json'),
  JSON.stringify({ generated_at: new Date().toISOString(), shots }, null, 2),
);
await browser.close();
console.log('p02_shots', shots.length);
