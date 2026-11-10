#!/usr/bin/env python3
"""
ZIP 158 — recuperação de fotografias Amazon com navegador assistido (Playwright).

- Sessão única, headed, sequencial (sem paralelismo agressivo).
- Se aparecer CAPTCHA: para, mantém a janela, pede intervenção humana,
  retoma só depois de acesso normal (ou marca pendente se continuar bloqueado).
- Não resolve CAPTCHA, não usa serviços pagos, não contorna proteções.
"""
from __future__ import annotations

import hashlib
import json
import re
import time
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "tool" / "reports" / "amazon_importer_phase1"
OUT = REPORT / "enrich_158"
PHOTO_DIR = OUT / "photos"
PROGRESS = OUT / "browser_progress.json"
CONTINUE = OUT / "CONTINUE"
PAUSE_INFO = OUT / "captcha_pause.json"
SOURCE = "amazon_browser_pending_rights"

HOSTS = [
    ("es", "https://www.amazon.es/dp/{asin}"),
    ("it", "https://www.amazon.it/dp/{asin}"),
    ("de", "https://www.amazon.de/dp/{asin}"),
    ("fr", "https://www.amazon.fr/dp/{asin}"),
]

CAPTCHA_RE = re.compile(
    r"captcha|robot\s*check|validateCaptcha|opfcaptcha|enter the characters",
    re.I,
)
ASIN_RE = re.compile(r"^[A-Z0-9]{10}$")


def is_jpeg(data: bytes) -> bool:
    return len(data) >= 2500 and data[0] == 0xFF and data[1] == 0xD8


