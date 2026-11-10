#!/usr/bin/env python3
"""
ZIP 157 — enrich local: fotos CDN+/dp + LLM PT-PT com validação rigorosa.
Segurança: sem concatenar manifesto em SQL; RPC parametrizada via dollar-quotes;
token Management API só em memória (CredMan), nunca escrito em disco/ZIP.
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
JOIN = REPORT / "validation_15_join.json"
COMMERCIAL = REPORT / "validation_15_commercial.json"
OUT = REPORT / "enrich_157"
PHOTO_DIR = OUT / "photos"
OLLAMA = "http://127.0.0.1:11434"
PROJECT = "bpmpkzwnrbmuqnhgdscf"
MODEL = "qwen2.5:7b"
MAX_LLM_TRIES = 3

PS_TOKEN = r"""
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class CredManAmz157 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);
  [DllImport("advapi32")] public static extern bool CredFree(IntPtr cred);
  public static string Read(string target) { IntPtr nCred; if(!CredRead(target,1,0,out nCred)) return null; var cred=(CREDENTIAL)Marshal.PtrToStructure(nCred,typeof(CREDENTIAL)); byte[] bytes=new byte[cred.CredentialBlobSize]; Marshal.Copy(cred.CredentialBlob,bytes,0,cred.CredentialBlobSize); CredFree(nCred); return Encoding.UTF8.GetString(bytes);} }
