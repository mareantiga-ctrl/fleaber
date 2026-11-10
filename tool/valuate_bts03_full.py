# -*- coding: utf-8 -*-
"""Avaliação completa BTS03 024 — pesquisa >20€ + estimativa resto."""
import csv
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

MANIFEST = Path(r"c:\Users\Casa\Downloads\a2zA2Z_CR_SK_20260709_BTS03_024.csv")
OUT = Path(__file__).parent / "reports" / "BTS03_024_avaliacao_completa.json"
OUT_CSV = Path(__file__).parent / "reports" / "BTS03_024_avaliacao_completa.csv"

# --- Dados pesquisados / conversa (novo real PT/EU, jul 2026) ---
# Chave = substring ASIN ou padrão no título (lower)
PESQUISA = {
    "b0gfddqvfq": {"novo": 140, "venda": 90, "liq": 5, "nota": "Lefant M330 Pro — Amazon ~130-140€"},
    "b0f4rbfhvz": {"novo": 290, "venda": 180, "liq": 4, "nota": "Lefant M3 + estação"},
    "b0dp6s7g4v": {"novo": 190, "venda": 140, "liq": 4, "nota": "Proscenic Q8 Max+ estação ~190€"},
    "b0d8w1434d": {"novo": 190, "venda": 140, "liq": 4, "nota": "Proscenic Q8 Max (2ª unidade)"},
    "b0djqdkrnp": {"novo": 150, "venda": 110, "liq": 4, "nota": "Proscenic Q8 sem estação"},
    "b0f26p4ft8": {"novo": 130, "venda": 100, "liq": 3, "nota": "Vexilar W9"},
    "b0dxfdz8qy": {"novo": 168, "venda": 100, "liq": 5, "nota": "Fissler Vitaquick 6L"},
    "b07jh4jhtc": {"novo": 115, "venda": 0, "pecas": 15, "liq": 4, "nota": "Fluval 307 — só peças se Defective"},
    "b09q3n98fb": {"novo": 120, "venda": 85, "liq": 4, "nota": "Nanoleaf Lines"},
    "b0bs1cx1lr": {"novo": 95, "venda": 60, "liq": 4, "nota": "Joseph Joseph Tota 90L"},
    "b0bzw7l66t": {"novo": 95, "venda": 70, "liq": 5, "nota": "Tempur Original Pillow"},
    "b09ql99gzr": {"novo": 253, "venda": 0, "pecas": 25, "liq": 3, "nota": "Sizzix Big Shot — peças"},
    "b09rq1wk9p": {"novo": 271, "venda": 190, "liq": 3, "nota": "Reschimica silicone 10kg"},
    "b0bn6pbgfd": {"novo": 45, "venda": 18, "liq": 2, "nota": "Excelsa Jaipur pratos — lento"},
    "b0fkbc k3vp": {"novo": 55, "venda": 30, "liq": 3, "nota": "unipaws cadeira cão"},
    "b0g7zbtbt3": {"novo": 65, "venda": 28, "liq": 2, "nota": "Bollerwagen carrinho"},
    "b07drj24vz": {"novo": 55, "venda": 0, "pecas": 8, "liq": 2, "nota": "Kerbl porta galinhas — nicho"},
    "b0721g1qkn": {"novo": 75, "venda": 0, "pecas": 12, "liq": 3, "nota": "Paulmann Zigbee panel"},
    "b08czvyjh1": {"novo": 70, "venda": 0, "pecas": 10, "liq": 4, "nota": "Philips Hue E14 2x"},
    "b08mqhw3bx": {"novo": 70, "venda": 40, "liq": 4, "nota": "Rotho Albula"},
    "b00o4bigwa": {"novo": 70, "venda": 45, "liq": 3, "nota": "Advance Veterinary Diet 12kg"},
    "b09zkfk4jd": {"novo": 65, "venda": 40, "liq": 3, "nota": "DreamyBlue pillow"},
    "b088s22w3q": {"novo": 65, "venda": 0, "pecas": 8, "liq": 3, "nota": "Philips Hue Buckram"},
    "b07d1f6l13": {"novo": 45, "venda": 22, "liq": 2, "nota": "Uniestor estore"},
    "b0f3jf1ybr": {"novo": 55, "venda": 40, "liq": 5, "nota": "Vileda H2PrO"},
    "b07xgcdmf4": {"novo": 45, "venda": 0, "pecas": 5, "liq": 2, "nota": "Blindecor estore"},
    "b0byyrvvc5": {"novo": 50, "venda": 30, "liq": 3, "nota": "BDFFLY TV backlight"},
    "b0dq8bdt9z": {"novo": 50, "venda": 0, "pecas": 5, "liq": 1, "nota": "Novilla surmatelas"},
    "b07v5cm1dw": {"novo": 90, "venda": 55, "liq": 5, "nota": "Philips Hue White Color 2x"},
    "b088rynq1v": {"novo": 43, "venda": 0, "pecas": 8, "liq": 3, "nota": "Philips Hue Milliskin"},
}

