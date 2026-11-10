import { chromium } from 'playwright';
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const hosts = new Set();
page.on('request', (r) => {
  try {
    const u = new URL(r.url());
    if (u.hostname.includes('supabase')) hosts.add(u.hostname);
  } catch (_) {}
});
await page.goto('http://127.0.0.1:8798/vendedora-prod/shop', { waitUntil: 'domcontentloaded', timeout: 120000 });
for (let i = 0; i < 60; i++) {
  await page.waitForTimeout(1000);
  const t = await page.title();
  const text = await page.innerText('body').catch(() => '');
  if (t.includes('Marketplace') || text.includes('TESTE') || (t.includes('encontrada') && i > 20)) break;
}
console.log(JSON.stringify({ title: await page.title(), hosts: [...hosts], url: page.url() }, null, 2));
await browser.close();
