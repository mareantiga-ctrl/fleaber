#!/usr/bin/env python3
"""
ZIP 158 — teste híbrido de fotografias (CDN → HTML /dp → navegador Playwright).
Não altera o LLM PT-PT do ZIP 157. Só fotos + progresso + upsert photos-only.
"""
from __future__ import annotations

import hashlib
import json
import re
import secrets
import subprocess
import time
import urllib.error
import urllib.request
import sys
from pathlib import Path

TOOL = Path(__file__).resolve().parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from amazon_importer_browser_photos import (  # noqa: E402
    CONTINUE,
    fetch_asins as browser_fetch_asins,
    load_progress,
)

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "tool" / "reports" / "amazon_importer_phase1"
JOIN = REPORT / "validation_15_join.json"
OUT = REPORT / "enrich_158"
PHOTO_DIR = OUT / "photos"
PROJECT = "bpmpkzwnrbmuqnhgdscf"

# Ordem de teste: 2 FAIL do ZIP 157 primeiro, depois os restantes 13.
FAIL_157 = ["B0DG4Z6CMY", "B0BKWFY5YP"]

PS_TOKEN = r"""
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class CredManAmz158 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);
  [DllImport("advapi32")] public static extern bool CredFree(IntPtr cred);
  public static string Read(string target) { IntPtr nCred; if(!CredRead(target,1,0,out nCred)) return null; var cred=(CREDENTIAL)Marshal.PtrToStructure(nCred,typeof(CREDENTIAL)); byte[] bytes=new byte[cred.CredentialBlobSize]; Marshal.Copy(cred.CredentialBlob,bytes,0,cred.CredentialBlobSize); CredFree(nCred); return Encoding.UTF8.GetString(bytes);} }
'@
Write-Output ([CredManAmz158]::Read('Supabase CLI:supabase'))
"""


def mgmt_token() -> str:
    t = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_TOKEN], text=True
    ).strip()
    if not t:
        raise SystemExit("CredMan token em falta")
    return t