# Conversa 1-110 por índice (fallback quando ASIN não bate)
from build_bts03_table import CONVERSATION, CONV_ESTADO

FUNC = {"pessimista": 0.40, "realista": 0.60, "otimista": 0.70}
CUSTO_LOTE = 1650


def norm(s):
    return (s or "").lower().strip()


def lookup_pesquisa(row):
    asin = norm(row.get("ASIN"))
    desc = norm(row.get("Item Desc"))
    for k, v in PESQUISA.items():
        if k.replace(" ", "") in asin or k in desc:
            return dict(v)
    return None


def categoria_lenta(desc):
    d = norm(desc)
    slow = [
        "store", "estore", "rollo", "cortina", "curtain", "poster", "quadro", "canvas",
        "wandlampe", "deckenleuchte", "plafon", "candeeiro", "light", "lichter",
        "manteles", "colcha", "bettlaken", "tapete", "rug", "mat",
        "deco", "moldura", "shadow box", "teller", "plate",
    ]
    return any(x in d for x in slow)


def categoria_rapida(desc):
    d = norm(desc)
    fast = [
        "hue", "philips", "purina", "ultima", "sheba", "trixie", "kerbl", "fissler",
        "joseph joseph", "bialetti", "brita", "sodastream", "vileda", "tempur",
        "robot", "aspir", "proscenic", "lefant", "nanoleaf", "rotho", "wenko",
        "pet", "hund", "gato", "chat", "dog", "cat",
    ]
    return any(x in d for x in fast)


def estimate_novo(pvp, desc, cond):
    """Estimativa conservadora novo real quando sem pesquisa."""
    d = norm(desc)
    # Robots / floorcare
    if any(x in d for x in ["robot", "aspirateur", "aspirador", "aspirapolvere", "vacuum"]):
        return round(pvp * 0.42, 0)
    if any(x in d for x in ["hue", "nanoleaf"]):
        return round(pvp * 1.0, 0)  # preço manifesto próximo do real
    if pvp >= 80:
        return round(pvp * 0.75, 0)
    if pvp >= 40:
        return round(pvp * 0.80, 0)
    if pvp >= 20:
        return round(pvp * 0.85, 0)
    return round(pvp * 0.70, 0)


def estimate_venda(novo, desc, cond, pecas=None):
    if cond == "Defective":
        return 0
    if pecas and novo >= 80:
        return 0
    if novo <= 20:
        base = 0.32 if categoria_lenta(desc) else 0.38
        return max(4, round(novo * base, 0))
    if novo <= 50:
        base = 0.38 if categoria_lenta(desc) else 0.50
        return round(novo * base, 0)
    if categoria_rapida(desc):
        return round(novo * 0.58, 0)
    return round(novo * 0.48, 0)


def estimate_pecas(novo, desc, cond):
    if cond != "Defective":
        return 0
    if novo < 50:
        return 0
    d = norm(desc)
    if any(x in d for x in ["robot", "aspir", "fluval", "filter", "hue", "philips", "sizzix"]):
        return round(min(25, novo * 0.12), 0)
    if novo >= 80:
        return 8
    if novo >= 50:
        return 5
    return 0


def valor_artigo(novo, venda, pecas, cond):
    is_def = cond == "Defective"
    if is_def:
        return {"pecas": pecas, "venda": 0, "novo_nd": 0}
    return {"pecas": 0, "venda": venda or 0, "novo_nd": novo}


