#!/usr/bin/env python3
"""
ZIP 178 — Importador Amazon autónomo (584 ASIN).

- Correr via: powershell -File tool/run_amazon_autonomous_178.ps1
- Não publica Marketplace · não cria Moloni · não altera stock/docs
- Progresso em ficheiros; retoma sem repetir ASIN concluídos
- CAPTCHA → regista bloqueado e continua (sem contornar)
- Ollama local para PT-PT (sem APIs pagas / sem tokens Cursor)
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import secrets
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

TOOL = Path(__file__).resolve().parent
ROOT = TOOL.parent
OUT = ROOT / "tool/reports/amazon_importer_phase1/enrich_178"
PHOTO_DIR = OUT / "photos"
PROGRESS = OUT / "progress.json"
STATUS = OUT / "status.json"
JOURNAL = OUT / "journal.jsonl"
BLOCKED = OUT / "blocked.jsonl"
WORKER_LOG = OUT / "worker.log"
MANIFEST = (
    ROOT / "tool/reports/_zip152_amazon_importer_phase1/reports/manifest_source.csv"
)
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from amazon_importer_image_dedupe import dedupe_photo_dicts  # noqa: E402
import amazon_importer_local_enrich as _enrich  # noqa: E402
from amazon_importer_local_enrich import (  # noqa: E402
    apply_glossary,
    fetch_cdn,
    generate_copy,
    is_jpeg,
    validate_copy,
)

# Fotos/cache locais neste ZIP; modelo Ollama detectado em runtime.
_enrich.PHOTO_DIR = PHOTO_DIR
_enrich.OUT = OUT
OUT.mkdir(parents=True, exist_ok=True)
PHOTO_DIR.mkdir(parents=True, exist_ok=True)
PROJECT = "bpmpkzwnrbmuqnhgdscf"
MARKETS = ("es", "it", "de", "fr")
HOST = {
    "es": "https://www.amazon.es/dp/{asin}",
    "it": "https://www.amazon.it/dp/{asin}",
    "de": "https://www.amazon.de/dp/{asin}",
    "fr": "https://www.amazon.fr/dp/{asin}",
}
THROTTLE_S = 1.2
RETRY_MAX = 2
CAPTCHA_RE = re.compile(
    r"captcha|robot\s*check|validateCaptcha|opfcaptcha|enter the characters",
    re.I,
)
UNAVAILABLE_RE = re.compile(
    r"currently unavailable|no disponible|non disponibile|nicht verfügbar|indisponible",
    re.I,
)

PS_TOKEN = r"""
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class CredManAmz178 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("advapi32")] public static extern void CredFree(IntPtr cred);
  public static string Read(string target) { IntPtr p; if (!CredRead(target, 1, 0, out p)) return null; var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL)); byte[] b = new byte[c.CredentialBlobSize]; Marshal.Copy(c.CredentialBlob, b, 0, c.CredentialBlobSize); CredFree(p); return Encoding.UTF8.GetString(b); }
}
'@
Write-Output ([CredManAmz178]::Read('Supabase CLI:supabase'))
"""

_tok_cache: str | None = None
_tok_at = 0.0


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def log(msg: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    line = f"[{utc_now()}] {msg}"
    print(line, flush=True)
    with WORKER_LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def journal(event: str, **kw) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    row = {"ts": utc_now(), "event": event, **kw}
    with JOURNAL.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False, default=str) + "\n")


def append_blocked(asin: str, reason: str, **extra) -> None:
    with BLOCKED.open("a", encoding="utf-8") as f:
        f.write(
            json.dumps(
                {"ts": utc_now(), "asin": asin, "reason": reason, **extra},
                ensure_ascii=False,
            )
            + "\n"
        )


def mgmt_token() -> str:
    global _tok_cache, _tok_at
    if _tok_cache and time.time() - _tok_at < 1500:
        return _tok_cache
    t = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_TOKEN], text=True
    ).strip()
    if not t:
        raise SystemExit("CredMan token em falta")
    _tok_cache, _tok_at = t, time.time()
    return t


def run_sql(q: str):
    tok = mgmt_token()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT}/database/query",
        data=json.dumps({"query": q}).encode(),
        headers={
            "Authorization": f"Bearer {tok}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode(errors="replace")[:1200]) from e


def dollar_quote(s: str | None) -> str:
    if s is None:
        return "NULL"
    tag = "a" + secrets.token_hex(8)
    return f"${tag}${s}${tag}$"


def load_progress() -> dict:
    if PROGRESS.exists():
        return json.loads(PROGRESS.read_text(encoding="utf-8"))
    return {
        "done": {},
        "stats": {
            "ok": 0,
            "error": 0,
            "blocked": 0,
            "skipped_existing_ok": 0,
        },
        "meta": {"zip": "178-C2", "cursor_tokens": False, "moloni_writes": False, "publish": False},
    }


def save_progress(p: dict) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    PROGRESS.write_text(json.dumps(p, indent=2, ensure_ascii=False), encoding="utf-8")


def write_status(**kw) -> None:
    base = {
        "updated_at": utc_now(),
        "cursor_tokens_consumed_during_run": False,
        "marketplace_publish": False,
        "moloni_create": False,
    }
    base.update(kw)
    STATUS.write_text(json.dumps(base, indent=2, ensure_ascii=False), encoding="utf-8")


def load_manifest() -> tuple[list[dict], dict[str, list[dict]]]:
    with MANIFEST.open(encoding="utf-8", errors="replace", newline="") as f:
        rows = list(csv.DictReader(f))
    by_asin: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        a = (r.get("ASIN") or "").strip().upper()
        if not a:
            continue
        by_asin[a].append(r)
    return rows, by_asin


def http_html(url: str, timeout: int = 28) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept-Language": "pt-PT,pt;q=0.9,es;q=0.8",
            "Accept": "text/html,application/xhtml+xml",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def parse_price(html: str) -> float | None:
    if UNAVAILABLE_RE.search(html):
        return None
    for pat in (
        r'"priceAmount"\s*:\s*([0-9]+(?:\.[0-9]+)?)',
        r'class="a-price-whole">([0-9.]+)<[\s\S]{0,80}?a-price-fraction">([0-9]+)',
        r'id="priceblock_ourprice"[^>]*>\s*[^0-9]*([0-9]+[.,][0-9]{2})',
    ):
        m = re.search(pat, html)
        if not m:
            continue
        try:
            if m.lastindex and m.lastindex >= 2 and m.group(2):
                amt = float(f"{m.group(1).replace('.', '')}.{m.group(2)}")
            else:
                amt = float(m.group(1).replace(",", "."))
            if amt > 0:
                return amt
        except Exception:
            continue
    return None


def extract_title(html: str) -> str:
    m = re.search(r'id="productTitle"[^>]*>\s*([^<]+)', html)
    if m:
        return re.sub(r"\s+", " ", m.group(1)).strip()
    m = re.search(r'"title"\s*:\s*"([^"]{8,200})"', html)
    if m:
        return m.group(1).encode("utf-8").decode("unicode_escape", errors="ignore")
    return ""


def extract_image_urls(html: str) -> list[str]:
    urls: list[str] = []
    seen = set()
    for pat in (
        r'"hiRes"\s*:\s*"(https://[^"]+)"',
        r'"large"\s*:\s*"(https://[^"]+)"',
        r'data-old-hires="(https://[^"]+)"',
        r'(https://m\.media-amazon\.com/images/I/[^"\s]+\.jpg)',
    ):
        for m in re.finditer(pat, html):
            u = m.group(1).replace("\\u002F", "/")
            if u in seen:
                continue
            seen.add(u)
            urls.append(u)
            if len(urls) >= 16:
                return urls
    return urls


def probe_prices(asin: str) -> dict:
    markets: dict[str, dict] = {}
    valid_prices: list[float] = []
    ref = None
    captcha_markets = []
    for code in MARKETS:
        attempt = 0
        while attempt <= RETRY_MAX:
            attempt += 1
            try:
                html = http_html(HOST[code].format(asin=asin))
            except Exception as e:
                markets[code] = {"status": "error", "error": str(e)[:120]}
                time.sleep(THROTTLE_S)
                break
            if CAPTCHA_RE.search(html):
                markets[code] = {"status": "captcha"}
                captcha_markets.append(code)
                time.sleep(THROTTLE_S + 0.5)
                break
            amt = parse_price(html)
            title = extract_title(html)
            if amt:
                markets[code] = {
                    "status": "ok",
                    "price_amount": amt,
                    "currency": "EUR",
                    "title": title[:240],
                    "availability": "ok",
                }
                valid_prices.append(amt)
                if ref is None:
                    ref = {"marketplace": code, "price_amount": amt, "title": title}
            else:
                markets[code] = {
                    "status": "not_found",
                    "title": title[:240] if title else None,
                }
            time.sleep(THROTTLE_S)
            break
    spread = False
    if len(valid_prices) >= 2:
        valid_prices.sort()
        spread = valid_prices[-1] / max(valid_prices[0], 0.01) > 2.5
    suggested = None
    if ref and not spread:
        suggested = round(float(ref["price_amount"]) * 0.5, 2)
    return {
        "markets": markets,
        "reference": ref,
        "suggested_sale_eur": suggested,
        "por_confirmar": spread,
        "captcha_markets": captcha_markets,
        "source_title": (ref or {}).get("title") or "",
    }


def collect_photos_html(asin: str) -> list[dict]:
    photos = fetch_cdn(asin)
    if len(photos) >= 2:
        return dedupe_photo_dicts(photos)
    for code in MARKETS:
        try:
            html = http_html(HOST[code].format(asin=asin))
        except Exception:
            time.sleep(THROTTLE_S)
            continue
        if CAPTCHA_RE.search(html):
            append_blocked(asin, "captcha_photos", market=code)
            time.sleep(THROTTLE_S)
            continue
        urls = extract_image_urls(html)
        seen = {p.get("md5") for p in photos}
        for url in urls:
            try:
                data = urllib.request.urlopen(
                    urllib.request.Request(
                        url,
                        headers={"User-Agent": "Mozilla/5.0"},
                    ),
                    timeout=30,
                ).read()
            except Exception:
                continue
            if not is_jpeg(data):
                continue
            h = hashlib.md5(data).hexdigest()
            if h in seen:
                continue
            seen.add(h)
            path = PHOTO_DIR / f"{asin}_html_{h[:8]}.jpg"
            path.write_bytes(data)
            photos.append(
                {
                    "url": url,
                    "bytes": len(data),
                    "md5": h,
                    "local": str(path),
                    "source": "amazon_dp_html",
                }
            )
            if len(photos) >= 8:
                break
        time.sleep(THROTTLE_S)
        if len(photos) >= 2:
            break
    return dedupe_photo_dicts(photos)


def product_first_title(source: str, brand: str, llm_title: str) -> str:
    t = apply_glossary((llm_title or "").strip())
    if not t:
        t = apply_glossary(source)[:90]
    # Se o título começa pela marca e há resto, inverter quando possível
    b = (brand or "").strip()
    if b and t.lower().startswith(b.lower()):
        rest = t[len(b) :].lstrip(" -—,|:").strip()
        if len(rest) >= 8:
            t = f"{rest} {b}"
    return t[:100]


def ensure_lot() -> str:
    """Lote privado ZIP178 para associações LPN (não publica)."""
    marker = OUT / "lot_id.txt"
    if marker.exists():
        lid = marker.read_text(encoding="utf-8").strip()
        if lid:
            rows = run_sql(
                f"select id::text as id from amazon_import_lots where id='{lid}'::uuid"
            )
            if rows:
                return lid
    rows = run_sql(
        """
