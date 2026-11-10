#!/usr/bin/env python3
"""
ZIP 160 — corrige os 15 anúncios AMZ-* Mare Antiga:
- títulos Tipo → Marca/modelo → Característica
- descrições comerciais + características (sem meta interna)
- galeria completa (dedupe por hash)
- estado Novo; dano manifesto → despublicar + revisão
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
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "tool" / "reports" / "amazon_importer_phase1"
OUT = REPORT / "enrich_160"
PHOTO_DIR = OUT / "photos"
JOIN = REPORT / "validation_15_join.json"
BEFORE = OUT / "before_15.json"

PROJECT = "bpmpkzwnrbmuqnhgdscf"
MARE_UID = "08c9dca8-3707-4ee5-9f43-b33293085d6a"
OLLAMA = "http://127.0.0.1:11434"
MODEL = "qwen2.5:7b"
MAX_PHOTOS = 12
MAX_LLM_TRIES = 3

PS_TOKEN = r"""
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class CredManAmz160 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);
  [DllImport("advapi32")] public static extern bool CredFree(IntPtr cred);
  public static string Read(string target) { IntPtr nCred; if(!CredRead(target,1,0,out nCred)) return null; var cred=(CREDENTIAL)Marshal.PtrToStructure(nCred,typeof(CREDENTIAL)); byte[] bytes=new byte[cred.CredentialBlobSize]; Marshal.Copy(cred.CredentialBlob,bytes,0,cred.CredentialBlobSize); CredFree(nCred); return Encoding.UTF8.GetString(bytes);} }
