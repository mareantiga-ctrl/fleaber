#!/usr/bin/env python3
"""
ZIP 159 — cria 15 rascunhos privados (is_draft=true) na conta Mare Antiga
a partir dos dados Amazon já enriquecidos (ZIP 157/158).

- Sem publicar (list_on_marketplace=false, available_for_live=false, is_draft=true)
- Idempotente por ref_code AMZ-{ASIN}
- Não inventa preços quando estado_preco != OK
- Não altera o importador nem envia Moloni
"""
from __future__ import annotations

import json
import re
import secrets
import subprocess
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "tool" / "reports" / "amazon_importer_phase1"
OUT = REPORT / "enrich_159"
JOIN = REPORT / "validation_15_join.json"
ENRICH157 = REPORT / "enrich_157" / "teste_15_enrich.json"
PHOTOS158 = REPORT / "enrich_158" / "teste_15_photos.json"

PROJECT = "bpmpkzwnrbmuqnhgdscf"
MARE_UID = "08c9dca8-3707-4ee5-9f43-b33293085d6a"
MARE_EMAIL = "mareantiga@gmail.com"
MARE_HANDLE = "mariana-prod"
HUB_BASE = "https://fleaber.pt"

PS_TOKEN = r"""
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class CredManAmz159 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);
  [DllImport("advapi32")] public static extern bool CredFree(IntPtr cred);
  public static string Read(string target) { IntPtr nCred; if(!CredRead(target,1,0,out nCred)) return null; var cred=(CREDENTIAL)Marshal.PtrToStructure(nCred,typeof(CREDENTIAL)); byte[] bytes=new byte[cred.CredentialBlobSize]; Marshal.Copy(cred.CredentialBlob,bytes,0,cred.CredentialBlobSize); CredFree(nCred); return Encoding.UTF8.GetString(bytes);} }
'@
Write-Output ([CredManAmz159]::Read('Supabase CLI:supabase'))
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
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:800]
        raise RuntimeError(f"SQL HTTP {e.code}: {detail}\n--- SQL ---\n{sql[:500]}") from e


def dollar_quote(s: str | None) -> str:
    if s is None:
        return "NULL"
    tag = "a" + secrets.token_hex(8)
    return f"${tag}${s}${tag}$"


def sql_text_array(urls: list[str]) -> str:
    if not urls:
        return "ARRAY[]::text[]"
    parts = [dollar_quote(u) for u in urls]
    return "ARRAY[" + ", ".join(parts) + "]::text[]"


def map_state(sale_condition: str | None, condition_code: str | None) -> str:
    s = (sale_condition or "").strip().lower()
    c = (condition_code or "").strip().lower()
    if "defeito" in s or "defective" in c:
        return "Com Defeito"
    if "danificado" in s or "damage" in c:
        return "Satisfatório"
    if s == "novo" or c in ("sellable", "new", ""):
        # Manifesto sem dano → Novo; seed Sellable sem mapeamento explícito
        if "damage" in c or "defect" in c:
            return "Satisfatório"
        if c in ("sellable",) and not s:
            return "Novo"
        if not s and not c:
            return "Novo"
        if "novo" in s:
            return "Novo"
    if "danificado" in s:
        return "Satisfatório"
    # fallback: se manifesto tem código de dano
    if "damage" in c:
        return "Satisfatório"
    if "defect" in c:
        return "Com Defeito"
    return "Novo" if not s else "Satisfatório"


def guess_category(title: str, hint: str = "") -> str:
    t = f"{title} {hint}".lower()
    rules = [
        (("frigideira", "caçarola", "kärcher", "karcher", "vapor", "electro"), "Electrodomésticos"),
        (("candeeiro", "vela", "espelho", "cortina", "cesto", "almofada", "joia", "tabuleiro", "decor"), "Casa e Decoração"),
        (("joelheira", "ombro", "cinta", "lombar", "suporte", "desporto"), "Desporto e Ar Livre"),
        (("beleza", "maquilhagem"), "Beleza e Cuidados"),
    ]
    for keys, cat in rules:
        if any(k in t for k in keys):
            return cat
    return "Casa e Decoração"


def ref_code(asin: str) -> str:
    return f"AMZ-{asin.upper()}"


def edit_url(product_id: str) -> str:
    return f"{HUB_BASE}/sellerProductForm?editProductId={product_id}"


def drafts_list_url() -> str:
    return f"{HUB_BASE}/gestaoReferencias"


def load_sources() -> list[dict]:
    join = {
        r["ASIN"].upper(): r
        for r in json.loads(JOIN.read_text(encoding="utf-8-sig"))
    }
    enrich = {
        r["asin"].upper(): r
        for r in json.loads(ENRICH157.read_text(encoding="utf-8"))
    }
    photos158 = {
        r["asin"].upper(): r
        for r in json.loads(PHOTOS158.read_text(encoding="utf-8"))
    }

    # Dados canónicos na BD (títulos LLM + fotos upsert)
    asins = list(join.keys())
    quoted = ",".join("'" + a + "'" for a in asins)
    catalog = run_sql(
        f"""