insert into amazon_import_lots (
  created_by, source_filename, status, row_count, distinct_asin_count,
  default_discount_pct, notes, meta, pause_requested, cursor_row
) values (
  '08c9dca8-3707-4ee5-9f43-b33293085d6a',
  'manifest_source.csv',
  'importing',
  625,
  584,
  50,
  'ZIP178 autonomous prep — sem publish',
  '{"zip":"178-C2","autonomous":true,"publish":false}'::jsonb,
  false,
  0
)
returning id::text as id
"""
    )
    lid = rows[0]["id"]
    marker.write_text(lid, encoding="utf-8")
    return lid


def pick_ollama_model() -> str:
    preferred = ["qwen2.5:7b", "qwen3:8b", "qwen2.5:14b", "llama3.1:8b"]
    try:
        with urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=5) as r:
            data = json.loads(r.read().decode())
        names = [m.get("name") for m in data.get("models") or [] if m.get("name")]
        for p in preferred:
            if p in names:
                _enrich.MODEL = p
                return p
        if names:
            _enrich.MODEL = names[0]
            return names[0]
    except Exception as e:
        log(f"ollama tags falhou: {e}")
    return _enrich.MODEL


def ensure_catalog_product(asin: str, manifest_title: str) -> str:
    rows = run_sql(
        f"""