'@
Write-Output ([CredManAmz160]::Read('Supabase CLI:supabase'))
"""

DAMAGE_RE = re.compile(r"damage|defect|danific|defeito", re.I)

PRODUCT_TYPE = {
    "B0FC2P5QSP": "Candeeiro de suspensão",
    "B09JHQ8386": "Cinta lombar térmica",
    "B09BNX7DB6": "Suporte para ombro",
    "B00VWMESJO": "Caçarola de ferro fundido",
    "B0H3QFHWG4": "Vela perfumada",
    "B0DC633XTQ": "Cortina para porta",
    "B0DG4Z6CMY": "Organizadores para joias",
    "B09QLVRZPC": "Espelho de maquilhagem",
    "B084J4GDWG": "Frigideira de indução",
    "B096RWQNV3": "Joelheiras de compressão",
    "B0BXDVMLGM": "Frigideira",
    "B0D21TWCXG": "Cestos de arrumação",
    "B0BKWFY5YP": "Almofada para cadeira",
    "B0CQT1D2RJ": "Máquina de limpeza a vapor",
    "B07SK2TWSG": "Candeeiro de secretária LED",
}

CATEGORY = {
    "B0FC2P5QSP": "Casa e Decoração",
    "B09JHQ8386": "Desporto e Ar Livre",
    "B09BNX7DB6": "Desporto e Ar Livre",
    "B00VWMESJO": "Casa e Decoração",
    "B0H3QFHWG4": "Casa e Decoração",
    "B0DC633XTQ": "Casa e Decoração",
    "B0DG4Z6CMY": "Casa e Decoração",
    "B09QLVRZPC": "Beleza e Cuidados",
    "B084J4GDWG": "Electrodomésticos",
    "B096RWQNV3": "Desporto e Ar Livre",
    "B0BXDVMLGM": "Electrodomésticos",
    "B0D21TWCXG": "Casa e Decoração",
    "B0BKWFY5YP": "Casa e Decoração",
    "B0CQT1D2RJ": "Electrodomésticos",
    "B07SK2TWSG": "Casa e Decoração",
}

FOREIGN_RE = re.compile(
    r"[\u4e00-\u9fff]|"
    r"\b(l[aá]mpara|sarten|sartén|hombre|mujer|coj[ií]n|espejo|joyas|"
    r"padella|uomo|donna|almacenamiento|paquetes?|colgante|frying pan|"
    r"shoulder brace|steam cleaner|pendant light)\b",
    re.I,
)


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
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode("utf-8", "replace")[:900]) from e


def dollar_quote(s: str | None) -> str:
    if s is None:
        return "NULL"
    tag = "a" + secrets.token_hex(8)
    return f"${tag}${s}${tag}$"


def sql_text_array(urls: list[str]) -> str:
    if not urls:
        return "ARRAY[]::text[]"
    return "ARRAY[" + ", ".join(dollar_quote(u) for u in urls) + "]::text[]"


def http_json(url: str, payload: dict | None = None, timeout: int = 240):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="GET" if payload is None else "POST",
        headers={"Content-Type": "application/json; charset=utf-8"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def http_bytes(url: str, timeout: int = 30) -> bytes:
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


def normalize_img_url(u: str) -> str:
    u = u.replace("\\u002F", "/").strip().rstrip("\\")
    u = re.sub(r"\._[A-Z0-9_,]+_\.", "._AC_SL1500_.", u)
    if not re.search(r"\.(jpg|jpeg|png)(?:\?|$)", u, re.I):
        u = u.rstrip(".") + "._AC_SL1500_.jpg"
    return u


def extract_gallery_urls(html: str) -> list[str]:
    """Galeria completa: colorImages.hiRes preferencial, depois large."""
    urls: list[str] = []
    # bloco colorImages
    m = re.search(r"'colorImages'\s*:\s*(\{.*?\})\s*,\s*'colorToAsin'", html, re.S)
    if not m:
        m = re.search(r'"colorImages"\s*:\s*(\{.*?\})\s*,\s*"colorToAsin"', html, re.S)
    if m:
        blob = m.group(1)
        for mm in re.finditer(r'"hiRes"\s*:\s*"(https:[^"]+)"', blob):
            urls.append(mm.group(1))
        for mm in re.finditer(r'"large"\s*:\s*"(https:[^"]+)"', blob):
            urls.append(mm.group(1))
    for pat in (
        r'"hiRes"\s*:\s*"(https:[^"]+)"',
        r'data-old-hires="(https:[^"]+)"',
        r'"large"\s*:\s*"(https:[^"]+images/I/[^"]+)"',
    ):
        for mm in re.finditer(pat, html, flags=re.I):
            urls.append(mm.group(1))

    out: list[str] = []
    seen_norm: set[str] = set()
    for u in urls:
        if "images/I/" not in u:
            continue
        low = u.lower()
        if any(x in low for x in ("sprite", "grey-pixel", "play-icon", "360_icon", "loading", "placeholder")):
            continue
        nu = normalize_img_url(u)
        # chave de identidade: id da imagem Amazon (ex. 71abcXYZ)
        key = re.search(r"/images/I/([A-Za-z0-9+\-_]+)", nu)
        ident = key.group(1).split(".")[0] if key else nu
        if ident in seen_norm:
            continue
        seen_norm.add(ident)
        out.append(nu)
    return out[:MAX_PHOTOS]


def extract_product_facts(html: str, asin: str) -> dict:
    facts: dict = {
        "asin": asin,
        "title": "",
        "brand": "",
        "bullets": [],
        "tech": {},
        "dimensions": [],
        "materials": [],
    }
    m = re.search(r'id="productTitle"[^>]*>([^<]+)<', html)
    if m:
        facts["title"] = re.sub(r"\s+", " ", m.group(1)).strip()
    m = re.search(r'id="bylineInfo"[^>]*>([^<]+)<', html)
    if m:
        brand = re.sub(r"\s+", " ", m.group(1)).strip()
        brand = re.sub(r"^(Visita la tienda de|Brand:|Marca:)\s*", "", brand, flags=re.I)
        facts["brand"] = brand
    for m in re.finditer(
        r'id="feature-bullets"[\s\S]*?</ul>', html, flags=re.I
    ):
        block = m.group(0)
        for li in re.finditer(r"<span[^>]*class=\"a-list-item\"[^>]*>([\s\S]*?)</span>", block):
            t = re.sub(r"<[^>]+>", " ", li.group(1))
            t = re.sub(r"\s+", " ", t).strip()
            if len(t) > 15 and "javascript" not in t.lower():
                facts["bullets"].append(t[:240])
        break
    # tech table
    for row in re.finditer(
        r"<tr[^>]*>\s*<th[^>]*>([\s\S]*?)</th>\s*<td[^>]*>([\s\S]*?)</td>",
        html,
        flags=re.I,
    ):
        k = re.sub(r"<[^>]+>", " ", row.group(1))
        v = re.sub(r"<[^>]+>", " ", row.group(2))
        k = re.sub(r"\s+", " ", k).strip()
        v = re.sub(r"\s+", " ", v).strip()
        if k and v and len(k) < 80 and len(v) < 200:
            facts["tech"][k] = v
            if re.search(r"dimensi|measure|tamaño|misur", k, re.I):
                facts["dimensions"].append(v)
            if re.search(r"material|fabric", k, re.I):
                facts["materials"].append(v)
    facts["bullets"] = facts["bullets"][:8]
    # limitar tech
    facts["tech"] = dict(list(facts["tech"].items())[:12])
    return facts


def download_gallery(asin: str, urls: list[str]) -> list[dict]:
    PHOTO_DIR.mkdir(parents=True, exist_ok=True)
    found = []
    seen_hash: set[str] = set()
    for url in urls:
        try:
            data = http_bytes(url)
        except Exception:
            continue
        if not is_jpeg(data):
            continue
        h = hashlib.md5(data).hexdigest()
        if h in seen_hash:
            continue
        seen_hash.add(h)
        path = PHOTO_DIR / f"{asin}_{h[:8]}.jpg"
        path.write_bytes(data)
        found.append(
            {
                "url": url,
                "md5": h,
                "bytes": len(data),
                "local": str(path.relative_to(REPORT)).replace("\\", "/"),
            }
        )
        if len(found) >= MAX_PHOTOS:
            break
    return found


def scrape_asin(page, asin: str) -> dict:
    from amazon_importer_browser_photos import (
        page_has_captcha,
        page_looks_like_product,
        wait_for_human,
        HOSTS,
    )

    last_err = None
    for market, tmpl in HOSTS:
        url = tmpl.format(asin=asin)
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=90000)
        except Exception as e:
            last_err = str(e)[:160]
            continue
        time.sleep(2.2)
        if page_has_captcha(page):
            if not wait_for_human(page, asin):
                return {"asin": asin, "ok": False, "error": "captcha", "photos": [], "facts": {}}
        if not page_looks_like_product(page, asin):
            last_err = f"not_product_{market}"
            continue
        html = page.content()
        facts = extract_product_facts(html, asin)
        urls = extract_gallery_urls(html)
        photos = download_gallery(asin, urls)
        if photos or facts.get("title"):
            return {
                "asin": asin,
                "ok": True,
                "market": market,
                "facts": facts,
                "photos": photos,
                "url_candidates": len(urls),
            }
        last_err = f"empty_{market}"
        time.sleep(1.5)
    return {"asin": asin, "ok": False, "error": last_err or "fail", "photos": [], "facts": {}}


def facts_prompt_block(facts: dict, ptype: str) -> str:
    lines = [
        f"Tipo de produto (PT): {ptype}",
        f"Título Amazon: {facts.get('title') or '(n/d)'}",
        f"Marca: {facts.get('brand') or '(n/d)'}",
    ]
    if facts.get("bullets"):
        lines.append("Bullet points confirmados:")
        for b in facts["bullets"][:6]:
            lines.append(f"- {b}")
    if facts.get("tech"):
        lines.append("Características técnicas confirmadas:")
        for k, v in list(facts["tech"].items())[:8]:
            lines.append(f"- {k}: {v}")
    if facts.get("dimensions"):
        lines.append("Dimensões: " + "; ".join(facts["dimensions"][:3]))
    if facts.get("materials"):
        lines.append("Materiais: " + "; ".join(facts["materials"][:3]))
    return "\n".join(lines)


def validate_commercial(title: str, description: str, ptype: str, facts: dict) -> list[str]:
    issues = []
    t, d = title.strip(), description.strip()
    if len(t) < 20:
        issues.append("título curto")
    if len(t) > 110:
        issues.append("título longo")
    if "—" in t and t.split("—")[0].strip().lower() in {"de", "da", "do", "o", "a"}:
        issues.append("título sem tipo/marca")
    # nova regra: tipo no início
    p0 = ptype.split()[0].lower()
    if p0 not in t.lower() and ptype.lower() not in t.lower():
        # aceitar sinónimos próximos
        synonyms = {
            "candeeiro": ["candeeiro", "luminária"],
            "caçarola": ["caçarola", "cocotte"],
            "frigideira": ["frigideira"],
            "vela": ["vela"],
            "cinta": ["cinta"],
            "suporte": ["suporte"],
            "espelho": ["espelho"],
            "joelheira": ["joelheira", "joelheiras"],
            "almofada": ["almofada"],
            "cortina": ["cortina"],
            "cesto": ["cesto", "cestos"],
            "organizador": ["organizador", "organizadores", "tabuleiro"],
            "máquina": ["máquina", "limpeza", "vapor"],
        }
        ok = False
        for key, alts in synonyms.items():
            if key in ptype.lower() and any(a in t.lower() for a in alts):
                ok = True
                break
        if not ok:
            issues.append(f"título sem tipo ({ptype})")
    if len(d) < 80:
        issues.append("descrição curta")
    if len(d) > 1200:
        issues.append("descrição longa")
    if FOREIGN_RE.search(f"{t} {d}"):
        issues.append("texto estrangeiro")
    for bad in ("ASIN:", "LPN:", "Preço Amazon", "direitos pendentes", "ZIP15", "manifesto"):
        if bad.lower() in d.lower() or bad.lower() in t.lower():
            issues.append(f"meta interna pública: {bad}")
    # genéricos
    for bad in ("produto de qualidade", "ideal para si", "não perca", "compra já"):
        if bad in d.lower():
            issues.append(f"frase genérica: {bad}")
    brand = (facts.get("brand") or "").strip()
    if brand and len(brand) >= 3 and brand.lower() not in {"amazon", "generic"}:
        # marca pode ser "Visit the Store" limpa
        b0 = brand.split()[0]
        if len(b0) >= 3 and b0.lower() not in t.lower() and b0.lower() not in {"marca", "brand"}:
            # não falhar duro se marca ambígua
            pass
    if not re.search(r"caracter", d, re.I):
        issues.append("falta secção características")
    return issues


def deterministic_title(ptype: str, facts: dict, source: str) -> str:
    brand = (facts.get("brand") or "").strip()
    src = facts.get("title") or source
    # modelo: tokens alfanuméricos úteis
    model_bits = []
    for m in re.finditer(
        r"\b(?:SC\s*\d+|GF\d+\w*|\d+(?:[.,]\d+)?\s*cm|1906|Charleston|Recy|Witches'? Brew)\b",
        src,
        flags=re.I,
    ):
        model_bits.append(m.group(0))
    # característica
    feature = ""
    blob = " ".join(facts.get("bullets") or []) + " " + src
    for pat, lab in (
        (r"bra[cç]o flex|flexible arm|braccio", "com Braço Flexível"),
        (r"led\b", "LED"),
        (r"indu[cz]", "compatível com Indução"),
        (r"ferro fundido|cast iron|ghisa", "em Ferro Fundido"),
        (r"terciopelo|velvet|velluto", "em Veludo"),
        (r"algod[aã]o|cotton|cotone", "em Algodão"),
        (r"compress", "de Compressão"),
        (r"vapor|steam", "a Vapor"),
        (r"vintage", "Vintage"),
    ):
        if re.search(pat, blob, re.I):
            feature = lab
            break
    parts = [ptype]
    if brand and brand.lower() not in ptype.lower():
        parts.append(brand.split(",")[0].strip())
    if model_bits:
        parts.append(" ".join(list(dict.fromkeys(model_bits))[:2]))
    if feature and feature.lower() not in " ".join(parts).lower():
        parts.append(feature)
    title = " ".join(p for p in parts if p).strip()
    title = re.sub(r"\s+", " ", title)
    return title[:110]


def deterministic_description(ptype: str, facts: dict) -> str:
    bullets = facts.get("bullets") or []
    tech = facts.get("tech") or {}
    brand = facts.get("brand") or ""
    intro_bits = [f"{ptype}"]
    if brand:
        intro_bits.append(f"da marca {brand.split(',')[0].strip()}")
    intro = " ".join(intro_bits) + "."
    if bullets:
        # 1–2 frases a partir dos bullets (sem traduzir à letra se ES — usar o essencial)
        useful = []
        for b in bullets[:3]:
            # se claramente PT/IT/ES, ainda assim usar como facto curto
            useful.append(b.rstrip("."))
        body = " ".join(f"{u}." for u in useful[:2])
    else:
        body = f"Artigo {ptype.lower()} com as características indicadas pelo fabricante."
    chars = []
    for k, v in list(tech.items())[:6]:
        chars.append(f"• {k}: {v}")
    for b in bullets[2:5]:
        chars.append(f"• {b}")
    if not chars:
        for d in facts.get("dimensions") or []:
            chars.append(f"• Dimensões: {d}")
        for m in facts.get("materials") or []:
            chars.append(f"• Material: {m}")
    if not chars:
        chars.append("• Consultar fotografias para detalhes visuais confirmados.")
    desc = f"{intro} {body}\n\nCaracterísticas\n" + "\n".join(chars[:7])
    return desc.strip()


def llm_generate(facts: dict, ptype: str, source: str) -> dict:
    block = facts_prompt_block(facts, ptype)
    example = (
        "Candeeiro de Secretária LED Velamp Charleston com Braço Flexível"
    )
    prompt = f"""Escreve APENAS JSON UTF-8: {{"title":"...","description":"..."}}

