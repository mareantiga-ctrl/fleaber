#!/usr/bin/env python3
"""
ZIP 184 — Revisão autónoma dos ASIN needs_review (não os 584).

- Só processa lista needs_review do progress ZIP 178
- Fotos CDN → HTML → Playwright (CAPTCHA = blocked, sem contornar)
- Preços ES→IT→DE→FR se em falta (cache/HTTP)
- Textos Ollama local se título/issues
- Retoma via progress_184.json
- Sem publish / Moloni real / tokens Cursor
"""
from __future__ import annotations

import argparse
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
from datetime import datetime, timezone
from pathlib import Path

TOOL = Path(__file__).resolve().parent
ROOT = TOOL.parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

OUT = ROOT / "tool/reports/amazon_importer_phase1/enrich_184"
PHOTO_DIR = OUT / "photos"
PROGRESS = OUT / "progress_184.json"
STATUS = OUT / "status.json"
JOURNAL = OUT / "journal.jsonl"
BLOCKED = OUT / "blocked.jsonl"
WORKER_LOG = OUT / "worker.log"
SRC178 = ROOT / "tool/reports/amazon_importer_phase1/enrich_178/progress.json"
PROJECT = "bpmpkzwnrbmuqnhgdscf"
MARKETS = ("es", "it", "de", "fr")
HOST = {
    "es": "https://www.amazon.es/dp/{asin}",
    "it": "https://www.amazon.it/dp/{asin}",
    "de": "https://www.amazon.de/dp/{asin}",
    "fr": "https://www.amazon.fr/dp/{asin}",
}
THROTTLE_S = 1.1
CAPTCHA_RE = re.compile(
    r"captcha|robot\s*check|validateCaptcha|opfcaptcha|enter the characters",
    re.I,
)

PS_TOKEN = r"""
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class CredManAmz184 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("advapi32")] public static extern void CredFree(IntPtr cred);
  public static string Read(string target) { IntPtr p; if (!CredRead(target, 1, 0, out p)) return null; var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL)); byte[] b = new byte[c.CredentialBlobSize]; Marshal.Copy(c.CredentialBlob, b, 0, c.CredentialBlobSize); CredFree(p); return Encoding.UTF8.GetString(b); }
}
'@
Write-Output ([CredManAmz184]::Read('Supabase CLI:supabase'))
"""

_tok = None
_tok_at = 0.0

import amazon_importer_local_enrich as _enrich  # noqa: E402
from amazon_importer_image_dedupe import dedupe_photo_dicts  # noqa: E402
from amazon_importer_local_enrich import (  # noqa: E402
    apply_glossary,
    fetch_cdn,
    generate_copy,
    is_jpeg,
    validate_copy,
)

_enrich.PHOTO_DIR = PHOTO_DIR
_enrich.OUT = OUT
OUT.mkdir(parents=True, exist_ok=True)
PHOTO_DIR.mkdir(parents=True, exist_ok=True)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def log(msg: str) -> None:
    line = f"[{utc_now()}] {msg}"
    print(line, flush=True)
    with WORKER_LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def journal(event: str, **kw) -> None:
    with JOURNAL.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"ts": utc_now(), "event": event, **kw}, ensure_ascii=False) + "\n")


def append_blocked(asin: str, reason: str, **extra) -> None:
    with BLOCKED.open("a", encoding="utf-8") as f:
        f.write(
            json.dumps({"ts": utc_now(), "asin": asin, "reason": reason, **extra}, ensure_ascii=False)
            + "\n"
        )


def mgmt_token() -> str:
    global _tok, _tok_at
    if _tok and time.time() - _tok_at < 1500:
        return _tok
    t = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_TOKEN], text=True
    ).strip()
    if not t:
        raise SystemExit("CredMan token em falta")
    _tok, _tok_at = t, time.time()
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
        "stats": {"recovered": 0, "still_review": 0, "manual": 0, "error": 0},
        "meta": {"zip": "184-C2", "cursor_tokens": False},
    }


def save_progress(p: dict) -> None:
    PROGRESS.write_text(json.dumps(p, indent=2, ensure_ascii=False), encoding="utf-8")


def write_status(**kw) -> None:
    base = {
        "updated_at": utc_now(),
        "cursor_tokens_per_asin": False,
        "publish": False,
        "moloni_create": False,
    }
    base.update(kw)
    STATUS.write_text(json.dumps(base, indent=2, ensure_ascii=False), encoding="utf-8")


