# -*- coding: utf-8 -*-
"""
BTS03 024 — 126 artigos PVP>20€
Pesquisa + preços FB / Vinted / Fleaber + títulos anúncio
"""
import csv
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

MANIFEST = Path(r"c:\Users\Casa\Downloads\a2zA2Z_CR_SK_20260709_BTS03_024.csv")
OUT_CSV = Path(__file__).parent / "reports" / "BTS03_024_precos_anuncios_126.csv"
OUT_JSON = Path(__file__).parent / "reports" / "BTS03_024_precos_anuncios_126.json"

# ASIN -> {novo, liq 1-5, nota, tipo}
# Pesquisa web jul/2026 + conversa anterior
BY_ASIN = {
    "B0GFDDQVFQ": {"novo": 140, "liq": 5, "tipo": "Robot aspirador LiDAR", "nota": "Amazon promo ~130-140€"},
    "B0F4RBFHVZ": {"novo": 390, "liq": 4, "tipo": "Robot + estação multifunções", "nota": "Lefant M3 oficial ~388-520€; 2ª mão ~300€"},
    "B0DP6S7G4V": {"novo": 190, "liq": 4, "tipo": "Robot aspirador + estação", "nota": "Proscenic Q8 Max+ ~190€"},
    "B09RQ1WK9P": {"novo": 271, "liq": 3, "tipo": "Silicone moldes 10 kg", "nota": "Reschimica R PRO 20 — verificar selado"},
    "B09QL99GZR": {"novo": 253, "liq": 3, "tipo": "Máquina cortar scrapbooking", "nota": "Sizzix — só peças se Defective", "pecas_def": 25},
    "B0D8W1434D": {"novo": 190, "liq": 4, "tipo": "Robot aspirador + estação", "nota": "Proscenic Q8 Max"},
    "B0DJQDKRNP": {"novo": 150, "liq": 4, "tipo": "Robot aspirador LiDAR", "nota": "Proscenic Q8 sem estação"},
    "B0F26P4FT8": {"novo": 130, "liq": 3, "tipo": "Robot aspirador LiDAR", "nota": "Vexilar W9", "pecas_def": 15},
    "B0DXFDZ8QY": {"novo": 168, "liq": 5, "tipo": "Panela pressão 6L", "nota": "Fissler Vitaquick"},
    "B07JH4JHTC": {"novo": 115, "liq": 4, "tipo": "Filtro aquário externo", "nota": "Fluval 307 — peças", "pecas_def": 15},
    "B09Q3N98FB": {"novo": 138, "liq": 4, "tipo": "LED inteligente modular", "nota": "Nanoleaf Lines 9 barras ~138-180€"},
    "B0CHMFLJSX": {"novo": 75, "liq": 2, "tipo": "Candeeiro parede LED 150cm", "nota": "Genérico exterior — lento"},
    "B0CNPYGF85": {"novo": 95, "liq": 2, "tipo": "Suporte cartaz A1 com rodas", "nota": "TUKA poster stand — nicho"},
    "B0BS1CX1LR": {"novo": 95, "liq": 4, "tipo": "Cesto roupa 90L", "nota": "Joseph Joseph Tota"},
    "B0BN6PBGFD": {"novo": 55, "liq": 2, "tipo": "Serviço mesa 18 peças", "nota": "Excelsa Jaipur — Defective lento"},
    "B0BZW7L66T": {"novo": 114, "liq": 5, "tipo": "Almofada cervical visco", "nota": "Tempur Original ~114-150€"},
    "B0FKBCK3VP": {"novo": 55, "liq": 3, "tipo": "Cadeira auto cão XL", "nota": "unipaws até 55kg"},
    "B0G7ZBTBT3": {"novo": 65, "liq": 2, "tipo": "Carrinho praia dobrável", "nota": "Bollerwagen 200L"},
    "B07DRJ24VZ": {"novo": 55, "liq": 2, "tipo": "Porta automática galinhas", "nota": "Kerbl — nicho rural"},
    "B0721G1QKN": {"novo": 75, "liq": 3, "tipo": "Painel LED Zigbee", "nota": "Paulmann Cesena"},
    "B08CZVYJH1": {"novo": 70, "liq": 4, "tipo": "Philips Hue E14 2x", "nota": "Hue lâmpadas"},
    "B08MQHW3BX": {"novo": 70, "liq": 4, "tipo": "Caixotes reciclagem cozinha", "nota": "Rotho Albula 4 comp."},
    "B00O4BIGWA": {"novo": 70, "liq": 3, "tipo": "Ração cão 12 kg", "nota": "Advance Veterinary"},
    "B09ZKFK4JD": {"novo": 65, "liq": 3, "tipo": "Almofada visco ajustável", "nota": "DreamyBlue"},
    "B088S22W3Q": {"novo": 65, "liq": 4, "tipo": "Philips Hue spot", "nota": "Hue Buckram"},
    "B07D1F6L13": {"novo": 45, "liq": 2, "tipo": "Estore duplo rolo", "nota": "Uniestor 120×250"},
    "B0DQV52YLZ": {"novo": 45, "liq": 3, "tipo": "Fita LED exterior 60m", "nota": "Lichterkette outdoor"},
    "B09475LSP7": {"novo": 60, "liq": 3, "tipo": "Ventoinha teto com luz", "nota": "Cecotec EnergySilence"},
    "B0DRFXH9D4": {"novo": 45, "liq": 2, "tipo": "Plafonnier LED Ø50cm", "nota": "OUILA 48W"},
    "B0CVKHV1C2": {"novo": 45, "liq": 2, "tipo": "Quadro decorativo 93×63", "nota": "Kare canvas"},
    "B0F5HF4V2Z": {"novo": 35, "liq": 3, "tipo": "Almofada leitura", "nota": "SOOYUZXXED"},
    "B0FM3NTQ6Z": {"novo": 45, "liq": 2, "tipo": "Painel LED teto 120×30", "nota": "Genérico dimmable"},
    "B07NXVR5DJ": {"novo": 55, "liq": 4, "tipo": "Candeeiro casa banho", "nota": "Paulmann 79718"},
    "B09ZPHQPX5": {"novo": 48, "liq": 4, "tipo": "Ração gato 12 kg", "nota": "Ultima esterilizado frango"},
    "B07WQLZ6SF": {"novo": 48, "liq": 4, "tipo": "Ração cão 14 kg", "nota": "Hunger of the Wolf"},
    "B0F8MYH24Q": {"novo": 40, "liq": 2, "tipo": "Plafonnier LED Ø60cm", "nota": "YIFMOO"},
    "B09TPYRGJD": {"novo": 48, "liq": 4, "tipo": "Ração gato 12 kg", "nota": "Ultima peru"},
    "B0F3JF1YBR": {"novo": 55, "liq": 5, "tipo": "Mopa limpeza água limpa/suja", "nota": "Vileda H2PrO"},
    "B07XGCDMF4": {"novo": 45, "liq": 2, "tipo": "Estore zebra duplo", "nota": "Blindecor"},
    "B0BYYRVVC5": {"novo": 35, "liq": 3, "tipo": "Sync LED TV HDMI", "nota": "BDFFLY backlight"},
    "B0DQ8BDT9Z": {"novo": 45, "liq": 2, "tipo": "Topper colchão cooling", "nota": "Novilla 160×200"},
    "B071F95D14": {"novo": 40, "liq": 3, "tipo": "Estendal mural", "nota": "Amig 100×40"},
    "B07V5CM1DW": {"novo": 90, "liq": 5, "tipo": "Philips Hue color 2x", "nota": "Hue White+Color"},
    "B08Y6H45G8": {"novo": 42, "liq": 4, "tipo": "Ração gato 7 kg", "nota": "Nature's Variety peru"},
    "B0DY4HGBNX": {"novo": 35, "liq": 2, "tipo": "Barra cortina duche L/U", "nota": "Aço preto"},
    "B088RYNQ1V": {"novo": 43, "liq": 3, "tipo": "Philips Hue spot embutir", "nota": "Milliskin"},
    "B0CJ2WH9Q9": {"novo": 40, "liq": 4, "tipo": "Cama cão ortopédica XL", "nota": "EHEYCIGA"},
    "B0CMQN8TDP": {"novo": 38, "liq": 3, "tipo": "Kit lixo embutido cozinha", "nota": "SOCONT"},
    "B09M9HV2D3": {"novo": 32, "liq": 3, "tipo": "Relógio LED parede 16.5\"", "nota": "XREXS"},
    "B07DX84L54": {"novo": 22, "liq": 4, "tipo": "Caixote porta 12L", "nota": "WENKO"},
    "B0CF8WZQQH": {"novo": 45, "liq": 2, "tipo": "Carrinho compras 6 rodas", "nota": "VOUNOT alumínio"},
    "B0FWCD22YW": {"novo": 38, "liq": 4, "tipo": "Cadeira auto cão", "nota": "Memory foam"},
    "B002CWWQ60": {"novo": 38, "liq": 2, "tipo": "Lâmpada répteis UV", "nota": "Lucky Reptile 50W"},
    "B0BF5DPMSY": {"novo": 35, "liq": 4, "tipo": "Casa gato exterior", "nota": "Kerbl Paola Eco"},
    "B0FX3SQJ5T": {"novo": 35, "liq": 3, "tipo": "Topper colchão 120×200", "nota": "BedStory"},
    "B0CWN4599V": {"novo": 35, "liq": 2, "tipo": "Candeeiro Sputnik 6 luzes", "nota": "Vintage"},
    "B096WWVXRV": {"novo": 28, "liq": 5, "tipo": "Snacks gato Sheba", "nota": "Creamy Snacks pack"},
    "B09Q95C2K1": {"novo": 35, "liq": 3, "tipo": "Lâmpadas GU10 RGB Alexa", "nota": "Fitop 2x"},
    "B0CVLFMS6Q": {"novo": 35, "liq": 2, "tipo": "Estore opaco 140×175", "nota": "INTERBLIND"},
    "B01783Z7GI": {"novo": 22, "liq": 3, "tipo": "Arnês cão Ferplast", "nota": "Tamanho M"},
    "B00004RFRV": {"novo": 28, "liq": 5, "tipo": "Cafeteira Bialetti 9 chávenas", "nota": "Moka Express alumínio"},
    "B081283QJ7": {"novo": 32, "liq": 3, "tipo": "Grelha ferro fundido", "nota": "NutriChef reversível"},
    "B06XSGPQHR": {"novo": 32, "liq": 3, "tipo": "Tampa WC soft close", "nota": "WENKO Premium"},
    "B0G2FTRB2P": {"novo": 28, "liq": 2, "tipo": "Mosquiteiro VW T5/T6", "nota": "Nicho VW"},
    "B0126MS41G": {"novo": 28, "liq": 3, "tipo": "Caixa transporte bolos", "nota": "Dr. Oetker"},
    "B07DVM75C4": {"novo": 28, "liq": 4, "tipo": "Ração cão Amazon 10kg", "nota": "Amazon Basics beef"},
    "B07DVK55RL": {"novo": 28, "liq": 4, "tipo": "Ração cão Amazon 10kg", "nota": "Amazon Basics cordeiro"},
    "B07SPXTQ33": {"novo": 50, "liq": 4, "tipo": "Philips Hue E14 2x", "nota": "Hue White E14"},
    "B0FN47P7XQ": {"novo": 28, "liq": 3, "tipo": "Almofada 40×80 visco", "nota": "BedStory"},
    "B016BC4K6K": {"novo": 28, "liq": 3, "tipo": "Relógio rádio parede", "nota": "TFA Dostmann"},
    "B0B7MRY6MQ": {"novo": 28, "liq": 2, "tipo": "Plafonnier LED 48W", "nota": "OTREN"},
    "B0DSP1ML7F": {"novo": 28, "liq": 2, "tipo": "Plafonnier LED teto", "nota": "Kuwork"},
    "B07X1KHDM5": {"novo": 25, "liq": 2, "tipo": "Película blackout janela", "nota": "Xcelenze 2m"},
    "B08L8YWF57": {"novo": 22, "liq": 2, "tipo": "Tapete entrada", "nota": "VOUNOT"},
    "B00O59VQ32": {"novo": 28, "liq": 2, "tipo": "Candeeiro pendente vintage", "nota": "EGLO Truro"},
    "B01987ZEQK": {"novo": 22, "liq": 2, "tipo": "Saco vácuo roupa XXL", "nota": "Compactor"},
    "B0000A8VUV": {"novo": 28, "liq": 4, "tipo": "Set açúcar/leite Bodum", "nota": "Bodum Columbia inox"},
    "B09NNP7VVG": {"novo": 28, "liq": 2, "tipo": "Candeeiro solar jardim", "nota": "Gadgy LED"},
    "B0CGV6FM76": {"novo": 45, "liq": 4, "tipo": "Filtro torneira BRITA", "nota": "BRITA On Tap V"},
    "B00MW8G62E": {"novo": 22, "liq": 4, "tipo": "Resguardos treino cão", "nota": "Amazon Basics"},
    "B09TFG94RS": {"novo": 28, "liq": 3, "tipo": "Pack 5 lâmpadas WiFi", "nota": "NITYAM SMART"},
    "B00004RFRU": {"novo": 24, "liq": 5, "tipo": "Cafeteira Bialetti 6 chávenas", "nota": "Moka Express"},
    "B0DMFCV34V": {"novo": 28, "liq": 4, "tipo": "Coleira pele cão", "nota": "Hunter Aalborg"},
    "B077K8Q5S5": {"novo": 28, "liq": 4, "tipo": "Nuancier fios bordar DMC", "nota": "Craft"},
    "B0831W7DLV": {"novo": 22, "liq": 4, "tipo": "Caixote lixo 20L", "nota": "Rotho Paso"},
    "B07T47VQX4": {"novo": 22, "liq": 4, "tipo": "Lâmpada plantas LED", "nota": "SANSI E27"},
    "B0BRT1VB8G": {"novo": 22, "liq": 4, "tipo": "Comedouro elevado cão", "nota": "lionto bambu"},
    "B0F3DB4SCW": {"novo": 22, "liq": 3, "tipo": "Capa baloiço 3 lugares", "nota": "Rimwig"},
    "B017R60JG4": {"novo": 18, "liq": 1, "tipo": "Moldura inox decor", "nota": "Decora — Defective"},
    "B0DXW1SYY9": {"novo": 22, "liq": 3, "tipo": "Organizador secretária madeira", "nota": "smartday"},
    "B0BVW1R11Y": {"novo": 28, "liq": 4, "tipo": "Escadas cão 3 degraus", "nota": "EHEYCIGA"},
    "B088TM385C": {"novo": 20, "liq": 2, "tipo": "Moldura shadow box", "nota": "Spiretro"},
    "B00CD229Q6": {"novo": 28, "liq": 5, "tipo": "Cartuchos BRITA magnésio", "nota": "BWT 5+1"},
    "B00820HMVA": {"novo": 18, "liq": 3, "tipo": "Copo escovas inox", "nota": "WENKO"},
    "B084T9KJCN": {"novo": 28, "liq": 4, "tipo": "Relógio rádio parede", "nota": "Bresser thermo"},
    "B014R008PU": {"novo": 28, "liq": 4, "tipo": "Cama cão 4 em 1", "nota": "lionto"},
    "B085YD7FN7": {"novo": 22, "liq": 4, "tipo": "Grelha forno universal", "nota": "ICQN Bosch/Siemens"},
    "B07HCNP535": {"novo": 22, "liq": 3, "tipo": "Afiador facas elétrico", "nota": "Adler CR4469"},
    "B0GGB71YSR": {"novo": 45, "liq": 4, "tipo": "Cama cão ortopédica grande", "nota": "EHEYCIGA XL"},
    "B0DKTKCM9S": {"novo": 22, "liq": 4, "tipo": "Aparadores livros Harry Potter", "nota": "Platform 9¾"},
    "B07DDXH42N": {"novo": 18, "liq": 3, "tipo": "Caneca térmica 280ml", "nota": "Drink Pod"},
    "B08MXLQ34G": {"novo": 22, "liq": 2, "tipo": "Candeeiro pé moderno", "nota": "BAKAJI"},
    "B0CC61YKP7": {"novo": 22, "liq": 4, "tipo": "Lâmpada LED circular", "nota": "Osram T9"},
    "B0DJV78D8D": {"novo": 22, "liq": 4, "tipo": "Garrafa SodaStream inox", "nota": "Fizz & Go 0.9L"},
    "B0DG34Z87M": {"novo": 22, "liq": 4, "tipo": "Garrafa térmica Hydro Flask", "nota": "354ml"},
    "B005X2FO7Y": {"novo": 18, "liq": 2, "tipo": "Tampa inox 37cm", "nota": "IBILI"},
    "B0B774LYSZ": {"novo": 22, "liq": 3, "tipo": "Colcha algodão 150×200", "nota": "LAYNENBURG"},
    # 111-126
    "B09YP1891X": {"novo": 18, "liq": 2, "tipo": "Rede decorativa corda", "nota": "WuLiangxi"},
    "B0081XIK4Q": {"novo": 28, "liq": 4, "tipo": "Colete salva-vidas cão", "nota": "Outward Hound"},
    "B01HYALF5W": {"novo": 28, "liq": 3, "tipo": "Tampa WC madeira MDF", "nota": "Beldray"},
    "B0DZC33MRF": {"novo": 28, "liq": 4, "tipo": "Escadas cão 3 degraus", "nota": "Feandrea"},
    "B0899QNZ91": {"novo": 22, "liq": 2, "tipo": "Toalha mesa algodão", "nota": "SUNBEAUTY"},
    "B09JTSS49F": {"novo": 22, "liq": 3, "tipo": "Lençol bebé GOTS 2x", "nota": "mimaDu 80×40"},
    "B06X1DYV7T": {"novo": 22, "liq": 4, "tipo": "Forma bolo desmontável 28cm", "nota": "Dr. Oetker"},
    "B0F8B36C3D": {"novo": 22, "liq": 3, "tipo": "Suporte plantas rodas", "nota": "VIBINHO"},
    "B08QYS68TT": {"novo": 35, "liq": 3, "tipo": "Almofada gravidez U", "nota": "Chilling Home"},
    "B00LO9BZ8M": {"novo": 22, "liq": 3, "tipo": "Despertador rádio digital", "nota": "TFA Bingo"},
    "B01KAR093K": {"novo": 18, "liq": 3, "tipo": "Glitter craft kids", "nota": "Baker Ross"},
    "B09M8BW63D": {"novo": 22, "liq": 3, "tipo": "Organizador acrílico makeup", "nota": "Cajones apilables"},
    "B0BW4SWNCY": {"novo": 22, "liq": 2, "tipo": "Aplique parede LED 12W", "nota": "M Ledme"},
    "B0F28W5M4S": {"novo": 22, "liq": 3, "tipo": "Utensílios cozinha silicone 14p", "nota": "Amazon Basics"},
    "B0CQJWT257": {"novo": 22, "liq": 3, "tipo": "Taça servir com tampa", "nota": "Mepal Silueta"},
    "B0FLY2KM71": {"novo": 22, "liq": 4, "tipo": "Escadas cão 2 degraus", "nota": "Feandrea"},
}