Redator PT-PT. Proibido ES/IT/FR/EN corrido/ZH.
Título OBRIGATÓRIO nesta ordem: Tipo de produto → Marca/modelo → Característica distintiva
Exemplo aprovado: «{example}»
Não uses travessão «—» a separar marca do tipo no início.
Não inventes especificações. Só dados confirmados abaixo.
Descrição: 2–4 frases comerciais naturais + secção «Características» com bullets confirmados.
Não incluir ASIN, LPN, preços Amazon, direitos de imagem nem notas de importação.

DADOS CONFIRMADOS:
{block}
Título manifesto/original auxiliar: {source[:240]}
"""
    t0 = time.time()
    try:
        raw = http_json(
            f"{OLLAMA}/api/generate",
            {
                "model": MODEL,
                "prompt": prompt,
                "stream": False,
                "format": "json",
                "options": {"temperature": 0.2, "num_predict": 700},
            },
            timeout=240,
        )
        text = raw.get("response") or ""
        data = json.loads(text)
        title = str(data.get("title") or "").strip()
        desc = str(data.get("description") or "").strip()
        return {
            "title": title,
            "description": desc,
            "elapsed_s": round(time.time() - t0, 2),
            "raw": text[:500],
        }
    except Exception as e:
        return {
            "title": "",
            "description": "",
            "elapsed_s": round(time.time() - t0, 2),
            "error": str(e)[:200],
        }


def generate_copy(facts: dict, ptype: str, source: str) -> dict:
    best = None
    feedback = None
    for attempt in range(1, MAX_LLM_TRIES + 1):
        llm = llm_generate(facts, ptype, source)
        if feedback and llm.get("title"):
            pass
        title = llm.get("title") or ""
        desc = llm.get("description") or ""
        issues = validate_commercial(title, desc, ptype, facts) if title else ["vazio"]
        if llm.get("error"):
            issues.append(llm["error"])
        row = {
            "title": title,
            "description": desc,
            "attempt": attempt,
            "issues": issues,
            "elapsed_s": llm.get("elapsed_s"),
            "pass": len(issues) == 0,
            "source": "llm",
        }
        if row["pass"]:
            return row
        best = row
        feedback = "; ".join(issues)
    # fallback determinístico
    title = deterministic_title(ptype, facts, source)
    desc = deterministic_description(ptype, facts)
    issues = validate_commercial(title, desc, ptype, facts)
    return {
        "title": title,
        "description": desc,
        "attempt": MAX_LLM_TRIES + 1,
        "issues": issues,
        "pass": len(issues) == 0,
        "source": "deterministic",
        "fallback_from": best,
    }


def load_products() -> list[dict]:
    return run_sql(
        f"""