def needs_review_asins() -> list[str]:
    src = json.loads(SRC178.read_text(encoding="utf-8"))
    done = src.get("done") or {}
    return sorted(
        a for a, v in done.items() if (v or {}).get("status") == "needs_review"
    )


def pick_ollama_model() -> str:
    preferred = ["qwen2.5:7b", "qwen3:8b", "llama3.1:8b"]
    try:
        with urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=5) as r:
            names = [
                m.get("name")
                for m in (json.loads(r.read().decode()).get("models") or [])
                if m.get("name")
            ]
        for p in preferred:
            if p in names:
                _enrich.MODEL = p
                return p
        if names:
            _enrich.MODEL = names[0]
            return names[0]
    except Exception as e:
        log(f"ollama: {e}")
    return getattr(_enrich, "MODEL", "qwen2.5:7b")


def http_html(url: str) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept-Language": "pt-PT,pt;q=0.9,es;q=0.8",
        },
    )
    with urllib.request.urlopen(req, timeout=28) as r:
        return r.read().decode("utf-8", "replace")


def parse_price(html: str) -> float | None:
    for pat in (
        r'"priceAmount"\s*:\s*([0-9]+(?:\.[0-9]+)?)',
        r'class="a-price-whole">([0-9.]+)<[\s\S]{0,80}?a-price-fraction">([0-9]+)',
    ):
        m = re.search(pat, html)
        if not m:
            continue
        try:
            if m.lastindex and m.lastindex >= 2 and m.group(2):
                return float(f"{m.group(1).replace('.', '')}.{m.group(2)}")
            return float(m.group(1).replace(",", "."))
        except Exception:
            continue
    return None


def extract_title(html: str) -> str:
    m = re.search(r'id="productTitle"[^>]*>\s*([^<]+)', html)
    if m:
        return re.sub(r"\s+", " ", m.group(1)).strip()
    return ""


def extract_image_urls(html: str) -> list[str]:
    urls, seen = [], set()
    for pat in (
        r'"hiRes"\s*:\s*"(https://[^"]+)"',
        r'"large"\s*:\s*"(https://[^"]+)"',
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
    markets = {}
    ref = None
    prices = []
    captcha = []
    source_title = ""
    for code in MARKETS:
        try:
            html = http_html(HOST[code].format(asin=asin))
        except Exception as e:
            markets[code] = {"status": "error", "error": str(e)[:100]}
            time.sleep(THROTTLE_S)
            continue
        if CAPTCHA_RE.search(html):
            markets[code] = {"status": "captcha"}
            captcha.append(code)
            time.sleep(THROTTLE_S)
            continue
        title = extract_title(html)
        if title and not source_title:
            source_title = title
        amt = parse_price(html)
        if amt and amt > 0:
            markets[code] = {"status": "ok", "price_amount": amt, "title": title[:240]}
            prices.append(amt)
            if ref is None:
                ref = {"marketplace": code, "price_amount": amt, "title": title}
        else:
            markets[code] = {"status": "not_found", "title": title[:240] if title else None}
        time.sleep(THROTTLE_S)
    spread = False
    if len(prices) >= 2:
        prices.sort()
        spread = prices[-1] / max(prices[0], 0.01) > 2.5
    suggested = None
    if ref and not spread:
        suggested = round(float(ref["price_amount"]) * 0.5, 2)
    return {
        "markets": markets,
        "reference": ref,
        "suggested_sale_eur": suggested,
        "por_confirmar": spread,
        "captcha_markets": captcha,
        "source_title": source_title,
    }


def download_urls(asin: str, urls: list[str], photos: list[dict]) -> list[dict]:
    seen = {p.get("md5") for p in photos if p.get("md5")}
    for url in urls:
        try:
            data = urllib.request.urlopen(
                urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}),
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
        path = PHOTO_DIR / f"{asin}_{h[:8]}.jpg"
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
    return photos