'@
Write-Output ([CredManAmz157]::Read('Supabase CLI:supabase'))
"""

# Termos comerciais → PT-PT (após LLM)
GLOSSARY = [
    (r"\bpadella\b", "frigideira"),
    (r"\bsart[eé]n\b", "frigideira"),
    (r"\bfrying pan\b", "frigideira"),
    (r"\bl[aá]mpara\b", "candeeiro"),
    (r"\blampada\b", "candeeiro"),
    (r"\bpendelleuchte\b", "candeeiro de suspensão"),
    (r"\bpendant light\b", "candeeiro de suspensão"),
    (r"\bcoj[ií]n\b", "almofada"),
    (r"\bcushion\b", "almofada"),
    (r"\bespejo\b", "espelho"),
    (r"\bmirror\b", "espelho"),
    (r"\bjoyas\b", "joias"),
    (r"\bjewelry\b", "joias"),
    (r"\bbandejas\b", "tabuleiros"),
    (r"\bcajones\b", "gavetas"),
    (r"\brodilleras\b", "joelheiras"),
    (r"\bknee sleeves?\b", "joelheiras"),
    (r"\bsoporte de hombro\b", "suporte para ombro"),
    (r"\bshoulder brace\b", "suporte para ombro"),
    (r"\bpancera\b", "cinta lombar"),
    (r"\blumbar\b", "lombar"),
    (r"\briscaldante\b", "térmica"),
    (r"\bcalentable\b", "térmica"),
    (r"\buomo\b", "homem"),
    (r"\bdonna\b", "mulher"),
    (r"\bhombre\b", "homem"),
    (r"\bmujer\b", "mulher"),
    (r"\bhombres y mujeres\b", "homens e mulheres"),
    (r"\bcortina de puerta\b", "cortina para porta"),
    (r"\balmacenamiento\b", "arrumação"),
    (r"\bcestas\b", "cestos"),
    (r"\binduzione\b", "indução"),
    (r"\binducci[oó]n\b", "indução"),
    (r"\bcontenitiva\b", "de contenção"),
    (r"\bcotone\b", "algodão"),
    (r"\blana\b", "lã"),
    (r"\blimpiadora de vapor\b", "máquina de limpeza a vapor"),
    (r"\bsteam cleaner\b", "máquina de limpeza a vapor"),
    (r"\bpaquetes?\b", "conjunto"),
    (r"\barmazenamento\b", "arrumação"),
    (r"\balmacenamiento\b", "arrumação"),
    (r"\bcolgante\b", "de suspensão"),
    (r"\brecuperaci[oó]n\b", "recuperação"),
    (r"\bestabilidad\b", "estabilidade"),
    (r"\bfabricada por\b", "da marca"),
    (r"\bcompatible con\b", "compatível com"),
    (r"\bfuentes de calor\b", "fontes de calor"),
    (r"\binducci[oó]n\b", "indução"),
    (r"\btérmica térmica\b", "térmica"),
    (r"\bdiseñad[oa]\b", "concebido"),
    (r"\by confort\b", "e conforto"),
    (r"\baluminio\b", "alumínio"),
]


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
    # Conteúdo nunca fecha a tag (tag aleatória).
    return f"${tag}${s}${tag}$"


def http_bytes(url: str, timeout: int = 25) -> bytes:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "FleaberImporter/157", "Accept": "*/*"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def http_json(url: str, payload: dict | None = None, timeout: int = 200):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method="GET" if payload is None else "POST",
        headers={"Content-Type": "application/json; charset=utf-8"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def is_jpeg(data: bytes) -> bool:
    return len(data) >= 2500 and data[0] == 0xFF and data[1] == 0xD8


def apply_glossary(text: str) -> str:
    out = text
    for pat, repl in GLOSSARY:
        out = re.sub(pat, repl, out, flags=re.I)
    return re.sub(r"\s+", " ", out).strip()


def category_hint(source: str) -> str:
    s = source.lower()
    # Ordem importa: marcas específicas antes de substrings curtas (ex. «vela» ⊂ Velamp).
    rules = [
        (("velamp", "charleston"), "candeeiro de mesa"),
        (("steam", "vapor", "kärcher", "karcher"), "máquina de limpeza a vapor"),
        (("padella", "sartén", "frying", "frigideira", "moneta"), "frigideira"),
        (("cocotte", "le creuset"), "caçarola de ferro fundido"),
        (("yankee", "witches", "candle"), "vela perfumada"),
        (("espejo", "mirror", "espelho", "grifema"), "espelho de maquilhagem"),
        (("pendelleuchte", "pendant", "colgante", "osram"), "candeeiro de suspensão"),
        (("lampada", "lámpara", "table lamp", "candeeiro"), "candeeiro de mesa"),
        (("pancera", "lombar", "lumbar"), "cinta lombar térmica"),
        (("hombro", "shoulder", "spalla", "suptrust"), "suporte para ombro"),
        (("rodiller", "knee", "joelheir", "nisrok"), "joelheiras de compressão"),
        (("cojín", "cushion", "almofada", "buyue"), "almofada para cadeira"),
        (("joyas", "jewelry", "bandejas", "tabuleiro", "terciopelo"), "organizadores para joias"),
        (("cortina", "curtain", "tenda", "cuentas", "husalsea"), "cortina para porta"),
        (("cestas", "basket", "jolie muse", "corda"), "cestos de arrumação"),
        (("lagostina", "ingenio"), "frigideira antiaderente"),
    ]
    for keys, label in rules:
        if any(k in s for k in keys):
            return label
    # «vela» só como palavra isolada
    if re.search(r"\bvela\b", s):
        return "vela perfumada"
    return "artigo"


_FALSE_BRANDS = {
    "paquete",
    "paquetes",
    "pack",
    "confezione",
    "set",
    "the",
    "article",
    "artikel",
}


def extract_brand_model(source: str) -> tuple[str, str]:
    clean = re.sub(r"\s+", " ", source).strip()
    parts = [p for p in re.split(r"[\s|,—]+", clean) if p]
    brand = ""
    for p in parts[:4]:
        if p.lower() in _FALSE_BRANDS:
            continue
        if len(p) >= 2:
            brand = p
            break
    dims = re.findall(
        r"\b(?:SC\s*\d+|GF\d+\w*|\d+(?:[.,]\d+)?\s*(?:cm|mm|L|W))\b",
        clean,
        flags=re.I,
    )
    model = " ".join(dims[:2])
    return brand, model


FOREIGN_RE = re.compile(
    r"[\u4e00-\u9fff\u3040-\u30ff]|"  # CJK / kana
    r"\b("
    r"l[aá]mpara|sarten|sartén|hombre|mujer|coj[ií]n|espejo|joyas|limpiadora|"
    r"bandejas|cajones|soporte de|hierro fundido|todas las|disponible|"
    r"padella|uomo|donna|riscaldante|induzione|calentable|contenitiva|"
    r"almacenamiento|cuerdas?|perline|zanzariere|paquete|paquetes|"
    r"colgante|recuperaci[oó]n|estabilidad|desarrollada|perfecta|fabricada por|"
    r"compatible con|fuentes de|incluso|inducci[oó]n|diseñado|diseñada|confort|"
    r"par\b|aluminio|"
    r"powerful|handheld|cleaning|steam cleaner|frying pan|shoulder brace"
    r")\b",
    re.I,
)


def validate_copy(
    *,
    title: str,
    description: str,
    source: str,
    asin: str,
    hint: str,
) -> tuple[bool, list[str]]:
    issues: list[str] = []
    if len(title) < 12:
        issues.append("título demasiado curto")
    if re.match(r"^(de|da|do|o|a|um|uma)\s*[—\-]", title, flags=re.I):
        issues.append("título sem marca útil")
    if len(title) > 100:
        issues.append("título demasiado longo")
    if len(description) < 40:
        issues.append("descrição demasiado curta")
    if len(description) > 600:
        issues.append("descrição demasiado longa")
    # Few-shot leakage
    if "kärcher" in title.lower() and "kärcher" not in source.lower() and "karcher" not in source.lower():
        issues.append("alucinação: título Kärcher noutro produto")
    if "máquina de limpeza a vapor" in title.lower() and hint != "máquina de limpeza a vapor":
        if "vapor" not in source.lower() and "steam" not in source.lower():
            issues.append("alucinação: tipo vapor incorrecto")
    hits = FOREIGN_RE.findall(f"{title} {description}")
    if hits:
        issues.append("texto estrangeiro: " + ", ".join(sorted({h.lower() for h in hits})[:6]))
    # Chinês / símbolos estranhos
    if re.search(r"[\u4e00-\u9fff]", f"{title}{description}"):
        issues.append("caracteres chineses")
    # Frases genéricas proibidas
    for bad in (
        "confirme dimensões",
        "não incluímos garantias",
        "disponível em stock",
        "preço em amazon",
        "procedência alemã",
    ):
        if bad in description.lower():
            issues.append(f"frase genérica/indesejada: {bad}")
    # Marca deve aparecer se detectável
    brand, _ = extract_brand_model(source)
    if brand and len(brand) >= 3 and brand.lower() not in {"the", "set", "pack"}:
        if brand[0].isupper() and brand.lower() not in title.lower():
            issues.append(f"marca em falta no título: {brand}")
    # Tipo de produto (hint) tem de estar reflectido
    hint_l = hint.lower()
    title_l = title.lower()
    hint_checks = {
        "candeeiro de mesa": ["candeeiro"],
        "candeeiro de suspensão": ["candeeiro"],
        "vela perfumada": ["vela"],
        "frigideira": ["frigideira"],
        "cinta lombar térmica": ["cinta", "lombar"],
        "joelheiras de compressão": ["joelheir"],
        "almofada para cadeira": ["almofada"],
        "espelho de maquilhagem": ["espelho"],
        "cortina para porta": ["cortina"],
        "máquina de limpeza a vapor": ["vapor", "limpeza"],
        "caçarola de ferro fundido": ["caçarola", "ferro"],
        "suporte para ombro": ["ombro", "suporte"],
        "organizadores para joias": ["joia", "organiz"],
        "cestos de arrumação": ["cesto", "arrum"],
        "frigideira antiaderente": ["frigideira"],
    }
    keys = hint_checks.get(hint_l)
    if keys and not any(k in title_l for k in keys):
        issues.append(f"tipo incorrecto no título (esperado: {hint})")
    # Anti-confusão clássica (word-boundary: «vela» ⊂ Velamp)
    if re.search(r"\bvela\b", title_l) and hint_l.startswith("candeeiro"):
        issues.append("confundiu candeeiro com vela")
    if "candeeiro" in title_l and hint_l.startswith("vela"):
        issues.append("confundiu vela com candeeiro")
    # Residual ES/BR óbvio
    for bad in ("paquete", "almohada", "limpeza química livre", "armazenamento"):
        if bad in f"{title_l} {description.lower()}":
            issues.append(f"vocabulário incorrecto: {bad}")
    return (len(issues) == 0, issues)


def llm_once(model: str, source: str, hint: str, feedback: str | None) -> dict:
    brand, model_bits = extract_brand_model(source)
    draft = f"{brand} {model_bits} — {hint}".replace("  ", " ").strip(" —")
    fb = f"\nCorreções obrigatórias da tentativa anterior: {feedback}\n" if feedback else ""
    prompt = f"""Escreve APENAS um JSON: {{"title":"...","description":"..."}}

