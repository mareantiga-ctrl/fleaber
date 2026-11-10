"""Build consolidated BTS03 024 analysis table from conversation data + manifest CSV."""
import csv
import json
from pathlib import Path

MANIFEST = Path(r"c:\Users\Casa\Downloads\a2zA2Z_CR_SK_20260709_BTS03_024.csv")
OUT_CSV = Path(__file__).parent / "reports" / "BTS03_024_analise_conversa.csv"
OUT_PURA = Path(__file__).parent / "reports" / "BTS03_024_tabela_conversa_110.csv"
OUT_JSON = Path(__file__).parent / "reports" / "BTS03_024_analise_conversa.json"

# Estado conforme análise na conversa (não manifesto) — artigos 1-110
CONV_ESTADO = [
    "Carrier", "Customer", "Customer", "Customer", "Defective", "Customer", "Customer", "Customer", "Defective", "Warehouse",
    "Defective", "Customer", "Warehouse", "Carrier", "Customer", "Customer", "Customer", "Warehouse", "Customer", "Warehouse",
    "Customer", "Customer", "Customer", "Customer", "Customer", "Customer", "Customer", "Customer", "Customer", "Customer",
    "Warehouse", "Carrier", "Carrier", "Customer", "Carrier", "Carrier", "Carrier", "Carrier", "Customer", "Defective",
    "Warehouse", "Defective", "Customer", "Customer", "Carrier", "Carrier", "Defective", "Carrier", "Customer", "Warehouse",
    "Warehouse", "Defective", "Carrier", "Defective", "Customer", "Customer", "Defective", "Carrier", "Defective", "Carrier",
    "Customer", "Warehouse", "Customer", "Customer", "Customer", "Carrier", "Warehouse", "Customer", "Customer", "Carrier",
    "Customer", "Warehouse", "Carrier", "Customer", "Customer", "Warehouse", "Carrier", "Customer", "Customer", "Warehouse",
    "Customer", "Warehouse", "Customer", "Customer", "Customer", "Customer", "Customer", "Warehouse", "Customer", "Customer",
    "Carrier", "Defective", "Customer", "Carrier", "Carrier", "Customer", "Customer", "Customer", "Customer", "Carrier",
    "Customer", "Carrier", "Customer", "Customer", "Customer", "Carrier", "Customer", "Defective", "Defective", "Carrier",
]