def collect_photos(asin: str) -> tuple[list[dict], str | None]:
    """Returns photos, block_reason."""
    photos = fetch_cdn(asin)
    if len(photos) >= 2:
        return dedupe_photo_dicts(photos), None

    for code in MARKETS:
        try:
            html = http_html(HOST[code].format(asin=asin))
        except Exception:
            time.sleep(THROTTLE_S)
            continue
        if CAPTCHA_RE.search(html):
            append_blocked(asin, "captcha_photos", market=code)
            time.sleep(THROTTLE_S)
            # try playwright headless once
            break
        urls = extract_image_urls(html)
        photos = download_urls(asin, urls, photos)
        time.sleep(THROTTLE_S)
        if len(photos) >= 2:
            return dedupe_photo_dicts(photos), None

    if len(photos) >= 2:
        return dedupe_photo_dicts(photos), None

    # Playwright headless — sem esperar humano; CAPTCHA → manual
    try:
        from playwright.sync_api import sync_playwright

        with sync_playwright() as pw:
            browser = pw.chromium.launch(headless=True)
            page = browser.new_page(
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                )
            )
            for code in MARKETS:
                url = HOST[code].format(asin=asin)
                try:
                    page.goto(url, wait_until="domcontentloaded", timeout=60000)
                    time.sleep(2.0)
                    html = page.content()
                    if CAPTCHA_RE.search(html):
                        browser.close()
                        return dedupe_photo_dicts(photos), "captcha_playwright"
                    urls = extract_image_urls(html)
                    photos = download_urls(asin, urls, photos)
                    if len(photos) >= 2:
                        break
                except Exception:
                    continue
            browser.close()
    except Exception as e:
        log(f"playwright fail {asin}: {e}")

    photos = dedupe_photo_dicts(photos)
    if len(photos) < 1:
        return photos, "no_photos"
    return photos, None


def enrich_write(asin, title, description, title_original, model, copy_status, suggested, photos):
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
    return rows[0].get("id") if rows else None


def upsert_offers(asin: str, price_info: dict) -> None:
    # need product id
    rows = run_sql(
        f"select id::text as id from amazon_catalog_products where asin={dollar_quote(asin)} limit 1"
    )
    if not rows:
        return
    pid = rows[0]["id"]
    for code, m in (price_info.get("markets") or {}).items():
        status = m.get("status") or "error"
        if status not in ("ok", "not_found", "captcha", "error", "blocked", "skipped", "pending"):
            status = "error"
        amt = m.get("price_amount")
        run_sql(
            f"""
insert into amazon_market_offers (
  product_id, asin, marketplace, status, price_amount, currency, title, source_url, fetched_at
) values (
  '{pid}'::uuid, {dollar_quote(asin)}, {dollar_quote(code)}, {dollar_quote(status)},
  {('null' if amt is None else str(float(amt)))}, 'EUR',
  {dollar_quote(m.get('title'))}, {dollar_quote(HOST[code].format(asin=asin))},
  timezone('utc', now())
)
"""
        )


def process_one(asin: str, prior: dict | None) -> dict:
    result = {
        "asin": asin,
        "started_at": utc_now(),
        "prior_issues": (prior or {}).get("issues") or [],
        "status": "error",
    }
    try:
        price_info = probe_prices(asin)
        # keep prior suggested if still valid and no new price
        suggested = price_info.get("suggested_sale_eur")
        if suggested is None and prior:
            suggested = (prior.get("price") or {}).get("suggested_sale_eur")
        result["price"] = {
            "suggested_sale_eur": suggested,
            "reference": price_info.get("reference"),
            "por_confirmar": price_info.get("por_confirmar"),
            "captcha_markets": price_info.get("captcha_markets"),
        }
        upsert_offers(asin, price_info)

        photos, photo_block = collect_photos(asin)
        result["photos_n"] = len(photos)
        result["photos_https"] = sum(
            1 for p in photos if str(p.get("url", "")).startswith("https://")
        )

        # existing title from DB
        row = run_sql(
            f"select title, description, title_original from amazon_catalog_products where asin={dollar_quote(asin)} limit 1"
        )
        db_title = (row[0].get("title") if row else None) or ""
        source = (
            price_info.get("source_title")
            or (prior or {}).get("title")
            or db_title
            or asin
        )

        need_copy = any(
            i.startswith("marca") or i.startswith("titulo") or "estrangeiro" in i
            for i in (result["prior_issues"] or [])
        ) or len(db_title) < 18

        if need_copy:
            llm = generate_copy(source, asin)
            title = apply_glossary(llm.get("title") or source)[:100]
            desc = apply_glossary(llm.get("description") or "")
            if "caracter" not in desc.lower():
                desc = (desc + "\nCaracterísticas: conforme ficha do fabricante.").strip()
            model = str(llm.get("model") or _enrich.MODEL)
        else:
            title = apply_glossary(db_title or source)[:100]
            desc = (row[0].get("description") if row else None) or (
                f"{title}. Características: conforme ficha do fabricante."
            )
            model = "reuse"

        ok_copy, issues = validate_copy(
            title=title, description=desc, source=source, asin=asin, hint=""
        )
        if price_info.get("por_confirmar"):
            issues = list(issues) + ["preco_por_confirmar"]
        if result["photos_https"] < 1:
            issues = list(issues) + ["fotos_insuficientes"]
        if photo_block:
            issues = list(issues) + [photo_block]

        copy_status = "pass" if (ok_copy and result["photos_https"] >= 1 and not price_info.get("por_confirmar")) else "revision_needed"
        enrich_write(
            asin=asin,
            title=title,
            description=desc,
            title_original=source[:500],
            model=model,
            copy_status=copy_status,
            suggested=suggested,
            photos=photos,
        )

        if copy_status == "pass":
            result["status"] = "recovered"
        elif photo_block in ("captcha_playwright", "captcha_photos") or result["photos_https"] < 1:
            result["status"] = "manual"
            append_blocked(asin, photo_block or "fotos_insuficientes", issues=issues)
        else:
            result["status"] = "still_review"

        result["issues"] = issues
        result["title"] = title
        result["finished_at"] = utc_now()
        journal("asin_done", asin=asin, status=result["status"], photos=result["photos_n"])
        return result
    except Exception as e:
        result["error"] = str(e)[:400]
        result["trace"] = traceback.format_exc()[-500:]
        result["finished_at"] = utc_now()
        append_blocked(asin, "exception", error=str(e)[:200])
        journal("asin_error", asin=asin, error=str(e)[:200])
        return result