insert into amazon_catalog_products (asin, title, catalog_status, discount_pct)
values ({dollar_quote(asin)}, {dollar_quote((manifest_title or '')[:200])}, 'imported', 50)
on conflict (asin) do update set
  updated_at = timezone('utc', now()),
  title = coalesce(nullif(amazon_catalog_products.title,''), excluded.title)
returning id::text as id
"""
    )
    return rows[0]["id"]


def _num_sql(raw) -> str:
    if raw is None or str(raw).strip() == "":
        return "NULL"
    try:
        return str(float(str(raw).strip().replace(",", ".")))
    except Exception:
        return "NULL"


def ensure_units(lot_id: str, product_id: str, asin: str, units: list[dict]) -> dict:
    imported = 0
    skipped_empty = 0
    duplicates = 0
    for u in units:
        lpn = (u.get("LPN") or "").strip()
        if not lpn:
            skipped_empty += 1
            continue
        exists = run_sql(
            f"select id from amazon_catalog_units where lpn={dollar_quote(lpn)} limit 1"
        )
        if exists:
            duplicates += 1
            continue
        qty = 1
        try:
            qty = max(1, int(float(str(u.get("QTY") or "1").replace(",", "."))))
        except Exception:
            qty = 1
        raw = {k: u.get(k) for k in ("ASIN", "LPN", "CONDITION", "QTY", "COST", "Item Desc")}
        run_sql(
            f"""