# Analysis from conversation (items 1-110). Keys: artigo_curto, novo, usado, venda_rapida, pecas, liquidez
# pecas = valor já contabilizado (metade do potencial, quando aplicável)
CONVERSATION = [
    {"artigo": "Lefant M330 Pro", "novo": 220, "usado": "80-100", "venda": 90, "pecas": None, "liq": 5},
    {"artigo": "Lefant M3 + Base", "novo": 290, "usado": "170-200", "venda": 180, "pecas": None, "liq": 4},
    {"artigo": "Proscenic Q8 Max + Estação", "novo": 190, "usado": "130-150", "venda": 140, "pecas": None, "liq": 4},
    {"artigo": "Reschimica Silicone 10 kg", "novo": 271, "usado": "180-220", "venda": 190, "pecas": None, "liq": 3},
    {"artigo": "Sizzix Big Shot Switch Plus", "novo": 253, "usado": None, "venda": None, "pecas": 25, "liq": 3},
    {"artigo": "Proscenic Q8 Max + Estação (2)", "novo": 190, "usado": "130-150", "venda": 140, "pecas": None, "liq": 4},
    {"artigo": "Proscenic Q8 (sem estação)", "novo": 150, "usado": "90-120", "venda": 110, "pecas": None, "liq": 4},
    {"artigo": "Vexilar W9", "novo": 129, "usado": "90-110", "venda": 100, "pecas": None, "liq": 3},
    {"artigo": "Vexilar W9 (Defective)", "novo": 129, "usado": None, "venda": None, "pecas": 15, "liq": 2},
    {"artigo": "Fissler Vitaquick 6L", "novo": 168, "usado": "90-120", "venda": 100, "pecas": None, "liq": 5},
    {"artigo": "Fluval 307 Filtro Externo", "novo": 115, "usado": None, "venda": None, "pecas": 15, "liq": 4},
    {"artigo": "Nanoleaf Lines Starter Kit", "novo": 120, "usado": "75-95", "venda": 85, "pecas": None, "liq": 4},
    {"artigo": "LED Wall Light 150 cm", "novo": 90, "usado": "40-60", "venda": 50, "pecas": None, "liq": 2},
    {"artigo": "TUKA A1 Poster Stand", "novo": 95, "usado": "45-60", "venda": 55, "pecas": None, "liq": 2},
    {"artigo": "Joseph Joseph Tota 90L", "novo": 95, "usado": "55-70", "venda": 60, "pecas": None, "liq": 4},
    {"artigo": "Tempur Original Pillow", "novo": 95, "usado": "60-80", "venda": 70, "pecas": None, "liq": 5},
    {"artigo": "Joseph Joseph Surface", "novo": 24, "usado": "12-18", "venda": 15, "pecas": None, "liq": 4},
    {"artigo": "Fissler utensílio cozinha", "novo": 85, "usado": "45-60", "venda": 50, "pecas": None, "liq": 4},
    {"artigo": "Fluval Aquário", "novo": 90, "usado": "45-60", "venda": 55, "pecas": None, "liq": 4},
    {"artigo": "Candeeiro Exterior LED", "novo": 80, "usado": "35-50", "venda": 40, "pecas": None, "liq": 2},
    {"artigo": "Paulmann Zigbee LED Panel", "novo": 75, "usado": "40-50", "venda": 45, "pecas": None, "liq": 3},
    {"artigo": "Philips Hue E14 (2x)", "novo": 70, "usado": "40-50", "venda": 45, "pecas": None, "liq": 5},
    {"artigo": "Rotho Albula Reciclagem", "novo": 70, "usado": "35-45", "venda": 40, "pecas": None, "liq": 4},
    {"artigo": "Advance Veterinary Diet", "novo": 70, "usado": "40-50", "venda": 45, "pecas": None, "liq": 3},
    {"artigo": "DreamyBlue Pillow", "novo": 65, "usado": "35-45", "venda": 40, "pecas": None, "liq": 3},
    {"artigo": "Philips Hue Buckram Spot", "novo": 65, "usado": "40-50", "venda": 45, "pecas": None, "liq": 5},
    {"artigo": "Uniestor Estore", "novo": 60, "usado": "25-35", "venda": 30, "pecas": None, "liq": 2},
    {"artigo": "Luzes LED Exterior 60 m", "novo": 60, "usado": "30-40", "venda": 35, "pecas": None, "liq": 3},
    {"artigo": "Cecotec Ventoinha Teto", "novo": 60, "usado": "35-45", "venda": 40, "pecas": None, "liq": 3},
    {"artigo": "OUILA Plafonnier LED", "novo": 60, "usado": "30-40", "venda": 35, "pecas": None, "liq": 2},
    {"artigo": "Kare Canvas Wall Art 93×63", "novo": 61, "usado": "35-45", "venda": 40, "pecas": None, "liq": 2},
    {"artigo": "Almofada leitura SOOYUZXXED", "novo": 61, "usado": "30-40", "venda": 35, "pecas": None, "liq": 3},
    {"artigo": "Painel LED 120×30 44W", "novo": 57, "usado": "30-40", "venda": 35, "pecas": None, "liq": 3},
    {"artigo": "Paulmann 79718", "novo": 57, "usado": "35-45", "venda": 40, "pecas": None, "liq": 4},
    {"artigo": "Ultima Gato Esterilizado 8×1,5 kg", "novo": 56, "usado": "35-45", "venda": 40, "pecas": None, "liq": 4},
    {"artigo": "The Hunger of the Wolf 14 kg", "novo": 55, "usado": "35-45", "venda": 40, "pecas": None, "liq": 4},
    {"artigo": "Candeeiro LED Ø60 cm", "novo": 55, "usado": "30-40", "venda": 35, "pecas": None, "liq": 3},
    {"artigo": "Ultima Gato Peru 8×1,5 kg", "novo": 55, "usado": "35-45", "venda": 40, "pecas": None, "liq": 4},
    {"artigo": "Vileda H2PrO Mop", "novo": 55, "usado": "35-45", "venda": 40, "pecas": None, "liq": 5},
    {"artigo": "Blindecor Zebra Rolo", "novo": 53, "usado": None, "venda": None, "pecas": 10, "liq": 2},
    {"artigo": "BDFFLY TV LED Backlight HDMI", "novo": 50, "usado": "25-35", "venda": 30, "pecas": None, "liq": 3},
    {"artigo": "Novilla Surmatelas Cooling 160×200", "novo": 50, "usado": None, "venda": None, "pecas": 5, "liq": 1},
    {"artigo": "Amig Estendal mural", "novo": 47, "usado": "25-35", "venda": 30, "pecas": None, "liq": 3},
    {"artigo": "Philips Hue White & Color (2)", "novo": 47, "usado": "30-40", "venda": 35, "pecas": None, "liq": 5},
    {"artigo": "Nature's Variety Gato 7 kg", "novo": 44, "usado": "28-35", "venda": 30, "pecas": None, "liq": 4},
    {"artigo": "Barra cortina duche L/U", "novo": 44, "usado": "20-30", "venda": 25, "pecas": None, "liq": 2},
    {"artigo": "Philips Hue Milliskin Spot", "novo": 43, "usado": None, "venda": None, "pecas": 8, "liq": 3},
    {"artigo": "EHEYCIGA Cama Ortopédica XL", "novo": 43, "usado": "25-35", "venda": 30, "pecas": None, "liq": 4},
    {"artigo": "SOCONT Caixote lixo extraível", "novo": 42, "usado": "25-35", "venda": 30, "pecas": None, "liq": 3},
    {"artigo": "Relógio LED Digital XREXS 16,5\"", "novo": 41, "usado": "20-30", "venda": 25, "pecas": None, "liq": 3},
    {"artigo": "WENKO Poubelle porte 12L", "novo": 40, "usado": "20-30", "venda": 25, "pecas": None, "liq": 4},
    {"artigo": "VOUNOT Carrinho Compras 6 rodas", "novo": 40, "usado": None, "venda": None, "pecas": 8, "liq": 2},
    {"artigo": "Cadeira Auto para Cão", "novo": 40, "usado": "20-30", "venda": 25, "pecas": None, "liq": 4},
    {"artigo": "Lucky Reptile Bright Sun UV 50W", "novo": 40, "usado": None, "venda": None, "pecas": 5, "liq": 2},
    {"artigo": "Kerbl Paola Eco Casa Gato", "novo": 39, "usado": "22-30", "venda": 25, "pecas": None, "liq": 4},
    {"artigo": "BedStory Topper 120×200", "novo": 39, "usado": "22-30", "venda": 25, "pecas": None, "liq": 3},
    {"artigo": "Candeeiro Sputnik Vintage 6 Luzes", "novo": 39, "usado": None, "venda": None, "pecas": 8, "liq": 2},
    {"artigo": "Sheba Creamy Snacks 11×4", "novo": 39, "usado": "22-30", "venda": 25, "pecas": None, "liq": 5},
    {"artigo": "Fitop Alexa GU10 RGB (2)", "novo": 38, "usado": None, "venda": None, "pecas": 5, "liq": 3},
    {"artigo": "INTERBLIND Estore Opaco 140×175", "novo": 38, "usado": "20-28", "venda": 24, "pecas": None, "liq": 2},
    {"artigo": "Relaxdays Caixa Arrumação", "novo": 38, "usado": "20-28", "venda": 24, "pecas": None, "liq": 3},
    {"artigo": "Amazon Basics Blackout Curtain", "novo": 38, "usado": "20-28", "venda": 24, "pecas": None, "liq": 3},
    {"artigo": "Trixie Cama Cão XL", "novo": 37, "usado": "22-30", "venda": 25, "pecas": None, "liq": 4},
    {"artigo": "Lâmpada LED WiFi Pack", "novo": 37, "usado": "22-30", "venda": 25, "pecas": None, "liq": 3},
    {"artigo": "Escorredor Joseph Joseph", "novo": 36, "usado": "20-28", "venda": 24, "pecas": None, "liq": 4},
    {"artigo": "Almofada Viscoelástica BedStory", "novo": 36, "usado": "20-28", "venda": 24, "pecas": None, "liq": 3},
    {"artigo": "Candeeiro Pé LED Moderno", "novo": 36, "usado": "18-25", "venda": 22, "pecas": None, "liq": 2},
    {"artigo": "Purina Pro Plan Veterinary Diet", "novo": 35, "usado": "20-28", "venda": 24, "pecas": None, "liq": 4},
    {"artigo": "Suporte TV Universal", "novo": 35, "usado": "18-25", "venda": 22, "pecas": None, "liq": 4},
    {"artigo": "Tapete Absorvente Animal XL", "novo": 35, "usado": "18-25", "venda": 22, "pecas": None, "liq": 3},
    {"artigo": "Amazon Basics Tapete Entrada", "novo": 35, "usado": "15-22", "venda": 18, "pecas": None, "liq": 4},
    {"artigo": "WENKO Organizador Casa Banho", "novo": 35, "usado": "15-22", "venda": 18, "pecas": None, "liq": 3},
    {"artigo": "Cecotec Aquecedor Cerâmico", "novo": 34, "usado": "18-25", "venda": 20, "pecas": None, "liq": 4},
    {"artigo": "Purina Pro Plan Medium", "novo": 34, "usado": "18-24", "venda": 20, "pecas": None, "liq": 4},
    {"artigo": "Candeeiro Mesa LED Touch", "novo": 34, "usado": "15-22", "venda": 18, "pecas": None, "liq": 3},
    {"artigo": "Suporte Monitor Ajustável", "novo": 33, "usado": "18-24", "venda": 20, "pecas": None, "liq": 4},
    {"artigo": "Caixa Arrumação XXL", "novo": 33, "usado": "15-22", "venda": 18, "pecas": None, "liq": 3},
    {"artigo": "Tapete Cozinha Antiderrapante", "novo": 32, "usado": "15-20", "venda": 17, "pecas": None, "liq": 3},
    {"artigo": "Escova Elétrica Animal", "novo": 32, "usado": "16-22", "venda": 18, "pecas": None, "liq": 4},
    {"artigo": "Cesto Roupa Dobrável", "novo": 32, "usado": "15-20", "venda": 17, "pecas": None, "liq": 3},
    {"artigo": "BRITA On Tap Pro V-MF", "novo": 29, "usado": "15-20", "venda": 16, "pecas": None, "liq": 4},
    {"artigo": "Amazon Basics Resguardos Treino", "novo": 28, "usado": "12-18", "venda": 14, "pecas": None, "liq": 4},
    {"artigo": "NITYAM SMART Pack 5 LED Wi-Fi", "novo": 28, "usado": "12-18", "venda": 14, "pecas": None, "liq": 3},
    {"artigo": "Bialetti Moka Express", "novo": 28, "usado": "15-20", "venda": 16, "pecas": None, "liq": 5},
    {"artigo": "Hunter Aalborg Coleira Pele", "novo": 28, "usado": "14-18", "venda": 15, "pecas": None, "liq": 4},
    {"artigo": "QISF Sacos Reutilizáveis Zip", "novo": 27, "usado": "10-15", "venda": 12, "pecas": None, "liq": 3},
    {"artigo": "DMC Nuancier Fios Bordar", "novo": 27, "usado": "15-20", "venda": 16, "pecas": None, "liq": 4},
    {"artigo": "Rotho Paso Caixote 20 L", "novo": 27, "usado": "12-18", "venda": 14, "pecas": None, "liq": 4},
    {"artigo": "SANSI Lâmpada LED Plantas 15W", "novo": 27, "usado": "14-18", "venda": 15, "pecas": None, "liq": 4},
    {"artigo": "lionto Comedouro Elevado Cão", "novo": 27, "usado": "12-18", "venda": 14, "pecas": None, "liq": 4},
    {"artigo": "Rimwig Capa Baloiço Jardim 3L", "novo": 27, "usado": "12-18", "venda": 14, "pecas": None, "liq": 3},
    {"artigo": "Decora Aro Retangular Inox", "novo": 26, "usado": None, "venda": 0, "pecas": None, "liq": 1},
    {"artigo": "Smartday Organizador Secretária", "novo": 26, "usado": "12-18", "venda": 14, "pecas": None, "liq": 3},
    {"artigo": "EHEYCIGA Escadas Cão/Gato", "novo": 26, "usado": "14-18", "venda": 15, "pecas": None, "liq": 4},
    {"artigo": "Spiretro Shadow Box Moldura", "novo": 26, "usado": "12-18", "venda": 14, "pecas": None, "liq": 2},
    {"artigo": "BWT Cartuchos Magnésio 5+1", "novo": 26, "usado": "15-20", "venda": 16, "pecas": None, "liq": 5},
    {"artigo": "WENKO Copo Escovas Bosio", "novo": 26, "usado": "12-18", "venda": 14, "pecas": None, "liq": 3},
    {"artigo": "Bresser Relógio Rádio Thermo", "novo": 25, "usado": "14-18", "venda": 15, "pecas": None, "liq": 4},
    {"artigo": "lionto Cama Cão 4 em 1", "novo": 25, "usado": "14-18", "venda": 15, "pecas": None, "liq": 4},
    {"artigo": "ICQN Grelha Universal Forno", "novo": 25, "usado": "12-18", "venda": 14, "pecas": None, "liq": 4},
    {"artigo": "Adler Afiador Facas CR4469", "novo": 25, "usado": "10-15", "venda": 10, "pecas": None, "liq": 3},
    {"artigo": "EHEYCIGA Cama Ortopédica Grande", "novo": 24, "usado": "10-15", "venda": 10, "pecas": None, "liq": 4},
    {"artigo": "Harry Potter Bookends 9¾", "novo": 24, "usado": "10-15", "venda": 10, "pecas": None, "liq": 4},
    {"artigo": "Drink Pod Caneca Térmica 280ml", "novo": 24, "usado": "8-12", "venda": 9, "pecas": None, "liq": 3},
    {"artigo": "BAKAJI Candeeiro de Pé", "novo": 24, "usado": "8-12", "venda": 8, "pecas": None, "liq": 2},
    {"artigo": "OSRAM LED Tube T9 Circular", "novo": 24, "usado": "10-14", "venda": 10, "pecas": None, "liq": 4},
    {"artigo": "SodaStream Fizz & Go Garrafa", "novo": 24, "usado": "10-15", "venda": 10, "pecas": None, "liq": 4},
    {"artigo": "Hydro Flask 354 ml", "novo": 24, "usado": None, "venda": 0, "pecas": None, "liq": 3},
    {"artigo": "IBILI Tampa Inox 37 cm", "novo": 24, "usado": None, "venda": 0, "pecas": None, "liq": 2},
    {"artigo": "LAYNENBURG Colcha 150×200", "novo": 23, "usado": "8-12", "venda": 8, "pecas": None, "liq": 3},
]