def norm(s):
    return (s or "").upper().strip()


def short_name(desc, tipo=None, max_len=55):
    if tipo:
        return tipo[:max_len]
    # limpar descrição amazon
    d = re.sub(r"\s+", " ", desc)
    d = d.split(",")[0].split(" - ")[0].split("|")[0]
    return d[:max_len].strip()


def pecas_val(novo, cond, desc, asin_data=None):
    if cond != "Defective":
        return 0
    if novo < 50:
        return 0
    d = desc.lower()
    if asin_data and "sizzix" in asin_data.get("nota", "").lower():
        return 25
    if any(x in d for x in ["robot", "aspir", "fluval", "hue", "philips", "sizzix"]):
        return min(25, max(8, round(novo * 0.10)))
    if novo >= 80:
        return 8
    if novo >= 50:
        return 5
    return 0


def price_fb(novo, cond, liq, pecas):
    if cond == "Defective":
        return pecas if pecas else 0
    mult = 0.50
    if cond in ("Carrier Damage",):
        mult = 0.45
    if liq <= 2:
        mult = 0.42
    return max(5, round(novo * mult))


def price_vinted(fb, novo, cond, liq):
    if cond == "Defective":
        return None
    # rotação rápida: ~75-85% do preço FB
    mult = 0.78 if liq >= 4 else 0.72
    return max(5, round(fb * mult))