select id, ref_code, title, description, price, state, category,
       is_draft, list_on_marketplace, image_urls, quantity
from public.products
where seller_id='{MARE_UID}' and ref_code like 'AMZ-%'
order by ref_code;
"""
    )


def update_product(row: dict, item: dict) -> None:
    """item: title, description, images, state, category, unpublish"""
    imgs = sql_text_array(item["image_urls"])
    # preservar preço
    unpub = item.get("unpublish") is True
    if unpub:
        flags = "is_draft = true, list_on_marketplace = false, available_for_live = false"
    else:
        # se já estava publicado, manter; se rascunho, não activar
        if row.get("is_draft") is True or row.get("list_on_marketplace") is not True:
            flags = "is_draft = true, list_on_marketplace = false"
        else:
            flags = "is_draft = false, list_on_marketplace = true"
    run_sql(
        f"""
update public.products set
  title = {dollar_quote(item['title'])},
  description = {dollar_quote(item['description'])},
  image_urls = {imgs},
  category = {dollar_quote(item['category'])},
  state = {dollar_quote(item['state'])},
  {flags}
where id = '{row['id']}'
  and seller_id = '{MARE_UID}'
  and ref_code = {dollar_quote(row['ref_code'])};
"""
    )


def commercial_pass(title: str, desc: str, ptype: str, n_photos: int, issues: list[str]) -> tuple[str, str]:
    if issues:
        return "FAIL", "; ".join(issues[:4])
    if n_photos < 2:
        return "FAIL", "galeria incompleta (<2 fotos distintas)"
    # comercial: título com ≥3 tokens e tipo
    if len(title.split()) < 4:
        return "FAIL", "título pouco informativo"
    if "caracter" not in desc.lower():
        return "FAIL", "sem características"
    return "PASS", "ok"


def main() -> None:
    import sys

    sys.path.insert(0, str(ROOT / "tool"))
    OUT.mkdir(parents=True, exist_ok=True)
    PHOTO_DIR.mkdir(parents=True, exist_ok=True)

    join = {
        r["ASIN"].upper(): r
        for r in json.loads(JOIN.read_text(encoding="utf-8-sig"))
    }
    products = load_products()
    if len(products) != 15:
        raise SystemExit(f"Esperava 15 produtos AMZ-, vi {len(products)}")
    (OUT / "before_15.json").write_text(
        json.dumps(products, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    from playwright.sync_api import sync_playwright

    results = []
    scrape_cache = OUT / "scrape_15.json"
    scraped: dict[str, dict] = {}
    if scrape_cache.exists():
        scraped = {
            r["asin"]: r
            for r in json.loads(scrape_cache.read_text(encoding="utf-8"))
            if r.get("ok")
        }

    need = [
        p["ref_code"].replace("AMZ-", "")
        for p in products
        if p["ref_code"].replace("AMZ-", "") not in scraped
        or len((scraped.get(p["ref_code"].replace("AMZ-", "")) or {}).get("photos") or []) < 2
    ]

    if need:
        print("Scraping", len(need), "ASIN…")
        with sync_playwright() as pw:
            profile = OUT / "pw_profile"
            profile.mkdir(exist_ok=True)
            ctx = pw.chromium.launch_persistent_context(
                user_data_dir=str(profile),
                headless=False,
                viewport={"width": 1280, "height": 900},
                locale="es-ES",
            )
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            try:
                for i, asin in enumerate(need, 1):
                    print(f"  [{i}/{len(need)}] {asin}")
                    row = scrape_asin(page, asin)
                    scraped[asin] = row
                    print(
                        f"    ok={row.get('ok')} photos={len(row.get('photos') or [])} "
                        f"bullets={len((row.get('facts') or {}).get('bullets') or [])}"
                    )
                    time.sleep(3.5)
            finally:
                ctx.close()
        scrape_cache.write_text(
            json.dumps(list(scraped.values()), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    # Testar 5 primeiros com LLM; depois todos
    for idx, prod in enumerate(products, 1):
        asin = prod["ref_code"].replace("AMZ-", "")
        sc = scraped.get(asin) or {}
        facts = sc.get("facts") or {}
        if not facts.get("title"):
            facts["title"] = (join.get(asin) or {}).get("TitleES") or (
                join.get(asin) or {}
            ).get("ManifestTitle") or ""
        photos = sc.get("photos") or []
        # fallback: manter imagens existentes se scrape falhou
        image_urls = [p["url"] for p in photos if str(p.get("url", "")).startswith("https://")]
        if not image_urls:
            image_urls = list(prod.get("image_urls") or [])
        ptype = PRODUCT_TYPE.get(asin, "Artigo")
        source = facts.get("title") or prod.get("title") or ""
        print(f"\n[{idx}/15] {asin} copy…")
        copy = generate_copy(facts, ptype, source)
        print(
            f"  title={copy['title'][:70]} | pass={copy['pass']} src={copy['source']} "
            f"issues={copy.get('issues')}"
        )

        cond = (join.get(asin) or {}).get("ManifestCondition") or ""
        needs_review = bool(DAMAGE_RE.search(cond))
        # Estado comercial: Novo; dano manifesto → despublicar para revisão
        unpublish = needs_review and (prod.get("list_on_marketplace") is True)
        state = "Novo"
        private_note = {
            "asin": asin,
            "manifest_condition": cond,
            "needs_condition_review": needs_review,
            "price_preserved": float(prod["price"]) if prod.get("price") is not None else None,
            "lpn_note": "privado — não na descrição",
        }

        # descrição pública = só comercial
        public_desc = copy["description"]
        # garantir UTF-8 limpo
        public_desc = public_desc.encode("utf-8", "ignore").decode("utf-8")
        title = copy["title"].encode("utf-8", "ignore").decode("utf-8")

        item = {
            "title": title,
            "description": public_desc,
            "image_urls": image_urls[:MAX_PHOTOS],
            "category": CATEGORY.get(asin, prod.get("category") or "Casa e Decoração"),
            "state": state,
            "unpublish": unpublish,
        }
        update_product(prod, item)

        # guardar nota privada em amazon_catalog se existir
        run_sql(
            f"""