METHOD = {
    "defective_pecas_rule": "Artigos Defective caros (>80€): valor peças conservador × 50%. Defective baratos (<50€ novo): 0€ peças a partir art.60",
    "funcional_rates": {
        "pessimista": {"func_pct": 0.40, "venda_pct": 0.30},
        "realista": {"func_pct": 0.60, "venda_pct": 0.45},
        "otimista": {"func_pct": 0.70, "venda_pct": 0.60},
    },
    "venda_rapida_rule": "Artigos baratos: max 40% valor novo; rotação lenta ainda menos",
}


def short_desc(desc: str, max_len: int = 55) -> str:
    return desc[:max_len].strip()


def stars(n: int) -> str:
    return "★" * n if n else ""


def main():
    with open(MANIFEST, encoding="utf-8") as f:
        manifest = list(csv.DictReader(f))

    rows_out = []
    total_novo = 0.0
    total_pecas = 0.0
    total_venda_rapida = 0.0

    for i, m in enumerate(manifest, 1):
        cond_manifest = m["CONDITION"]
        cond_conv = CONV_ESTADO[i - 1] if i <= len(CONVERSATION) else ""
        pvp = float(m["UNIT RETAIL"])
        conv = CONVERSATION[i - 1] if i <= len(CONVERSATION) else None

        if conv:
            novo = conv["novo"]
            usado = conv["usado"] or ""
            venda = conv["venda"]
            pecas = conv["pecas"] or 0
            liq = conv["liq"]
            artigo = conv["artigo"]
            estado = cond_conv
            fonte = "conversa"
        else:
            novo = None
            usado = ""
            venda = None
            pecas = 0
            liq = None
            artigo = short_desc(m["Item Desc"])
            estado = cond_manifest
            fonte = "pendente"

        is_def = estado.strip().lower() == "defective"
        if novo is not None:
            total_novo += novo
        if pecas:
            total_pecas += pecas
        if venda and not is_def:
            total_venda_rapida += venda

        rows_out.append({
            "#": i,
            "Artigo (conversa)": artigo,
            "Descrição manifesto": short_desc(m["Item Desc"], 80),
            "Estado (conversa)": estado if fonte == "conversa" else "",
            "Estado (manifesto)": cond_manifest,
            "PVP manifesto (€)": pvp,
            "Novo real (€)": novo if novo is not None else "",
            "Usado (€)": usado,
            "Venda rápida (€)": venda if venda is not None else (0 if is_def else ""),
            "Peças contab. (€)": pecas if pecas else (0 if is_def else ""),
            "Liquidez": stars(liq) if liq else "",
            "Fonte análise": fonte,
        })

    # Totais cumulativos da conversa: venda_rapida × %funcional + peças
    # (venda_rapida já incorpora o preço de venda conservador)
    analyzed = [r for r in rows_out if r["Fonte análise"] == "conversa"]
    novo_all = sum(r["Novo real (€)"] for r in analyzed)
    novo_nd = sum(
        r["Novo real (€)"] for r in analyzed if r["Estado (conversa)"] != "Defective"
    )
    pecas_sum = sum(r["Peças contab. (€)"] or 0 for r in analyzed)
    venda_sum = sum(
        r["Venda rápida (€)"] or 0
        for r in analyzed
        if r["Estado (conversa)"] != "Defective"
    )

    # Totais da conversa (recalculados a partir dos dados capturados)
    conv_novo = sum(c["novo"] for c in CONVERSATION)
    conv_pecas = sum(c["pecas"] or 0 for c in CONVERSATION)
    conv_venda = sum(
        c["venda"] or 0
        for i, c in enumerate(CONVERSATION)
        if CONV_ESTADO[i] != "Defective"
    )
    conv_scenarios = {
        k: round(conv_venda * METHOD["funcional_rates"][k]["func_pct"] + conv_pecas, 2)
        for k in METHOD["funcional_rates"]
    }

    summary = {
        "lote": "A2zA2Z CR SK 20260709 BTS03 024",
        "total_artigos_manifesto": len(manifest),
        "artigos_analisados_conversa": len(analyzed),
        "pvp_manifesto_total": round(sum(float(m["UNIT RETAIL"]) for m in manifest), 2),
        "valor_novo_real_1_110": round(novo_all, 2),
        "valor_novo_real_nao_defective_1_110": round(novo_nd, 2),
        "pecas_contabilizadas_1_110": pecas_sum,
        "venda_rapida_se_todos_bons_1_110": round(venda_sum, 2),
        "receita_prevista_1_110": conv_scenarios,
        "receita_conversa_declarada_1_110": {
            "pessimista": 1596,
            "realista": 2342,
            "otimista": 2715,
        },
        "metodo": METHOD,
    }

    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(rows_out[0].keys())
    with open(OUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows_out)
        # summary rows
        f.write("\n")
        w.writerow({fieldnames[0]: "TOTAIS (1-110 analisados)"})
        w.writerow({"#": "Métrica", "Artigo (conversa)": "Valor"})
        w.writerow({"#": "Artigos manifesto", "Artigo (conversa)": len(manifest)})
        w.writerow({"#": "PVP manifesto total", "Artigo (conversa)": summary["pvp_manifesto_total"]})
        w.writerow({"#": "Novo real não-Defective", "Artigo (conversa)": summary["valor_novo_real_nao_defective_1_110"]})
        w.writerow({"#": "Peças contabilizadas", "Artigo (conversa)": summary["pecas_contabilizadas_1_110"]})
        w.writerow({"#": "Venda rápida (todos bons)", "Artigo (conversa)": summary["venda_rapida_se_todos_bons_1_110"]})
        for k, v in conv_scenarios.items():
            w.writerow({"#": f"Receita {k} (recalc)", "Artigo (conversa)": v})
        w.writerow({"#": "Receita realista (conversa)", "Artigo (conversa)": 2342})

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump({"summary": summary, "rows": rows_out}, f, ensure_ascii=False, indent=2)

    # Tabela pura da conversa (1-110) — formato acordado
    pura_rows = []
    for i, c in enumerate(CONVERSATION, 1):
        pura_rows.append({
            "#": i,
            "Artigo": c["artigo"],
            "Estado": CONV_ESTADO[i - 1],
            "Novo (€)": c["novo"],
            "Usado (€)": c["usado"] or "",
            "Venda rápida (€)": c["venda"] if c["venda"] is not None else "",
            "Peças (€)": c["pecas"] or "",
            "Liquidez": stars(c["liq"]),
        })
    pura_fields = list(pura_rows[0].keys())
    with open(OUT_PURA, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=pura_fields)
        w.writeheader()
        w.writerows(pura_rows)
        f.write("\n")
        w.writerow({"#": "TOTAIS", "Artigo": "1-110 conversa"})
        w.writerow({"#": "Novo real total", "Artigo": round(conv_novo, 2)})
        w.writerow({"#": "Peças contabilizadas", "Artigo": conv_pecas})
        w.writerow({"#": "Venda rápida (todos bons)", "Artigo": round(conv_venda, 2)})
        for k, v in conv_scenarios.items():
            w.writerow({"#": f"Receita {k}", "Artigo": v})

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"\nCSV manifesto+conversa: {OUT_CSV}")
    print(f"CSV conversa pura 1-110: {OUT_PURA}")
    print(f"JSON: {OUT_JSON}")


if __name__ == "__main__":
    main()