def price_fleaber(fb):
    if fb is None:
        return None
    return max(5, fb - 5)


def fb_title(tipo, cond, novo, preco_fb, asin_data):
    estado_pt = {
        "Customer Damage": "devolução testada",
        "Carrier Damage": "transporte — testamos",
        "Warehouse Damage": "armazém — bom estado",
        "Defective": "para peças",
    }.get(cond, "devolução Amazon")
    if cond == "Defective":
        if not preco_fb:
            return f"{tipo} — DEFECTIVE — verificar / descartar"
        return f"{tipo} — PARA PEÇAS — {preco_fb}€"
    ref = asin_data.get("nota", "") if asin_data else ""
    return f"{tipo} — {estado_pt} — {preco_fb}€ (novo ~{novo}€)"


def stars(n):
    return "★" * int(n) if n else "★★"


def lookup(row):
    asin = norm(row.get("ASIN"))
    if asin in BY_ASIN:
        return dict(BY_ASIN[asin]), "pesquisa"
    return None, None


def estimate(row):
    pvp = float(row["UNIT RETAIL"])
    desc = row["Item Desc"]
    d = desc.lower()
    if any(x in d for x in ["robot", "aspirateur", "aspirador", "aspirapolvere"]):
        novo = round(pvp * 0.42)
    elif "hue" in d or "philips" in d and "led" in d:
        novo = round(pvp * 0.95)
    elif pvp >= 60:
        novo = round(pvp * 0.78)
    elif pvp >= 40:
        novo = round(pvp * 0.82)
    else:
        novo = round(pvp * 0.85)
    liq = 3
    if any(x in d for x in ["store", "rollo", "cortina", "light", "led", "deco", "poster", "wand"]):
        liq = 2
    if any(x in d for x in ["hue", "purina", "ultima", "bialetti", "tempur", "fissler", "joseph"]):
        liq = 4
    tipo = short_name(desc)
    return {"novo": novo, "liq": liq, "tipo": tipo, "nota": "estimativa categoria"}, "estimativa"