insert into amazon_catalog_units (
  lot_id, product_id, asin, lpn, condition_code, condition_label, qty,
  manifesto_cost_eur, manifesto_retail_eur, manifesto_currency,
  sku_fc, fnsku, package_weight, package_weight_uom, raw_row
) values (
  '{lot_id}'::uuid,
  '{product_id}'::uuid,
  {dollar_quote(asin)},
  {dollar_quote(lpn)},
  {dollar_quote((u.get('CONDITION') or '')[:80])},
  'Novo',
  {qty},
  {_num_sql(u.get('COST'))},
  {_num_sql(u.get('UNIT RETAIL') or u.get('TOTAL RETAIL'))},
  {dollar_quote((u.get('CURRENCY CODE') or 'EUR')[:8])},
  {dollar_quote((u.get('FCSku') or None))},
  {dollar_quote((u.get('FNSku') or None))},
  {_num_sql(u.get('ItemPkgWeight'))},
  {dollar_quote((u.get('ItemPkgWeightUOM') or None))},
  {dollar_quote(json.dumps(raw, ensure_ascii=False))}::jsonb
)
"""
        )
        imported += 1
    return {
        "imported": imported,
        "duplicates": duplicates,
        "skipped_empty_lpn": skipped_empty,
    }


def upsert_offers(product_id: str, asin: str, price_info: dict) -> None:
    for code, m in (price_info.get("markets") or {}).items():
        status = m.get("status") or "error"
        amt = m.get("price_amount")
        title = m.get("title")
        avail = m.get("availability")
        run_sql(
            f"""