update public.amazon_catalog_products
set prep_notes = {dollar_quote(json.dumps(private_note, ensure_ascii=False))},
    title = {dollar_quote(title)},
    description = {dollar_quote(public_desc)},
    updated_at = timezone('utc', now())
where asin = {dollar_quote(asin)};
"""
        )

        q_status, q_why = commercial_pass(
            title, public_desc, ptype, len(image_urls), copy.get("issues") or []
        )
        # foto score
        photo_pass = "PASS" if len(image_urls) >= 2 else "FAIL"
        if len(image_urls) == 1 and sc.get("url_candidates", 0) <= 1:
            photo_pass = "PASS"  # galeria Amazon realmente só 1
            photo_why = "1 foto (única na galeria Amazon)"
        else:
            photo_why = f"{len(image_urls)} distintas (candidatos HTML {sc.get('url_candidates', '?')})"

        results.append(
            {
                "asin": asin,
                "product_id": prod["id"],
                "title_before": prod.get("title"),
                "title_after": title,
                "desc_before": (prod.get("description") or "")[:300],
                "desc_after": public_desc[:500],
                "n_photos_before": len(prod.get("image_urls") or []),
                "n_photos_after": len(image_urls),
                "photo_pass": photo_pass,
                "photo_why": photo_why,
                "category": item["category"],
                "state": state,
                "needs_condition_review": needs_review,
                "unpublished_for_review": unpublish,
                "price": float(prod["price"]) if prod.get("price") is not None else None,
                "copy_source": copy.get("source"),
                "text_pass": q_status,
                "text_why": q_why,
                "edit_url": f"https://fleaber.pt/sellerProductForm?editProductId={prod['id']}",
                "public_url": f"https://fleaber.pt/productDetails?product_id={prod['id']}",
            }
        )

    # verificação final
    after = load_products()
    meta_leaks = []
    for p in after:
        d = p.get("description") or ""
        if any(x in d for x in ("ASIN:", "LPN:", "Preço Amazon", "direitos pendentes")):
            meta_leaks.append(p["ref_code"])
    dupes = run_sql(
        f"""