def run_sql(sql: str):
    tok = mgmt_token()
    body = json.dumps({"query": sql}).encode("utf-8")
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT}/database/query",
        data=body,
        headers={
            "Authorization": f"Bearer {tok}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read().decode())


def dollar_quote(s: str | None) -> str:
    if s is None:
        return "NULL"
    tag = "a" + secrets.token_hex(8)
    return f"${tag}${s}${tag}$"


def http_bytes(url: str, timeout: int = 25) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept": "*/*",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def is_jpeg(data: bytes) -> bool:
    return len(data) >= 2500 and data[0] == 0xFF and data[1] == 0xD8


def ordered_asins() -> list[str]:
    join = json.loads(JOIN.read_text(encoding="utf-8-sig"))
    all_asins = [r["ASIN"].upper() for r in join]
    rest = [a for a in all_asins if a not in FAIL_157]
    return FAIL_157 + rest


def fetch_cdn(asin: str) -> list[dict]:
    found = []
    seen = set()
    for i in range(1, 6):
        nn = f"{i:02d}"
        for url in [
            f"https://m.media-amazon.com/images/P/{asin}.{nn}.LZZZZZZZ.jpg",
            f"https://images-eu.ssl-images-amazon.com/images/P/{asin}.{nn}.LZZZZZZZ.jpg",
        ]:
            try:
                data = http_bytes(url)
            except Exception:
                continue
            if not is_jpeg(data):
                continue
            h = hashlib.md5(data).hexdigest()
            if h in seen:
                continue
            seen.add(h)
            path = PHOTO_DIR / f"{asin}_cdn_{h[:8]}.jpg"
            path.write_bytes(data)
            found.append(
                {
                    "url": url,
                    "bytes": len(data),
                    "md5": h,
                    "local": str(path.relative_to(REPORT)).replace("\\", "/"),
                    "source": "amazon_cdn_pending_rights",
                }
            )
            break
        if len(found) >= 5:
            break
    return found


def extract_product_images(html: str) -> list[str]:
    if re.search(r"captcha|robot check|validateCaptcha", html, re.I):
        return []
    urls: list[str] = []
    for pat in [
        r'"hiRes"\s*:\s*"(https:[^"]+)"',
        r'"large"\s*:\s*"(https:[^"]+)"',
        r'data-old-hires="(https:[^"]+)"',
        r"(https://m\.media-amazon\.com/images/I/[A-Za-z0-9+,_%-]+)",
    ]:
        for m in re.finditer(pat, html, flags=re.I):
            u = m.group(1).replace("\\u002F", "/")
            urls.append(u)
    out = []
    seen = set()
    for u in urls:
        if "media-amazon.com/images/I/" not in u and "images-amazon.com/images/I/" not in u:
            continue
        if any(x in u.lower() for x in ("sprite", "grey-pixel", "play-icon")):
            continue
        base = re.sub(r"\._[A-Z0-9_,]+_\.", "._AC_SL1000_.", u)
        if not re.search(r"\.(jpg|jpeg|png)(?:\?|$)", base, re.I):
            base = base.rstrip(".") + "._AC_SL1000_.jpg"
        if base not in seen:
            seen.add(base)
            out.append(base)
    return out[:12]


def fetch_html_dp(asin: str) -> tuple[list[dict], bool]:
    """Return (photos, captcha_blocked)."""
    captcha = False
    for host in ("es", "it", "de", "fr"):
        url = f"https://www.amazon.{host}/dp/{asin}"
        try:
            data = http_bytes(url, timeout=35)
        except Exception:
            continue
        html = data.decode("utf-8", "replace")
        if re.search(r"captcha|robot check|validateCaptcha", html, re.I):
            captcha = True
            continue
        candidates = extract_product_images(html)
        found = []
        seen = set()
        for img in candidates:
            try:
                raw = http_bytes(img, timeout=20)
            except Exception:
                continue
            if not is_jpeg(raw):
                continue
            h = hashlib.md5(raw).hexdigest()
            if h in seen:
                continue
            seen.add(h)
            path = PHOTO_DIR / f"{asin}_html_{h[:8]}.jpg"
            path.write_bytes(raw)
            found.append(
                {
                    "url": img,
                    "bytes": len(raw),
                    "md5": h,
                    "local": str(path.relative_to(REPORT)).replace("\\", "/"),
                    "source": "amazon_dp_html",
                }
            )
            if len(found) >= 5:
                break
        if found:
            return found, False
        time.sleep(1.2)
    return [], captcha


def upsert_photos(asin: str, photos: list[dict]) -> str | None:
    https_photos = [p for p in photos if str(p.get("url", "")).startswith("https://")]
    photos_json = json.dumps(
        [
            {"url": p["url"], "source": p.get("source") or "amazon_browser_pending_rights"}
            for p in https_photos
        ],
        ensure_ascii=False,
    )
    sql = (
        "select public.batata_amazon_photos_write("
        f"{dollar_quote(asin)}, "
        f"{dollar_quote(photos_json)}::jsonb"
        ") as id;"
    )
    rows = run_sql(sql)
    if isinstance(rows, list) and rows:
        return rows[0].get("id")
    return None


def classify_method(photos: list[dict]) -> str:
    if not photos:
        return "none"
    src = (photos[0].get("source") or "").lower()
    if "cdn" in src:
        return "cdn"
    if "browser" in src:
        return "browser"
    if "dp_html" in src or "html" in src:
        return "html"
    return src or "unknown"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    PHOTO_DIR.mkdir(parents=True, exist_ok=True)

    print("Applying migration photos browser…")
    mig = (
        ROOT
        / "supabase"
        / "migrations"
        / "20261105080000_amazon_importer_browser_photos_batata.sql"
    )
    run_sql(mig.read_text(encoding="utf-8"))
    print("Migration OK")

    asins = ordered_asins()
    print("Ordem:", ", ".join(asins))

    results = []
    need_browser: list[str] = []
    captcha_html_hits = 0

    # Fase 1: CDN + HTML (sem browser) — rápido
    for i, asin in enumerate(asins, 1):
        print(f"\n[{i}/15] {asin} CDN/HTML…")
        row = {
            "asin": asin,
            "photos": [],
            "method": "none",
            "cdn_count": 0,
            "html_count": 0,
            "browser_count": 0,
            "captcha": False,
            "human": False,
            "photo_pass": "FAIL",
            "photo_why": "sem fotografias",
            "product_id": None,
        }
        cdn = fetch_cdn(asin)
        row["cdn_count"] = len(cdn)
        if cdn:
            row["photos"] = cdn
            row["method"] = "cdn"
        else:
            html_photos, blocked = fetch_html_dp(asin)
            row["html_count"] = len(html_photos)
            if blocked:
                captcha_html_hits += 1
                row["captcha"] = True
            if html_photos:
                row["photos"] = html_photos
                row["method"] = "html"
            else:
                need_browser.append(asin)
                print(f"  -> precisa browser")
                results.append(row)
                continue

        row["photo_pass"] = "PASS"
        row["photo_why"] = f"{len(row['photos'])} via {row['method']}"
        try:
            row["product_id"] = upsert_photos(asin, row["photos"])
        except Exception as e:
            row["photo_why"] += f" (upsert err: {e})"
        print(f"  -> {row['photo_pass']} {row['photo_why']}")
        results.append(row)
        time.sleep(0.8)

    # Fase 2: browser só nos que falharam
    browser_stats = {"captcha_hits": 0, "human_interventions": 0}
    if need_browser:
        print(f"\n=== Browser assistido para {len(need_browser)} ASIN ===")
        print("Uma janela Chromium. Se CAPTCHA: resolve e cria", CONTINUE)
        browsed = browser_fetch_asins(need_browser, skip_done=True, pause_between_s=4.0)
        by_asin = {r["asin"].upper(): r for r in browsed}
        prog = load_progress()
        browser_stats = prog.get("stats") or browser_stats

        for row in results:
            if row["method"] != "none":
                continue
            b = by_asin.get(row["asin"].upper()) or {}
            photos = b.get("photos") or []
            row["browser_count"] = len(photos)
            # captcha/human = só o que o browser reportou (não o soft-block HTTP)
            row["html_soft_blocked"] = bool(row.get("captcha"))
            row["captcha"] = bool(b.get("captcha"))
            row["human"] = bool(b.get("human"))
            if photos:
                row["photos"] = photos
                row["method"] = "browser"
                row["photo_pass"] = "PASS"
                row["photo_why"] = f"{len(photos)} via browser ({b.get('market')})"
                try:
                    row["product_id"] = upsert_photos(row["asin"], photos)
                except Exception as e:
                    row["photo_why"] += f" (upsert err: {e})"
            else:
                row["photo_pass"] = "FAIL"
                row["photo_why"] = b.get("error") or "browser sem fotos"
                if b.get("pending"):
                    row["photo_why"] = "pendente (CAPTCHA / bloqueio)"
            print(f"  {row['asin']}: {row['photo_pass']} — {row['photo_why']}")

    # Relatório
    photo_ok = sum(1 for r in results if r["photo_pass"] == "PASS")
    by_method = {
        "cdn": sum(1 for r in results if r["method"] == "cdn"),
        "html": sum(1 for r in results if r["method"] == "html"),
        "browser": sum(1 for r in results if r["method"] == "browser"),
        "none": sum(1 for r in results if r["method"] == "none"),
    }
    # CAPTCHA «do utilizador» = só o que o browser pediu e exigiu intervenção.
    browser_captcha_asins = [
        r["asin"] for r in results if r.get("human") or (r.get("method") == "browser" and r.get("captcha"))
    ]
    human_n = sum(1 for r in results if r.get("human"))
    html_soft_blocked = [
        r["asin"]
        for r in results
        if r.get("captcha") and not r.get("human") and r.get("method") in ("browser", "none")
    ]

    summary = {
        "photos_pass": photo_ok,
        "n": 15,
        "by_method": by_method,
        "captcha_user_asins": browser_captcha_asins,
        "captcha_count": len(browser_captcha_asins),
        "human_interventions": human_n,
        "html_soft_blocked_asins": html_soft_blocked,
        "html_captcha_hits": captcha_html_hits,
        "browser_stats": browser_stats,
        "auto_advance": True,
        "ready_for_larger_batch": photo_ok >= 14 and human_n <= 2,
    }
    (OUT / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (OUT / "teste_15_photos.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        "# ZIP 158 — fotografias Amazon (híbrido + navegador assistido)",
        "",
        f"**Fotos PASS:** **{photo_ok}/15**",
        f"- CDN: {by_method['cdn']} · HTML `/dp`: {by_method['html']} · Browser: {by_method['browser']} · Sem foto: {by_method['none']}",
        f"- CAPTCHA no navegador (intervenção): **{human_n}** — "
        f"{', '.join(browser_captcha_asins) or 'nenhum'}",
        f"- HTML urllib bloqueado (sem pedir humano; recuperado via browser): "
        f"{len(html_soft_blocked)} — {', '.join(html_soft_blocked) or 'nenhum'}",
        f"- Intervenções humanas: **{human_n}**",
        f"- Avanço automático entre produtos: **sim** (1 sessão; pausa só em CAPTCHA)",
        "",
        "## Por ASIN",
        "",
    ]
    for r in results:
        lines.append(
            f"- `{r['asin']}` **{r['photo_pass']}** · método `{r['method']}` · "
            f"n={len(r.get('photos') or [])} · humano={r.get('human')} — {r.get('photo_why')}"
        )
    lines += [
        "",
        "## Comparação 157 → 158",
        "",
        "| Métrica | 157 | 158 |",
        "|---|---:|---:|",
        f"| Fotos | 13 | **{photo_ok}** |",
        "",
        "## Instruções (CAPTCHA)",
        "",
        "1. O Chromium abre sozinho na página do ASIN.",
        "2. Se pedir verificação: resolve no navegador.",
        f"3. Cria o ficheiro vazio `{CONTINUE.as_posix()}` (ou responde «feito» no chat).",
        "4. O processo retoma o ASIN actual e segue para o seguinte.",
        "",
    ]
    (OUT / "RELATORIO_ZIP158.md").write_text(
        "\n".join(lines), encoding="utf-8"
    )
    print("\n=== RESUMO ===")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print("Relatório:", OUT / "RELATORIO_ZIP158.md")


if __name__ == "__main__":
    main()