select asin, id, title, description, suggested_sale_eur, copy_status,
       primary_image_url
from public.amazon_catalog_products
where asin in ({quoted});
"""
    )
    cat_by = {c["asin"].upper(): c for c in catalog or []}
    photo_rows = run_sql(
        f"""
select p.asin, ph.public_url, ph.sort_order, ph.source
from public.amazon_catalog_products p
join public.amazon_product_photos ph on ph.product_id = p.id
where p.asin in ({quoted})
order by p.asin, ph.sort_order nulls last, ph.created_at;
"""
    )
    photos_by: dict[str, list[str]] = {}
    for ph in photo_rows or []:
        url = (ph.get("public_url") or "").strip()
        if not url.startswith("https://"):
            continue
        photos_by.setdefault(ph["asin"].upper(), []).append(url)

    units = run_sql(
        f"""
select asin, lpn, qty, condition_code, condition_label
from public.amazon_catalog_units
where asin in ({quoted});
"""
    )
    units_by: dict[str, list[dict]] = {}
    for u in units or []:
        units_by.setdefault(u["asin"].upper(), []).append(u)

    out = []
    for asin in asins:
        j = join[asin]
        e = enrich.get(asin) or {}
        c = cat_by.get(asin) or {}
        urls = photos_by.get(asin) or []
        if not urls:
            # fallback ZIP 158 ficheiro local → urls https
            for ph in (photos158.get(asin) or {}).get("photos") or []:
                u = ph.get("url")
                if u and str(u).startswith("https://"):
                    urls.append(u)
        if not urls and c.get("primary_image_url"):
            urls = [c["primary_image_url"]]

        title = (c.get("title") or (e.get("llm") or {}).get("title") or "").strip()
        description = (
            c.get("description") or (e.get("llm") or {}).get("description") or ""
        ).strip()
        sale_condition = e.get("sale_condition") or map_state(
            None, j.get("ManifestCondition")
        )
        # normalizar sale_condition string do enrich
        if sale_condition in (
            "Danificado (armazém)",
            "Danificado (transporte)",
            "Danificado (cliente)",
            "Com defeito",
            "Novo",
        ):
            condition_label = sale_condition
        else:
            condition_label = sale_condition

        # Preço: suggested Amazon 50%; se falhar → 50% do retail do manifesto.
        price = c.get("suggested_sale_eur")
        if price is None and e.get("estado_preco") == "OK" and e.get("sugerido") is not None:
            price = e.get("sugerido")
        manifest_retail = None
        try:
            if j.get("ManifestRetail") not in (None, ""):
                manifest_retail = float(str(j["ManifestRetail"]).replace(",", "."))
        except (TypeError, ValueError):
            manifest_retail = None
        if price is None and manifest_retail is not None and manifest_retail > 0:
            price = round(manifest_retail / 2.0, 2)

        qty = int(j.get("Units") or 1)
        unit_lpns = [u.get("lpn") for u in units_by.get(asin, []) if u.get("lpn")]
        missing = []
        if not title:
            missing.append("titulo")
        if not urls:
            missing.append("fotografias")
        if price is None:
            missing.append("preco")
        if not unit_lpns:
            missing.append("lpn")

        out.append(
            {
                "asin": asin,
                "amazon_product_id": c.get("id"),
                "title": title,
                "description": description,
                "price": float(price) if price is not None else None,
                "price_source": (
                    "amazon_50pct"
                    if c.get("suggested_sale_eur") is not None
                    or (
                        e.get("estado_preco") == "OK"
                        and e.get("sugerido") is not None
                    )
                    else (
                        "manifest_retail_50pct"
                        if price is not None and manifest_retail is not None
                        else None
                    )
                ),
                "manifest_retail": manifest_retail,
                "amazon_price": j.get("AmazonPrice") or e.get("preco_amazon"),
                "qty": qty if qty >= 1 else 1,
                "lpns": unit_lpns,
                "condition_code": j.get("ManifestCondition") or e.get("condition_code"),
                "sale_condition": condition_label,
                "state": map_state(condition_label, j.get("ManifestCondition")),
                "category": guess_category(
                    title, (e.get("llm") or {}).get("hint") or ""
                ),
                "image_urls": urls[:8],
                "copy_status": c.get("copy_status") or (e.get("llm") or {}).get("copy_status"),
                "missing": missing,
                "ref_code": ref_code(asin),
            }
        )
    return out


def build_description(item: dict) -> str:
    parts = []
    if item["description"]:
        parts.append(item["description"].strip())
    meta = [
        f"ASIN: {item['asin']}",
        f"Estado manifesto: {item['sale_condition']}",
    ]
    if item["lpns"]:
        meta.append("LPN: " + ", ".join(item["lpns"]))
    else:
        meta.append("LPN: por associar (não constava no catálogo importado)")
    if item["amazon_price"] is not None:
        meta.append(f"Preço Amazon referência: {item['amazon_price']} €")
    if item["price"] is None:
        meta.append("Preço de venda: por confirmar")
    elif item.get("price_source") == "manifest_retail_50pct":
        meta.append(
            f"Preço de venda: {item['price']} € "
            f"(50% do retail manifesto {item.get('manifest_retail')} €)"
        )
    if item.get("copy_status") == "revision_needed":
        meta.append("Texto: revisão necessária (ZIP 157)")
    meta.append("Origem fotos: referência Amazon — direitos pendentes (rascunho interno)")
    parts.append("\n".join(meta))
    return "\n\n".join(parts).strip()


def upsert_draft(item: dict) -> dict:
    ref = item["ref_code"]
    existing = run_sql(
        f"""
