import { chromium } from 'playwright';
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const hosts = new Set();
page.on('request', r => { try { const u=new URL(r.url()); if(u.hostname.includes('supabase')) hosts.add(u.hostname); } catch{} });
await page.goto('http://127.0.0.1:8799/vendedora-prod/shop', { waitUntil: 'domcontentloaded' });
for (let i=0;i<45;i++){
  await page.waitForTimeout(1000);
  const t = await page.title();
  console.log(i, t, page.url());
  if (t.includes('Marketplace') || t.includes('encontrada')) break;
}
await page.screenshot({ path: '../../04-marketplace-density-study/SCREENSHOTS/COMPACT/diag_1440.png' });
console.log('hosts', [...hosts]);
await browser.close();