def http_bytes(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def load_progress() -> dict[str, Any]:
    if PROGRESS.exists():
        return json.loads(PROGRESS.read_text(encoding="utf-8"))
    return {"done": {}, "stats": {"captcha_hits": 0, "human_interventions": 0}}


def save_progress(data: dict[str, Any]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    PROGRESS.write_text(
        json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def page_has_captcha(page) -> bool:
    try:
        html = page.content()
    except Exception:
        return False
    if CAPTCHA_RE.search(html or ""):
        return True
    # widgets comuns
    for sel in (
        "#captchacharacters",
        "form[action*='validateCaptcha']",
        "img[src*='captcha']",
    ):
        try:
            if page.locator(sel).count() > 0:
                return True
        except Exception:
            pass
    return False


def page_looks_like_product(page, asin: str) -> bool:
    try:
        url = page.url or ""
        html = page.content() or ""
    except Exception:
        return False
    a = asin.upper()
    if a in url.upper():
        return True
    if re.search(rf'"asin"\s*:\s*"{a}"', html, re.I):
        return True
    if re.search(rf"data-asin=[\"']{a}[\"']", html, re.I):
        return True
    # landing genérica / soft 404
    if re.search(r"Page Not Found|Dog of Amazon|nous sommes d[eé]sol", html, re.I):
        return False
    return "images/I/" in html and ("dp/" in url or "/gp/" in url)


def extract_image_urls(html: str) -> list[str]:
    urls: list[str] = []
    for pat in (
        r'"hiRes"\s*:\s*"(https:[^"]+)"',
        r'"large"\s*:\s*"(https:[^"]+)"',
        r'data-old-hires="(https:[^"]+)"',
        r'data-a-dynamic-image="(\{[^"]+\})"',
        r"(https://m\.media-amazon\.com/images/I/[A-Za-z0-9+,_%-]+)",
        r"(https://images-eu\.ssl-images-amazon\.com/images/I/[A-Za-z0-9+,_%-]+)",
    ):
        for m in re.finditer(pat, html, flags=re.I):
            raw = m.group(1).replace("\\u002F", "/").replace("&quot;", '"')
            if raw.startswith("{"):
                try:
                    obj = json.loads(raw.encode("utf-8").decode("unicode_escape"))
                    urls.extend(obj.keys())
                except Exception:
                    pass
                continue
            urls.append(raw)

    out: list[str] = []
    seen: set[str] = set()
    for u in urls:
        u = u.strip().rstrip("\\")
        if "media-amazon.com/images/I/" not in u and "images-amazon.com/images/I/" not in u:
            continue
        low = u.lower()
        if any(x in low for x in ("sprite", "grey-pixel", "play-icon", "360_icon", "loading")):
            continue
        # normalizar para SL1000 quando possível
        base = re.sub(r"\._[A-Z0-9_,]+_\.", "._AC_SL1000_.", u)
        if not re.search(r"\.(jpg|jpeg|png)(?:\?|$)", base, re.I):
            if "._AC_SL1000_." not in base:
                base = base.rstrip(".") + "._AC_SL1000_.jpg"
        # Dedupe por id de imagem Amazon (mesma foto, URLs/tamanhos diferentes).
        key = re.search(r"/images/I/([A-Za-z0-9+\-_]+)", base)
        ident = key.group(1).split(".")[0] if key else base
        if ident in seen:
            continue
        seen.add(ident)
        out.append(base)
    return out[:16]


def download_photos(asin: str, urls: list[str], max_n: int = 12) -> list[dict]:
    """Descarrega e deduplica por MD5 + dhash perceptual (ZIP 161)."""
    PHOTO_DIR.mkdir(parents=True, exist_ok=True)
    try:
        from amazon_importer_image_dedupe import dedupe_photo_dicts
    except ImportError:
        import sys

        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from amazon_importer_image_dedupe import dedupe_photo_dicts

    raw_photos: list[dict] = []
    for url in urls:
        try:
            data = http_bytes(url)
        except Exception:
            continue
        if not is_jpeg(data):
            continue
        h = hashlib.md5(data).hexdigest()
        raw_photos.append(
            {
                "url": url,
                "bytes": data,
                "md5": h,
                "source": SOURCE,
            }
        )
    unique = dedupe_photo_dicts(raw_photos, max_keep=max_n)
    found: list[dict] = []
    for ph in unique:
        data = ph["bytes"]
        h = ph["md5"]
        path = PHOTO_DIR / f"{asin}_browser_{h[:8]}.jpg"
        path.write_bytes(data)
        found.append(
            {
                "url": ph["url"],
                "bytes": len(data),
                "md5": h,
                "local": str(path.relative_to(REPORT)).replace("\\", "/"),
                "source": SOURCE,
            }
        )
    return found


def notify_captcha(asin: str, url: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    PAUSE_INFO.write_text(
        json.dumps(
            {
                "asin": asin,
                "url": url,
                "message": (
                    "A Amazon requer verificação. Resolve-a no navegador e "
                    "depois cria o ficheiro CONTINUE (ou escreve «feito» no chat)."
                ),
                "continue_file": str(CONTINUE),
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    if CONTINUE.exists():
        CONTINUE.unlink()
    msg = (
        "A Amazon requer verificação. Resolve-a no navegador e carrega em Continuar.\n"
        f"ASIN: {asin}\n"
        f"Ou cria o ficheiro: {CONTINUE}"
    )
    print("\n*** CAPTCHA ***")
    print(msg)
    try:
        import subprocess

        # MessageBox não bloqueia o Python (lançado noutro processo).
        ps = (
            "Add-Type -AssemblyName PresentationFramework; "
            "[System.Windows.MessageBox]::Show("
            f"'A Amazon requer verificação.\\nResolve-a no navegador.\\nASIN: {asin}\\n"
            "Depois cria tool/reports/amazon_importer_phase1/enrich_158/CONTINUE "
            "ou responde feito no chat.',"
            "'Fleaber — CAPTCHA Amazon','OK','Warning')"
        )
        subprocess.Popen(
            ["powershell", "-NoProfile", "-WindowStyle", "Normal", "-Command", ps],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def wait_for_human(page, asin: str, timeout_s: int = 900) -> bool:
    """Espera resolução humana. True se página ficou utilizável."""
    notify_captcha(asin, page.url)
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if CONTINUE.exists():
            try:
                CONTINUE.unlink()
            except Exception:
                pass
            time.sleep(1.0)
            try:
                page.reload(wait_until="domcontentloaded", timeout=60000)
            except Exception:
                pass
            time.sleep(2.0)
            if not page_has_captcha(page) and page_looks_like_product(page, asin):
                if PAUSE_INFO.exists():
                    PAUSE_INFO.unlink()
                return True
            # utilizador pediu continuar mas ainda bloqueado
            return not page_has_captcha(page)
        try:
            if not page_has_captcha(page) and page_looks_like_product(page, asin):
                if PAUSE_INFO.exists():
                    PAUSE_INFO.unlink()
                return True
        except Exception:
            pass
        time.sleep(2.0)
    return False


class BrowserPhotoSession:
    def __init__(self) -> None:
        self._pw = None
        self._browser = None
        self._context = None
        self._page = None
        self.stats = {"captcha_hits": 0, "human_interventions": 0, "pending": []}

    def start(self) -> None:
        from playwright.sync_api import sync_playwright

        self._pw = sync_playwright().start()
        # Perfil persistente = cookies normais da sessão; sem tricks anti-deteção.
        profile = OUT / "pw_profile"
        profile.mkdir(parents=True, exist_ok=True)
        # Navegador normal visível — sem flags de «stealth» / anti-deteção.
        self._context = self._pw.chromium.launch_persistent_context(
            user_data_dir=str(profile),
            headless=False,
            viewport={"width": 1280, "height": 900},
            locale="es-ES",
        )
        self._page = (
            self._context.pages[0]
            if self._context.pages
            else self._context.new_page()
        )

    def close(self) -> None:
        try:
            if self._context:
                self._context.close()
        except Exception:
            pass
        try:
            if self._pw:
                self._pw.stop()
        except Exception:
            pass

    def fetch_asin(self, asin: str) -> dict[str, Any]:
        asin = asin.strip().upper()
        if not ASIN_RE.match(asin):
            return {
                "asin": asin,
                "ok": False,
                "photos": [],
                "captcha": False,
                "human": False,
                "method": "browser",
                "error": "invalid_asin",
            }
        assert self._page is not None
        page = self._page
        last_err = None
        captcha_seen = False
        human = False

        for market, tmpl in HOSTS:
            url = tmpl.format(asin=asin)
            try:
                page.goto(url, wait_until="domcontentloaded", timeout=90000)
            except Exception as e:
                last_err = str(e)[:180]
                continue
            time.sleep(2.5)

            if page_has_captcha(page):
                captcha_seen = True
                self.stats["captcha_hits"] += 1
                self.stats["human_interventions"] += 1
                human = True
                ok_human = wait_for_human(page, asin)
                if not ok_human:
                    self.stats["pending"].append(asin)
                    return {
                        "asin": asin,
                        "ok": False,
                        "photos": [],
                        "captcha": True,
                        "human": True,
                        "method": "browser",
                        "market": market,
                        "error": "captcha_unresolved",
                        "pending": True,
                    }
                # após verificação, revalidar
                if page_has_captcha(page):
                    self.stats["pending"].append(asin)
                    return {
                        "asin": asin,
                        "ok": False,
                        "photos": [],
                        "captcha": True,
                        "human": True,
                        "method": "browser",
                        "market": market,
                        "error": "still_blocked",
                        "pending": True,
                    }

            if not page_looks_like_product(page, asin):
                last_err = f"not_product_{market}"
                continue

            html = page.content()
            urls = extract_image_urls(html)
            photos = download_photos(asin, urls)
            if photos:
                return {
                    "asin": asin,
                    "ok": True,
                    "photos": photos,
                    "captcha": captcha_seen,
                    "human": human,
                    "method": "browser",
                    "market": market,
                    "url_count": len(urls),
                }
            last_err = f"no_jpeg_{market}"
            # pausa leve entre mercados
            time.sleep(1.5)

        return {
            "asin": asin,
            "ok": False,
            "photos": [],
            "captcha": captcha_seen,
            "human": human,
            "method": "browser",
            "error": last_err or "no_photos",
            "pending": captcha_seen,
        }


def fetch_asins(
    asins: list[str],
    *,
    skip_done: bool = True,
    pause_between_s: float = 3.0,
) -> list[dict[str, Any]]:
    """Processa ASIN em série com uma única janela."""
    OUT.mkdir(parents=True, exist_ok=True)
    PHOTO_DIR.mkdir(parents=True, exist_ok=True)
    progress = load_progress()
    results: list[dict[str, Any]] = []
    session = BrowserPhotoSession()
    session.start()
    try:
        for i, asin in enumerate(asins, 1):
            a = asin.upper()
            if skip_done and a in progress.get("done", {}):
                prev = progress["done"][a]
                if prev.get("ok") and prev.get("photos"):
                    print(f"[{i}/{len(asins)}] {a} SKIP (já feito)")
                    results.append(prev)
                    continue
            print(f"[{i}/{len(asins)}] {a} browser…")
            row = session.fetch_asin(a)
            print(
                f"  -> ok={row.get('ok')} photos={len(row.get('photos') or [])} "
                f"captcha={row.get('captcha')} human={row.get('human')} "
                f"err={row.get('error')}"
            )
            progress.setdefault("done", {})[a] = row
            progress["stats"] = {
                "captcha_hits": session.stats["captcha_hits"],
                "human_interventions": session.stats["human_interventions"],
                "pending": list(session.stats["pending"]),
            }
            save_progress(progress)
            results.append(row)
            if i < len(asins):
                time.sleep(pause_between_s)
    finally:
        session.close()
    return results


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("asins", nargs="+")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    rows = fetch_asins(args.asins, skip_done=not args.force)
    print(json.dumps({"n": len(rows), "ok": sum(1 for r in rows if r.get("ok"))}, indent=2))