select id, title, is_draft, list_on_marketplace, available_for_live, price,
       cardinality(image_urls) as n_imgs
from public.products
where seller_id = '{MARE_UID}'
  and ref_code = {dollar_quote(ref)}
limit 1;
"""
    )
    desc = build_description(item)
    title = item["title"] or f"ASIN {item['asin']} (sem título)"
    price_sql = "0" if item["price"] is None else str(float(item["price"]))
    imgs = sql_text_array(item["image_urls"])
    qty = int(item["qty"])

    if existing:
        pid = existing[0]["id"]
        # Actualizar só rascunhos ZIP159 — nunca anúncios publicados / não-draft
        if existing[0].get("is_draft") is not True:
            return {
                "asin": item["asin"],
                "status": "SKIP_EXISTING_PUBLISHED",
                "product_id": pid,
                "reason": "ref_code já existe e não é rascunho — não alterar",
                "edit_url": edit_url(pid),
                "missing": item["missing"],
            }
        run_sql(
            f"""
update public.products set
  title = {dollar_quote(title)},
  description = {dollar_quote(desc)},
  price = {price_sql}::numeric,
  image_urls = {imgs},
  category = {dollar_quote(item['category'])},
  state = {dollar_quote(item['state'])},
  quantity = {qty},
  is_draft = true,
  list_on_marketplace = false,
  available_for_live = false,
  is_sold = false