insert into amazon_market_offers (
  product_id, asin, marketplace, status, price_amount, currency,
  title, availability, source_url, fetched_at
) values (
  '{product_id}'::uuid,
  {dollar_quote(asin)},
  {dollar_quote(code)},
  {dollar_quote(status)},
  {('null' if amt is None else str(float(amt)))},
  'EUR',
  {dollar_quote(title)},
  {dollar_quote(avail)},
  {dollar_quote(HOST[code].format(asin=asin))},
  timezone('utc', now())
)
"""
        )


def enrich_write(
    asin: str,
    title: str,
    description: str,
    title_original: str,
    model: str,
    copy_status: str,
    suggested,
    photos: list[dict],
) -> str | None:
    https_photos = [p for p in photos if str(p.get("url", "")).startswith("https://")]
    photos_json = json.dumps(
        [{"url": p["url"], "source": p.get("source") or "amazon_dp_html"} for p in https_photos],
        ensure_ascii=False,
    )
    sug_sql = "NULL" if suggested is None else str(float(suggested))
    rows = run_sql(
        "select public.batata_amazon_enrich_write("
        f"{dollar_quote(asin)}, "
        f"{dollar_quote(title)}, "
        f"{dollar_quote(description)}, "
        f"{dollar_quote(title_original)}, "
        f"{dollar_quote(model)}, "
        f"{dollar_quote(copy_status)}, "
        f"{sug_sql}::numeric, "
        f"{dollar_quote(photos_json)}::jsonb"
        ") as id;"
    )
    if isinstance(rows, list) and rows:
        return rows[0].get("id")
    return None


def process_asin(asin: str, units: list[dict], progress: dict, lot_id: str) -> dict:
    asin = asin.upper()
    if asin in progress.get("done", {}) and progress["done"][asin].get("status") in (
        "ok",
        "needs_review",
        "blocked_no_lpn_only",
    ):
        # already finished
        return progress["done"][asin]

    manifest_title = (units[0].get("Item Desc") or "").strip() if units else ""
    lpns = [(u.get("LPN") or "").strip() for u in units]
    if asin == "B0FS2FB69P" or (units and all(not x for x in lpns)):
        # special: empty LPN — still enrich product if possible, but flag
        append_blocked(asin, "missing_lpn", units=len(units))

    result = {
        "asin": asin,
        "started_at": utc_now(),
        "status": "error",
        "sale_condition": "Novo",
    }
    try:
        product_id = ensure_catalog_product(asin, manifest_title)
        result["product_id"] = product_id
        result["units"] = ensure_units(lot_id, product_id, asin, units)

        price_info = probe_prices(asin)
        result["price"] = {
            "reference": price_info.get("reference"),
            "suggested_sale_eur": price_info.get("suggested_sale_eur"),
            "por_confirmar": price_info.get("por_confirmar"),
            "captcha_markets": price_info.get("captcha_markets"),
            "markets_ok": [
                k
                for k, v in (price_info.get("markets") or {}).items()
                if v.get("status") == "ok"
            ],
        }
        upsert_offers(product_id, asin, price_info)

        photos = collect_photos_html(asin)
        result["photos_n"] = len(photos)
        result["photos_https"] = sum(
            1 for p in photos if str(p.get("url", "")).startswith("https://")
        )

        source = (
            price_info.get("source_title")
            or manifest_title
            or asin
        )
        llm = generate_copy(source, asin)
        brand = (source.split() or [""])[0]
        title = product_first_title(source, brand, llm.get("title") or "")
        desc = apply_glossary(llm.get("description") or "")
        # força menção Características se validação exigir
        if "caracter" not in desc.lower():
            desc = (desc + "\nCaracterísticas: conforme ficha do fabricante.").strip()
        ok_copy, issues = validate_copy(
            title=title,
            description=desc,
            source=source,
            asin=asin,
            hint=llm.get("hint") or "",
        )
        copy_status = "pass" if ok_copy else "revision_needed"
        if price_info.get("por_confirmar"):
            issues = list(issues) + ["preco_por_confirmar"]
            copy_status = "revision_needed"
        if result["photos_https"] < 1:
            issues = list(issues) + ["fotos_insuficientes"]
            copy_status = "revision_needed"

        suggested = price_info.get("suggested_sale_eur")
        enrich_id = enrich_write(
            asin=asin,
            title=title,
            description=desc,
            title_original=source[:500],
            model=str(llm.get("model") or llm.get("hint") or "ollama/local"),
            copy_status=copy_status,
            suggested=suggested,
            photos=photos,
        )
        # mark price confirm flag in prep_notes
        if price_info.get("por_confirmar") or issues:
            note = "ZIP178; Novo; " + "; ".join(issues[:8])
            run_sql(
                f"""