def main():
    rows = list(csv.DictReader(open(MANIFEST, encoding="utf-8")))
    out = []
    tot = {k: 0 for k in ["pvp", "novo", "novo_nd", "venda", "pecas"]}
    pesquisados = estimados = 0

    for i, m in enumerate(rows, 1):
        pvp = float(m["UNIT RETAIL"])
        cond = m["CONDITION"]
        desc = m["Item Desc"]
        asin = m.get("ASIN", "")

        pesq = lookup_pesquisa(m)
        conv = CONVERSATION[i - 1] if i <= len(CONVERSATION) else None

        fonte = "estimativa"
        nota = ""

        if pesq:
            novo = pesq["novo"]
            venda = pesq.get("venda", 0)
            pecas = pesq.get("pecas", 0)
            if cond == "Defective" and not pesq.get("pecas"):
                pecas = estimate_pecas(novo, desc, cond)
                venda = 0
            fonte = "pesquisa"
            nota = pesq.get("nota", "")
            pesquisados += 1
        elif conv and i <= 110:
            novo = conv["novo"]
            venda = conv["venda"] or 0
            pecas = conv["pecas"] or 0
            if CONV_ESTADO[i - 1] == "Defective" or cond == "Defective":
                if novo < 50:
                    pecas = 0
                venda = 0
            fonte = "conversa"
            pesquisados += 1
        else:
            novo = estimate_novo(pvp, desc, cond)
            pecas = estimate_pecas(novo, desc, cond)
            venda = estimate_venda(novo, desc, cond, pecas)
            fonte = "estimativa"
            estimados += 1
            nota = "regra PVP/categoria"

        if cond == "Defective":
            venda = 0
            if novo < 50:
                pecas = min(pecas, 0)  # regra combinada

        tot["pvp"] += pvp
        tot["novo"] += novo
        if cond != "Defective":
            tot["novo_nd"] += novo
            tot["venda"] += venda
        tot["pecas"] += pecas

        out.append({
            "#": i,
            "artigo": desc[:70],
            "estado": cond,
            "pvp": pvp,
            "novo": novo,
            "venda_rapida": venda,
            "pecas": pecas,
            "fonte": fonte,
            "nota": nota,
        })

    receitas = {k: round(tot["venda"] * FUNC[k] + tot["pecas"], 2) for k in FUNC}
    margens = {k: round(receitas[k] - CUSTO_LOTE, 2) for k in FUNC}
    roi = {k: round((receitas[k] / CUSTO_LOTE - 1) * 100, 1) for k in FUNC}

    defective = sum(1 for r in out if r["estado"] == "Defective")
    over20 = sum(1 for r in out if r["pvp"] > 20)

    summary = {
        "lote": "A2zA2Z CR SK 20260709 BTS03 024",
        "custo_comprado": CUSTO_LOTE,
        "artigos": len(out),
        "defective": defective,
        "pvp_total": round(tot["pvp"], 2),
        "novo_real_total": round(tot["novo"], 2),
        "novo_nao_defective": round(tot["novo_nd"], 2),
        "venda_rapida_se_bons": round(tot["venda"], 2),
        "pecas_total": round(tot["pecas"], 2),
        "pesquisados_ou_conversa": pesquisados,
        "estimados": estimados,
        "receitas": receitas,
        "margem_vs_1650": margens,
        "roi_pct": roi,
        "metodo": "Defective=peças; restantes: venda_rapida×40/60/70% + peças",
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"summary": summary, "items": out}, f, ensure_ascii=False, indent=2)

    fields = ["#", "artigo", "estado", "pvp", "novo", "venda_rapida", "pecas", "fonte", "nota"]
    with open(OUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(out)
        f.write("\n")
        for label, key in [
            ("CUSTO LOTE (com portes)", CUSTO_LOTE),
            ("PVP manifesto total", summary["pvp_total"]),
            ("Novo real estimado total", summary["novo_real_total"]),
            ("Venda rápida (todos bons)", summary["venda_rapida_se_bons"]),
            ("Peças", summary["pecas_total"]),
            ("Receita PESSIMISTA", receitas["pessimista"]),
            ("Receita REALISTA", receitas["realista"]),
            ("Receita OTIMISTA", receitas["otimista"]),
            ("Margem REALISTA vs 1650", margens["realista"]),
        ]:
            w.writerow({"#": label, "artigo": key})

    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