where id = '{pid}'
  and seller_id = '{MARE_UID}'
  and is_draft = true;
"""
        )
        status = "UPDATED"
    else:
        rows = run_sql(
            f"""
insert into public.products (
  seller_id, title, description, price, image_urls, category, state,
  ref_code, quantity, is_draft, list_on_marketplace, available_for_live, is_sold
) values (
  '{MARE_UID}',
  {dollar_quote(title)},
  {dollar_quote(desc)},
  {price_sql}::numeric,
  {imgs},
  {dollar_quote(item['category'])},
  {dollar_quote(item['state'])},
  {dollar_quote(ref)},
  {qty},
  true,
  false,
  false,
  false
)
returning id;
"""
        )
        pid = rows[0]["id"]
        status = "CREATED"

    # Ligação amazon → fleaber (idempotente)
    if item.get("amazon_product_id"):
        run_sql(
            f"""
insert into public.amazon_export_links (product_id, target, status, external_id, meta)
select
  {dollar_quote(item['amazon_product_id'])}::uuid,
  'fleaber_draft',
  'ok',
  {dollar_quote(pid)},
  jsonb_build_object(
    'asin', {dollar_quote(item['asin'])},
    'fleaber_product_id', {dollar_quote(pid)},
    'zip', '159',
    'seller', {dollar_quote(MARE_EMAIL)}
  )
where not exists (
  select 1 from public.amazon_export_links
  where product_id = {dollar_quote(item['amazon_product_id'])}::uuid
    and target = 'fleaber_draft'
    and external_id = {dollar_quote(pid)}
);
"""
        )

    return {
        "asin": item["asin"],
        "status": status,
        "product_id": pid,
        "ref_code": ref,
        "title": title,
        "price": item["price"],
        "state": item["state"],
        "category": item["category"],
        "qty": qty,
        "lpns": item["lpns"],
        "n_photos": len(item["image_urls"]),
        "missing": item["missing"],
        "copy_status": item.get("copy_status"),
        "edit_url": edit_url(pid),
        "is_draft": True,
        "list_on_marketplace": False,
        "available_for_live": False,
    }


def verify_privacy(product_ids: list[str]) -> dict:
    if not product_ids:
        return {"ok": False}
    quoted = ",".join("'" + p + "'" for p in product_ids)
    rows = run_sql(
        f"""
select id, seller_id, is_draft, list_on_marketplace, available_for_live, is_sold,
       cardinality(image_urls) as n_imgs, title, price, state, category, ref_code, quantity
from public.products
where id in ({quoted});
"""
    )
    pub = run_sql(
        f"""
select id from public.hub_products_public where id in ({quoted});
"""
    )
    return {
        "rows": rows,
        "in_public_hub": pub or [],
        "all_draft": all(r.get("is_draft") is True for r in (rows or [])),
        "none_marketplace": all(
            r.get("list_on_marketplace") is not True for r in (rows or [])
        ),
        "all_mare": all(r.get("seller_id") == MARE_UID for r in (rows or [])),
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # Confirmar conta
    users = run_sql(
        f"""
select id, email from auth.users where id = '{MARE_UID}' limit 1;
"""
    )
    if not users or users[0].get("email", "").lower() != MARE_EMAIL:
        raise SystemExit(f"Conta Mare Antiga não confirmada: {users}")

    items = load_sources()
    results = []
    for i, item in enumerate(items, 1):
        print(f"[{i}/15] {item['asin']} {item['title'][:50]}…")
        if "titulo" in item["missing"] or "fotografias" in item["missing"]:
            # Ainda criar rascunho se possível, mas marcar FAIL campos
            pass
        row = upsert_draft(item)
        print(
            f"  -> {row['status']} id={row.get('product_id')} "
            f"photos={row.get('n_photos')} missing={row.get('missing')}"
        )
        results.append(row)

    ids = [r["product_id"] for r in results if r.get("product_id")]
    verify = verify_privacy(ids)

    # Duplicados por ref?
    dups = run_sql(
        f"""
