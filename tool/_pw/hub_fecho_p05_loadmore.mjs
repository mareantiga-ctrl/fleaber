import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(__dirname, '../..');
const shots = path.join(repo, '06-fecho-final-paginas-05-06/SCREENSHOTS');
const evidence = path.join(repo, '06-fecho-final-paginas-05-06/EVIDENCE');
const BASE = 'http://127.0.0.1:8799';

async function settle(page) {
  await page.waitForSelector('flt-glass-pane, canvas, flutter-view', {
    timeout: 90000,
  });
  await page.waitForTimeout(4500);
  const b = page.locator('text=Aceitar').first();
  if (await b.count()) await b.click({ force: true }).catch(() => {});
  await page
    .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
    .catch(() => {});
  await page.waitForTimeout(700);
}

function parse(json) {
  const rows = Array.isArray(json?.items) ? json.items : [];
  return rows.map((r) => ({
    id: String(r.id),
    stars: Number(r.stars),
    created_at: r.created_at,
  }));
}

function sorted(items, sort) {
  for (let i = 1; i < items.length; i++) {
    const a = items[i - 1];
    const b = items[i];
    const da = Date.parse(a.created_at);
    const db = Date.parse(b.created_at);
    const sa = a.stars;
    const sb = b.stars;
    if (sort === 'newest' && db !== da && !(db < da)) return false;
    if (sort === 'oldest' && db !== da && !(db > da)) return false;
    if (sort === 'highest') {
      if (sb !== sa) {
        if (!(sb < sa)) return false;
      } else if (db !== da && !(db < da)) return false;
    }
    if (sort === 'lowest') {
      if (sb !== sa) {
        if (!(sb > sa)) return false;
      } else if (db !== da && !(db < da)) return false;
    }
  }
  return true;
}

async function clickLabel(page, label) {
  await page
    .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
    .catch(() => {});
  await page.waitForTimeout(400);
  const chip = page.getByText(label, { exact: true });
  const n = await chip.count();
  if (!n) return false;
  await chip.first().click({ force: true });
  return true;
}

async function clickVerMais(page) {
  await page
    .evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
    .catch(() => {});
  await page.waitForTimeout(300);
  // Prefer semantics text; also try scrolling the list area
  for (let i = 0; i < 6; i++) {
    const btn = page.getByText('Ver mais avaliações', { exact: true });
    if (await btn.count()) {
      await btn.first().click({ force: true });
      return true;
    }
    await page.mouse.wheel(0, 900);
    await page.waitForTimeout(350);
  }
  return false;
}

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const bySort = {};
page.on('response', async (res) => {
  if (
    res.request().method() !== 'POST' ||
    !res.url().includes('batata_hub_reviews_public_page')
  ) {
    return;
  }
  let sort = null;
  try {
    sort = res.request().postDataJSON()?.p_sort;
  } catch (_) {}
  try {
    const json = await res.json();
    if (!bySort[sort]) bySort[sort] = [];
    bySort[sort].push(parse(json));
  } catch (_) {}
});

await page.goto(`${BASE}/fleahub-demo-ux/reviews`, {
  waitUntil: 'networkidle',
  timeout: 120000,
});
await settle(page);

const sorts = [
  ['newest', 'Mais recentes'],
  ['oldest', 'Mais antigas'],
  ['highest', 'Melhor nota'],
  ['lowest', 'Pior nota'],
];
const out = [];

for (const [key, label] of sorts) {
  // Fresh navigation avoids semantics drift after scroll
  await page.goto(`${BASE}/fleahub-demo-ux/reviews`, {
    waitUntil: 'networkidle',
    timeout: 120000,
  });
  await settle(page);
  const before = (bySort[key] || []).length;
  const clicked = await clickLabel(page, label);
  await page.waitForTimeout(2800);
  const more = await clickVerMais(page);
  await page.waitForTimeout(3200);
  const pages = (bySort[key] || []).slice(before);
  const items = pages.flatMap((p) => p);
  const ids = items.map((i) => i.id);
  const dup = [...new Set(ids.filter((id, i) => ids.indexOf(id) !== i))];
  await page.screenshot({
    path: path.join(shots, `p05_sort_${key}_loadmore_1440.png`),
    fullPage: false,
  });
  const row = {
    sort: key,
    label,
    chipClicked: clicked,
    moreClicked: more,
    rpcPages: pages.length,
    itemCount: items.length,
    orderOk: items.length ? sorted(items, key) : false,
    duplicates: dup,
    first3: items.slice(0, 3),
    mid: items.slice(9, 12),
    pass: false,
  };
  row.pass =
    clicked &&
    pages.length >= 2 &&
    items.length >= 11 &&
    row.orderOk &&
    dup.length === 0;
  out.push(row);
  console.log(
    key,
    'pass',
    row.pass,
    'pages',
    row.rpcPages,
    'items',
    row.itemCount,
    'more',
    more,
  );
}

await browser.close();
const report = {
  id: 'p05_sort_loadmore',
  pass: out.every((r) => r.pass),
  out,
};
fs.writeFileSync(
  path.join(evidence, 'P05_LOADMORE_SORT.json'),
  JSON.stringify(report, null, 2),
);
console.log('OVERALL', report.pass);