update amazon_catalog_products
set prep_notes = {dollar_quote(note)},
    catalog_status = case
      when {dollar_quote(copy_status)} = 'pass' then 'prepared'
      else 'needs_review'
    end,
    updated_at = timezone('utc', now())
where asin = {dollar_quote(asin)}
"""
            )

        result.update(
            {
                "status": "ok" if copy_status == "pass" else "needs_review",
                "title": title,
                "copy_status": copy_status,
                "issues": issues,
                "enrich_id": enrich_id,
                "finished_at": utc_now(),
            }
        )
        if asin == "B0FS2FB69P":
            result["status"] = "blocked_no_lpn_only"
            result["note"] = "ASIN processado sem inventar LPN"
        journal("asin_done", **{k: result[k] for k in result if k != "title"})
        return result
    except Exception as e:
        result["error"] = str(e)[:400]
        result["trace"] = traceback.format_exc()[-600:]
        result["finished_at"] = utc_now()
        append_blocked(asin, "exception", error=str(e)[:200])
        journal("asin_error", asin=asin, error=str(e)[:200])
        return result


def pick_pilot(by_asin: dict[str, list[dict]], existing: set[str]) -> list[str]:
    """5 ASIN representativos: 2 já no catálogo + 3 novos; inclui multi-LPN se possível."""
    multi = [a for a, us in by_asin.items() if len(us) > 1]
    single = [a for a, us in by_asin.items() if len(us) == 1]
    chosen: list[str] = []
    for a in existing:
        if a in by_asin and a not in chosen:
            chosen.append(a)
        if len(chosen) >= 2:
            break
    for pool in (multi, single):
        for a in pool:
            if a in chosen or a == "B0FS2FB69P":
                continue
            if a in existing and len([x for x in chosen if x in existing]) >= 2:
                continue
            chosen.append(a)
            if len(chosen) >= 5:
                break
        if len(chosen) >= 5:
            break
    return chosen[:5]


def run_batch(asins: list[str], by_asin: dict[str, list[dict]], *, label: str) -> dict:
    progress = load_progress()
    lot_id = ensure_lot()
    progress["lot_id"] = lot_id
    model = pick_ollama_model()
    progress["ollama_model"] = model
    save_progress(progress)
    log(f"lot_id={lot_id} ollama_model={model}")
    write_status(
        state="running",
        label=label,
        total=len(asins),
        done=len(progress.get("done", {})),
        lot_id=lot_id,
        ollama_model=model,
    )
    for i, asin in enumerate(asins, 1):
        prev = progress.get("done", {}).get(asin)
        if prev and prev.get("status") in ("ok", "needs_review", "blocked_no_lpn_only"):
            log(f"[{i}/{len(asins)}] {asin} SKIP done={prev.get('status')}")
            continue
        log(f"[{i}/{len(asins)}] {asin} …")
        row = process_asin(asin, by_asin.get(asin, []), progress, lot_id)
        progress.setdefault("done", {})[asin] = row
        st = row.get("status")
        if st == "ok":
            progress["stats"]["ok"] = progress["stats"].get("ok", 0) + 1
        elif st == "needs_review":
            progress["stats"]["needs_review"] = progress["stats"].get("needs_review", 0) + 1
        elif str(st).startswith("blocked"):
            progress["stats"]["blocked"] = progress["stats"].get("blocked", 0) + 1
        else:
            progress["stats"]["error"] = progress["stats"].get("error", 0) + 1
        save_progress(progress)
        write_status(
            state="running",
            label=label,
            total=len(asins),
            index=i,
            last_asin=asin,
            last_status=st,
            stats=progress["stats"],
            done_count=len(progress["done"]),
        )
    return progress


def main() -> int:
    ap = argparse.ArgumentParser(description="Amazon autonomous importer ZIP 178")
    ap.add_argument("--pilot", action="store_true", help="Só prova 5 ASIN")
    ap.add_argument("--full", action="store_true", help="Lote completo (após pilot PASS)")
    ap.add_argument("--resume", action="store_true", help="Retomar full a partir de progress")
    ap.add_argument("--asins", nargs="*", help="Lista explícita de ASIN")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    PHOTO_DIR.mkdir(parents=True, exist_ok=True)

    rows, by_asin = load_manifest()
    log(f"manifest rows={len(rows)} asins={len(by_asin)}")

    existing_rows = run_sql("select asin from amazon_catalog_products")
    existing = {r["asin"] for r in existing_rows if r.get("asin")}

    if args.asins:
        target = [a.upper() for a in args.asins]
        label = "custom"
    elif args.pilot:
        target = pick_pilot(by_asin, existing)
        label = "pilot5"
        log(f"pilot asins={target}")
    elif args.full or args.resume:
        # all asins from manifesto; B0FS2FB69P included but flagged
        target = sorted(by_asin.keys())
        label = "full584"
    else:
        ap.print_help()
        return 2

    write_status(state="starting", label=label, total=len(target))
    journal("run_start", label=label, n=len(target), cursor_tokens=False)

    progress = run_batch(target, by_asin, label=label)

    # summarize
    done = progress.get("done", {})
    summary = {
        "label": label,
        "target": len(target),
        "completed": len(done),
        "ok": sum(1 for v in done.values() if v.get("status") == "ok"),
        "needs_review": sum(1 for v in done.values() if v.get("status") == "needs_review"),
        "blocked": sum(1 for v in done.values() if str(v.get("status", "")).startswith("blocked")),
        "error": sum(1 for v in done.values() if v.get("status") == "error"),
        "pending": len(target) - len(done),
        "cursor_tokens": False,
        "publish": False,
        "moloni_create": False,
    }
    (OUT / f"summary_{label}.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    if label == "pilot5":
        # PASS if >=3 of 5 finished without hard error (ok or needs_review)
        good = summary["ok"] + summary["needs_review"]
        pilot_pass = good >= 3 and summary["error"] <= 2
        pilot = {
            "PASS": pilot_pass,
            "summary": summary,
            "asins": {a: done.get(a, {}).get("status") for a in target},
            "note": "needs_review conta como processado (revisão humana posterior)",
        }
        (OUT / "PILOT_RESULT.json").write_text(
            json.dumps(pilot, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        write_status(state="pilot_done", PASS=pilot_pass, summary=summary)
        journal("pilot_done", **pilot)
        log(f"PILOT PASS={pilot_pass} summary={summary}")
        return 0 if pilot_pass else 1

    write_status(state="completed", summary=summary)
    journal("run_done", **summary)
    log(f"FULL done summary={summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