select ref_code, count(*)::int as n
from public.products
where seller_id = '{MARE_UID}'
  and ref_code like 'AMZ-%'
group by ref_code
having count(*) > 1;
"""
    )

    created = sum(1 for r in results if r["status"] == "CREATED")
    updated = sum(1 for r in results if r["status"] == "UPDATED")
    skipped = sum(1 for r in results if r["status"].startswith("SKIP"))
    with_photos = sum(1 for r in results if (r.get("n_photos") or 0) > 0)
    with_price = sum(1 for r in results if r.get("price") is not None)

    summary = {
        "seller_email": MARE_EMAIL,
        "seller_id": MARE_UID,
        "seller_handle": MARE_HANDLE,
        "n": len(results),
        "created": created,
        "updated": updated,
        "skipped": skipped,
        "with_photos": with_photos,
        "with_price": with_price,
        "duplicates": dups or [],
        "privacy": {
            "all_draft": verify.get("all_draft"),
            "none_marketplace": verify.get("none_marketplace"),
            "all_mare": verify.get("all_mare"),
            "in_public_hub_count": len(verify.get("in_public_hub") or []),
        },
        "drafts_list_url": drafts_list_url(),
        "hub_profile": f"{HUB_BASE}/{MARE_HANDLE}",
    }

    (OUT / "drafts_15.json").write_text(
        json.dumps({"summary": summary, "results": results, "verify": verify}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    (OUT / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        "# ZIP 159 — 15 rascunhos Mare Antiga",
        "",
        f"**Conta:** `{MARE_EMAIL}` · handle `{MARE_HANDLE}`",
        f"**Criados:** {created} · **Actualizados:** {updated} · **Skip:** {skipped}",
        f"**Com fotos:** {with_photos}/15 · **Com preço:** {with_price}/15",
        f"**Rascunhos privados:** is_draft=true · marketplace=false · live=false",
        f"**No Hub público:** {summary['privacy']['in_public_hub_count']} (deve ser 0)",
        f"**Duplicados AMZ-:** {len(dups or [])}",
        "",
        f"Lista rascunhos (app): {drafts_list_url()}",
        "",
        "| ASIN | Título | Preço | Estado | Fotos | Estado criação | Editar |",
        "|---|---|---:|---|---:|---|---|",
    ]
    for r in results:
        price = "—" if r.get("price") is None else f"{r['price']:.2f} €"
        miss = ",".join(r.get("missing") or []) or "—"
        lines.append(
            f"| `{r['asin']}` | {(r.get('title') or '')[:40]} | {price} | {r.get('state')} | "
            f"{r.get('n_photos')} | {r.get('status')} ({miss}) | [abrir]({r.get('edit_url')}) |"
        )
    lines += [
        "",
        "## Como ver",
        "",
        f"1. Entra em {HUB_BASE} com `{MARE_EMAIL}`.",
        "2. Vai a **Gestão de referências → Rascunhos** (ou usa os links «abrir» acima).",
        "3. Confirma fotos, título, descrição, preço, estado, quantidade e referência `AMZ-…`.",
        "",
        "## Campos em falta (não inventados)",
        "",
    ]
    for r in results:
        if r.get("missing"):
            lines.append(f"- `{r['asin']}`: {', '.join(r['missing'])}")
    if not any(r.get("missing") for r in results):
        lines.append("- (nenhum crítico além do esperado)")
    lines.append("")
    (OUT / "RELATORIO_ZIP159.md").write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print("Relatório:", OUT / "RELATORIO_ZIP159.md")


if __name__ == "__main__":
    main()