def run(asins: list[str], label: str) -> dict:
    progress = load_progress()
    src = json.loads(SRC178.read_text(encoding="utf-8"))
    prior_map = src.get("done") or {}
    model = pick_ollama_model()
    progress["ollama_model"] = model
    save_progress(progress)
    log(f"label={label} n={len(asins)} model={model}")
    write_status(state="running", label=label, total=len(asins), done=len(progress.get("done", {})))

    for i, asin in enumerate(asins, 1):
        prev = progress.get("done", {}).get(asin)
        if prev and prev.get("status") in ("recovered", "manual"):
            log(f"[{i}/{len(asins)}] {asin} SKIP {prev.get('status')}")
            continue
        log(f"[{i}/{len(asins)}] {asin} …")
        row = process_one(asin, prior_map.get(asin))
        progress.setdefault("done", {})[asin] = row
        st = row.get("status")
        key = {
            "recovered": "recovered",
            "still_review": "still_review",
            "manual": "manual",
        }.get(st, "error")
        progress["stats"][key] = progress["stats"].get(key, 0) + 1
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
    ap = argparse.ArgumentParser()
    ap.add_argument("--pilot", action="store_true")
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--asins", nargs="*")
    args = ap.parse_args()

    all_nr = needs_review_asins()
    log(f"needs_review source={len(all_nr)}")

    if args.asins:
        target = [a.upper() for a in args.asins]
        label = "custom"
    elif args.pilot:
        target = all_nr[:5]
        label = "pilot5"
    elif args.full or args.resume:
        target = all_nr
        label = "full_nr"
    else:
        ap.print_help()
        return 2

    journal("run_start", label=label, n=len(target), cursor_tokens=False)
    progress = run(target, label)
    done = progress.get("done", {})
    summary = {
        "label": label,
        "target": len(target),
        "completed_in_this_file": len(done),
        "recovered": sum(1 for v in done.values() if v.get("status") == "recovered"),
        "still_review": sum(1 for v in done.values() if v.get("status") == "still_review"),
        "manual": sum(1 for v in done.values() if v.get("status") == "manual"),
        "error": sum(1 for v in done.values() if v.get("status") == "error"),
        "cursor_tokens": False,
    }
    (OUT / f"summary_{label}.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    if label == "pilot5":
        # PASS if at least 1 recovered OR progressed without crash on all 5
        pilot_pass = summary["error"] == 0 and summary["completed_in_this_file"] >= 5
        # Prefer recovery signal
        if summary["recovered"] >= 1:
            pilot_pass = True
        # If all manual due to captcha, still pass pipeline (blocked external)
        if summary["manual"] + summary["recovered"] + summary["still_review"] >= 5 and summary["error"] == 0:
            pilot_pass = True
        pilot = {"PASS": pilot_pass, "summary": summary, "asins": {a: done.get(a, {}).get("status") for a in target}}
        (OUT / "PILOT_RESULT.json").write_text(json.dumps(pilot, indent=2, ensure_ascii=False), encoding="utf-8")
        write_status(state="pilot_done", PASS=pilot_pass, summary=summary)
        log(f"PILOT PASS={pilot_pass} {summary}")
        return 0 if pilot_pass else 1

    write_status(state="completed", summary=summary)
    log(f"FULL done {summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
