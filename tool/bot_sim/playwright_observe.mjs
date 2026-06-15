#!/usr/bin/env node
/**
 * Opcional: observar UI da live com Playwright (1 browser).
 * Requer: npm i -D playwright && npx playwright install chromium
 *
 *   node tool/bot_sim/playwright_observe.mjs --url "https://staging.fleaber.app/live/UUID"
 */
import { chromium } from 'playwright';

const args = process.argv.slice(2);
const urlIdx = args.indexOf('--url');
const url = urlIdx >= 0 ? args[urlIdx + 1] : null;
const durationMin = parseInt(args[args.indexOf('--minutes') + 1] || '10', 10);

if (!url) {
  console.error('Uso: node tool/bot_sim/playwright_observe.mjs --url <live_url> [--minutes 10]');
  process.exit(1);
}

const browser = await chromium.launch({ headless: false });
const page = await browser.newPage();
await page.goto(url, { waitUntil: 'domcontentloaded' });
console.log(`A observar ${url} por ${durationMin} min…`);
await page.waitForTimeout(durationMin * 60 * 1000);
await browser.close();