def main():
    rows = list(csv.DictReader(open(MANIFEST, encoding="utf-8")))
    over20 = [(i + 1, r) for i, r in enumerate(rows) if float(r["UNIT RETAIL"]) > 20]

    out = []
    tot_fb = tot_vinted = tot_fleaber = 0
    pesquisa_n = estimativa_n = 0

    for num, row in over20:
        pvp = float(row["UNIT RETAIL"])
        cond = row["CONDITION"]
        desc = row["Item Desc"]
        asin = norm(row.get("ASIN"))

        data, fonte = lookup(row)
        if not data:
            data, fonte = estimate(row)
            estimativa_n += 1
        else:
            pesquisa_n += 1

        novo = data["novo"]
        liq = data.get("liq", 3)
        tipo = data.get("tipo") or short_name(desc)
        pecas = data.get("pecas_def", 0) if cond == "Defective" else 0
        if cond == "Defective" and not pecas:
            pecas = pecas_val(novo, cond, desc, data)

        fb = price_fb(novo, cond, liq, pecas)
        vinted = price_vinted(fb, novo, cond, liq) if cond != "Defective" else None
        fleaber = price_fleaber(fb) if fb and cond != "Defective" else (None if not fb else "")
        titulo = fb_title(tipo, cond, novo, fb, data)

        if fb:
            tot_fb += fb
        if vinted:
            tot_vinted += vinted
        if fleaber:
            tot_fleaber += fleaber

        out.append({
            "#": num,
            "ASIN": asin,
            "Tipo artigo": tipo,
            "Descrição manifesto": desc[:80],
            "Estado": cond,
            "PVP manifesto (€)": pvp,
            "Novo real (€)": novo,
            "Facebook (€)": fb if fb else "",
            "Vinted rápido (€)": vinted if vinted else "",
            "Fleaber (€)": fleaber if fleaber else "",
            "Peças (€)": pecas if cond == "Defective" and pecas else "",
            "Liquidez": stars(liq),
            "Título anúncio FB": titulo,
            "Fonte preço": fonte,
            "Nota": data.get("nota", ""),
        })

    # receita modelo 60% vendem ao preço vinted médio
    func_vinted = sum(r["Vinted rápido (€)"] or 0 for r in out if r["Estado"] != "Defective")
    func_fb = sum(r["Facebook (€)"] or 0 for r in out if r["Estado"] != "Defective")
    pecas_t = sum(r["Peças (€)"] or 0 for r in out)
    receita_realista = round(func_vinted * 0.60 + pecas_t, 2)

    summary = {
        "lote": "A2zA2Z CR SK 20260709 BTS03 024",
        "artigos_pvp_maior_20": len(out),
        "pesquisa_direta": pesquisa_n,
        "estimativa": estimativa_n,
        "soma_precos_fb": tot_fb,
        "soma_precos_vinted": tot_vinted,
        "soma_precos_fleaber": tot_fleaber,
        "receita_realista_126_60pct_vinted": receita_realista,
        "custo_lote": 1650,
        "margem_estimada_126": round(receita_realista - 1650 * (len(out) / 246), 2),
    }

    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    fields = list(out[0].keys())
    with open(OUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(out)
        f.write("\n")
        for k, v in summary.items():
            w.writerow({"#": k, "Tipo artigo": v})

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump({"summary": summary, "items": out}, f, ensure_ascii=False, indent=2)

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"\nCSV: {OUT_CSV}")


if __name__ == "__main__":
    main()