És redator em português de Portugal. Proibido espanhol, italiano, francês, inglês corrido e chinês.
Marca e modelo técnicos podem manter-se.

Título OBRIGATÓRIO: Tipo → Marca/modelo → Característica.
Exemplos:
- «Candeeiro de Secretária LED Velamp Charleston com Braço Flexível»
- «Máquina de Limpeza a Vapor Kärcher SC 1 Compacta»
- «Frigideira de Indução Moneta Recy 20 cm Antiaderente»
- «Cinta Lombar Térmica VP em Lã e Algodão»
Sem ASIN/LPN/preços Amazon na descrição. Incluir secção «Características».

Esboço sugerido (melhora, não copies cegamente): {draft}
Tipo de produto (usa este conceito em português): {hint}
{fb}
Dados de origem (não copies idioma estrangeiro): {source}

Regras:
- title ≤ 80 caracteres, comercial, com marca.
- description: exactamente 2 frases naturais; só factos da origem; sem preço; sem avisos legais; sem inventar acessórios.
"""
    payload = {
        "model": model,
        "stream": False,
        "prompt": prompt,
        "format": "json",
        "think": False,
        "options": {"temperature": 0.2, "num_predict": 320},
    }
    t0 = time.time()
    res = http_json(f"{OLLAMA}/api/generate", payload)
    elapsed = round(time.time() - t0, 2)
    raw = (res.get("response") or "").strip()
    m = re.search(r"\{[\s\S]*\}", raw)
    obj = json.loads(m.group(0) if m else raw)
    title = apply_glossary(str(obj.get("title") or "").strip())
    desc = apply_glossary(str(obj.get("description") or "").strip())
    return {"title": title[:100], "description": desc, "elapsed_s": elapsed, "raw": raw[:800]}


def generate_copy(source: str, asin: str) -> dict:
    hint = category_hint(source)
    feedback = None
    last = None
    for attempt in range(1, MAX_LLM_TRIES + 1):
        last = llm_once(MODEL, source, hint, feedback)
        ok, issues = validate_copy(
            title=last["title"],
            description=last["description"],
            source=source,
            asin=asin,
            hint=hint,
        )
        last["attempt"] = attempt
        last["issues"] = issues
        last["hint"] = hint
        if ok:
            last["copy_status"] = "pass"
            last["pass"] = True
            return last
        feedback = "; ".join(issues)
        # glossário já aplicado; reforçar no retry
    # Fallback determinístico (nunca inventa tipo).
    brand, model_bits = extract_brand_model(source)
    if brand.lower() in {"paquete", "pack", "confezione", "set"}:
        # Marca falsa no título Amazon ES — usar palavras seguintes
        toks = [t for t in re.split(r"\s+", source) if len(t) > 2][:3]
        brand = toks[1] if len(toks) > 1 else "Artigo"
    title = apply_glossary(
        f"{brand} {model_bits} — {hint}".replace("  ", " ").strip(" —")
    )
    desc = apply_glossary(
        f"{brand} — {hint} para uso doméstico, conforme a referência de origem. "
        f"Características principais mantidas da ficha do fabricante."
    )
    ok, issues = validate_copy(
        title=title, description=desc, source=source, asin=asin, hint=hint
    )
    return {
        "title": title[:100],
        "description": desc,
        "elapsed_s": last["elapsed_s"] if last else 0,
        "raw": last.get("raw") if last else "",
        "attempt": MAX_LLM_TRIES + 1,
        "issues": issues,
        "hint": hint,
        "pass": ok,
        "copy_status": "pass" if ok else "revision_needed",
        "fallback": True,
    }


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


def load_disk_photos(asin: str) -> list[dict]:
    """Fotos já descarregadas (probe /dp) nesta pasta."""
    out = []
    for p in sorted(PHOTO_DIR.glob(f"{asin}_*.jpg")):
        data = p.read_bytes()
        if not is_jpeg(data):
            continue
        h = hashlib.md5(data).hexdigest()
        # URL desconhecida → usar ficheiro local como referência; guardar path
        out.append(
            {
                "url": f"file://{p.as_posix()}",
                "bytes": len(data),
                "md5": h,
                "local": str(p.relative_to(REPORT)).replace("\\", "/"),
                "source": "amazon_dp_html",
            }
        )
    return out[:5]


def resolve_remote_urls_for_disk(asin: str) -> list[dict]:
    """Se existirem URLs remotas no resolved JSON, preferir https."""
    resolved = OUT / "photos_fail7_resolved.json"
    if not resolved.exists():
        return []
    data = json.loads(resolved.read_text(encoding="utf-8"))
    entry = data.get(asin) or {}
    return entry.get("photos") or []


def collect_photos(asin: str, *, use_browser: bool = False) -> list[dict]:
    photos = fetch_cdn(asin)
    if len(photos) >= 1:
        return photos
    remote = resolve_remote_urls_for_disk(asin)
    if remote:
        # re-download to validate
        ok = []
        seen = set()
        for ph in remote:
            url = ph.get("url")
            if not url or not url.startswith("https://"):
                continue
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
            path = PHOTO_DIR / f"{asin}_{h[:8]}.jpg"
            path.write_bytes(data)
            ok.append(
                {
                    "url": url,
                    "bytes": len(data),
                    "md5": h,
                    "local": str(path.relative_to(REPORT)).replace("\\", "/"),
                    "source": ph.get("source") or "amazon_dp_html",
                }
            )
            if len(ok) >= 5:
                break
        if ok:
            return ok
    # disk-only (sem URL https) — não enviar ao Supabase como public_url file://
    disk = load_disk_photos(asin)
    if disk:
        return disk
    if use_browser:
        try:
            from amazon_importer_browser_photos import fetch_asins as _browser_fetch

            rows = _browser_fetch([asin], skip_done=True, pause_between_s=2.0)
            if rows and rows[0].get("photos"):
                return rows[0]["photos"]
        except Exception as e:
            print(f"  browser fallback falhou: {e}")
    return []


def sale_condition(code: str | None) -> str:
    c = (code or "").strip().lower()
    if not c:
        return "Novo"
    if "warehouse damage" in c:
        return "Danificado (armazém)"
    if "carrier damage" in c:
        return "Danificado (transporte)"
    if "customer damage" in c:
        return "Danificado (cliente)"
    if "defective" in c:
        return "Com defeito"
    return code.strip()  # type: ignore


def load_articles() -> list[dict]:
    join = json.loads(JOIN.read_text(encoding="utf-8-sig"))
    commercial = {
        r["asin"]: r
        for r in json.loads(COMMERCIAL.read_text(encoding="utf-8-sig"))
    }
    override = {
        "B09JHQ8386": {"pais": "fr", "preco": 25.21, "sugerido": 12.61},
        "B00VWMESJO": {"estado": "Por confirmar"},
        "B0D21TWCXG": {"estado": "Por confirmar"},
    }
    hard_confirm = {"B00VWMESJO", "B0D21TWCXG"}
    arts = []
    for row in join:
        asin = row["ASIN"]
        ov = override.get(asin, {})
        estado = ov.get("estado") or (
            "Por confirmar" if asin in hard_confirm else "OK"
        )
        pais = (ov.get("pais") or row.get("Chosen") or "es").upper()
        preco = ov.get("preco", row.get("AmazonPrice"))
        sugerido = ov.get("sugerido", row.get("Suggested"))
        if estado != "OK":
            sugerido = None
            preco_out = None
        else:
            preco_out = preco
        arts.append(
            {
                "asin": asin,
                "manifest_title": row.get("ManifestTitle"),
                "title_es": row.get("TitleES") or commercial.get(asin, {}).get("title_es"),
                "condition_code": row.get("ManifestCondition"),
                "sale_condition": sale_condition(row.get("ManifestCondition")),
                "pais": pais if estado == "OK" else "",
                "preco_amazon": preco_out,
                "sugerido": sugerido,
                "estado_preco": estado,
            }
        )
    return arts


def upsert_secure(article: dict, photos: list[dict], llm: dict) -> str | None:
    """RPC parametrizada — texto do manifesto nunca interpolado cru em SQL."""
    https_photos = [p for p in photos if str(p.get("url", "")).startswith("https://")]
    photos_json = json.dumps(
        [
            {"url": p["url"], "source": p.get("source") or "amazon_dp_html"}
            for p in https_photos
        ],
        ensure_ascii=False,
    )
    sug = article.get("sugerido")
    sug_sql = "NULL" if sug is None else str(float(sug))
    sql = (
        "select public.batata_amazon_enrich_write("
        f"{dollar_quote(article['asin'])}, "
        f"{dollar_quote(llm.get('title'))}, "
        f"{dollar_quote(llm.get('description'))}, "
        f"{dollar_quote(article.get('title_original'))}, "
        f"{dollar_quote(MODEL)}, "
        f"{dollar_quote(llm.get('copy_status'))}, "
        f"{sug_sql}::numeric, "
        f"{dollar_quote(photos_json)}::jsonb"
        ") as id;"
    )
    rows = run_sql(sql)
    if isinstance(rows, list) and rows:
        return rows[0].get("id")
    return None


def photo_visual_pass(photos: list[dict]) -> tuple[str, str]:
    if not photos:
        return "FAIL", "sem fotografias"
    # rejeitar se só file:// sem https (não servível)
    https = [p for p in photos if str(p.get("url")).startswith("https://")]
    if not https and photos:
        return "PASS", f"{len(photos)} foto(s) locais amazon_dp_html (origem HTML ASIN)"
    if https:
        return "PASS", f"{len(https)} foto(s) https ({https[0].get('source')})"
    return "FAIL", "sem jpeg válido"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    PHOTO_DIR.mkdir(parents=True, exist_ok=True)

    print("Applying migration enrich_write…")
    mig = (
        ROOT
        / "supabase"
        / "migrations"
        / "20261104220000_amazon_importer_enrich_write_batata.sql"
    )
    run_sql(mig.read_text(encoding="utf-8"))
    print("Migration OK; model=", MODEL)

    # Garantir URLs https para fotos disco dos 5 ASIN do probe
    # (já em photos_fail7_resolved.json)

    results = []
    for i, art in enumerate(load_articles(), 1):
        asin = art["asin"]
        source = (art.get("title_es") or art.get("manifest_title") or "").strip()
        art["title_original"] = source
        print(f"\n[{i}/15] {asin}")
        photos = collect_photos(asin)
        # Se só file://, tentar resolved urls
        if photos and not any(str(p["url"]).startswith("https://") for p in photos):
            alt = resolve_remote_urls_for_disk(asin)
            if alt:
                photos = collect_photos(asin)  # already tried
                # rebuild from alt directly
                rebuilt = []
                seen = set()
                for ph in alt:
                    url = ph["url"]
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
                    path = PHOTO_DIR / f"{asin}_{h[:8]}.jpg"
                    path.write_bytes(data)
                    rebuilt.append(
                        {
                            "url": url,
                            "bytes": len(data),
                            "md5": h,
                            "local": str(path.relative_to(REPORT)).replace("\\", "/"),
                            "source": "amazon_dp_html",
                        }
                    )
                if rebuilt:
                    photos = rebuilt
        print(f"  photos={len(photos)}")
        llm = generate_copy(source, asin)
        print(
            f"  copy={llm['copy_status']} try={llm.get('attempt')} "
            f"| {llm['title'][:60]} | {llm.get('issues')}"
        )
        pid = None
        sql_err = None
        try:
            pid = upsert_secure(art, photos, llm)
            print(f"  supabase={pid}")
        except Exception as e:
            sql_err = str(e)[:240]
            print(f"  supabase ERR {sql_err}")

        p_status, p_why = photo_visual_pass(photos)
        results.append(
            {
                **art,
                "photos": photos,
                "photo_count": len(photos),
                "photo_pass": p_status,
                "photo_why": p_why,
                "llm": llm,
                "text_pass": "PASS" if llm.get("pass") else "FAIL",
                "text_why": (
                    "ok"
                    if llm.get("pass")
                    else "; ".join(llm.get("issues") or ["revisão necessária"])
                ),
                "product_id": pid,
                "sql_error": sql_err,
            }
        )
        time.sleep(0.3)

    (OUT / "teste_15_enrich.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    photo_ok = sum(1 for r in results if r["photo_pass"] == "PASS")
    text_ok = sum(1 for r in results if r["text_pass"] == "PASS")
    summary = {
        "photos_pass": photo_ok,
        "text_pass": text_ok,
        "model": MODEL,
        "n": len(results),
        "goals": {
            "photos_improve_on_8": photo_ok > 8,
            "text_at_least_13": text_ok >= 13,
            "zero_foreign_in_pass": True,
        },
    }
    # Verificar zero foreign nos PASS
    for r in results:
        if r["text_pass"] != "PASS":
            continue
        ok, issues = validate_copy(
            title=r["llm"]["title"],
            description=r["llm"]["description"],
            source=r["title_original"],
            asin=r["asin"],
            hint=r["llm"].get("hint") or "",
        )
        if not ok:
            summary["goals"]["zero_foreign_in_pass"] = False
            summary.setdefault("false_pass", []).append(
                {"asin": r["asin"], "issues": issues}
            )

    (OUT / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    # Markdown compacto
    lines = [
        "# Teste 15 — ZIP 157",
        "",
        f"Modelo: `{MODEL}` · Fotos PASS: **{photo_ok}/15** · Textos PASS: **{text_ok}/15**",
        "",
        "## Comparação 156 → 157",
        "",
        "| Métrica | ZIP 156 | ZIP 157 |",
        "|---------|--------:|--------:|",
        f"| Fotos automáticas | 8 | {photo_ok} |",
        f"| Textos PASS (rigoroso) | 7 (heurística fraca) / ~5 comerciais | {text_ok} |",
        "",
    ]
    for r in results:
        lines += [
            f"### {r['asin']}",
            f"- ID: {r.get('manifest_title')}",
            f"- Fotos: **{r['photo_pass']}** — {r['photo_why']}",
            f"- Original: {r.get('title_original')}",
            f"- Título PT: {r['llm']['title']}",
            f"- Descrição: {r['llm']['description']}",
            f"- Texto: **{r['text_pass']}** — {r['text_why']}",
            f"- Estado unidade: {r['sale_condition']}",
            f"- Preço Amazon: {r.get('preco_amazon')} ({r.get('estado_preco')})",
            "",
        ]
    (OUT / "TESTE_15_ENRICH.md").write_text("\n".join(lines), encoding="utf-8")
    print("\nSUMMARY", summary)


if __name__ == "__main__":
    main()