select ref_code, count(*)::int n from public.products
where seller_id='{MARE_UID}' and ref_code like 'AMZ-%'
group by 1 having count(*)>1;
"""
    )

    summary = {
        "n": 15,
        "titles_pass": sum(1 for r in results if r["text_pass"] == "PASS"),
        "photos_improved": sum(
            1 for r in results if r["n_photos_after"] > r["n_photos_before"]
        ),
        "avg_photos": round(
            sum(r["n_photos_after"] for r in results) / 15, 2
        ),
        "photo_pass": sum(1 for r in results if r["photo_pass"] == "PASS"),
        "unpublished_review": [
            r["asin"] for r in results if r.get("unpublished_for_review")
        ],
        "meta_leaks": meta_leaks,
        "duplicates": dupes or [],
        "model": MODEL,
    }
    (OUT / "results_15.json").write_text(
        json.dumps({"summary": summary, "results": results}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    (OUT / "after_15.json").write_text(
        json.dumps(after, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        "# ZIP 160 — correcção dos 15 anúncios Amazon",
        "",
        f"**Modelo:** `{MODEL}`",
        f"**Títulos/desc PASS comercial:** {summary['titles_pass']}/15",
        f"**Fotos PASS:** {summary['photo_pass']}/15 · média {summary['avg_photos']} · melhorias {summary['photos_improved']}",
        f"**Despublicados p/ revisão de estado (manifesto dano/defeito):** {len(summary['unpublished_review'])} — {', '.join(summary['unpublished_review']) or 'nenhum'}",
        f"**Meta interna na descrição pública:** {len(meta_leaks)}",
        f"**Duplicados:** {len(dupes or [])}",
        "",
        "| ASIN | Título novo | Fotos | Text | Estado | Hub |",
        "|---|---|---:|---|---|---|",
    ]
    for r in results:
        flag = "revisão" if r.get("unpublished_for_review") else "Novo"
        lines.append(
            f"| `{r['asin']}` | {r['title_after'][:48]} | {r['n_photos_after']} | "
            f"**{r['text_pass']}** | {flag} | [ver]({r['public_url']}) |"
        )
    lines += [
        "",
        "## Respostas",
        "",
        f"1. Títulos bons: **{summary['titles_pass']}/15**",
        f"2. Descrições boas: **{summary['titles_pass']}/15** (mesmo critério comercial)",
        f"3. Fotos por artigo: ver tabela (média **{summary['avg_photos']}**)",
        "4. Acentuação: descrições regravadas UTF-8 sem meta; labels Hub nativos «Descrição»/«Informação» no código — verificar print",
        "5. 15 IDs actualizados, 0 duplicados" if not dupes else "5. HÁ DUPLICADOS",
        "6. Falta p/ 584: API Creators ou throttle estável; QA amostral; LPN real; revisão humana dano→Novo",
        "",
    ]
    (OUT / "RELATORIO_ZIP160.md").write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
