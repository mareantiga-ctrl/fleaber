# -*- coding: utf-8 -*-
"""Relatório completo BTS03 024 — explicação detalhada de receitas."""
import csv
import json
import sys
from collections import Counter
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

MANIFEST = Path(r"c:\Users\Casa\Downloads\a2zA2Z_CR_SK_20260709_BTS03_024.csv")
PRICING_126 = Path(__file__).parent / "reports" / "BTS03_024_precos_anuncios_126.json"
OUT_MD = Path(__file__).parent / "reports" / "BTS03_024_RELATORIO_COMPLETO.md"
OUT_JSON = Path(__file__).parent / "reports" / "BTS03_024_RELATORIO_COMPLETO.json"

CUSTO_LOTE = 1650
FUNC = {"pessimista": 0.40, "realista": 0.60, "otimista": 0.70}


def estimate_under20(row):
    """Estimativa conservadora artigos PVP <= 20€."""
    pvp = float(row["UNIT RETAIL"])
    cond = row["CONDITION"]
    desc = row["Item Desc"].lower()
    novo = round(pvp * 0.72, 2)  # manifesto barato ≈ mais próximo do real
    lento = any(x in desc for x in [
        "light", "led", "lamp", "deco", "poster", "curtain", "store", "rollo",
        "tapete", "rug", "mat", "wand", "plaf", "moldura", "colcha",
    ])
    if cond == "Defective":
        pecas = 3 if novo >= 15 else 0
        return {"novo": novo, "venda": 0, "pecas": pecas, "fb": pecas, "vinted": 0}
    # venda rápida = preço realista de venda (não 50% FB)
    ratio = 0.32 if lento else 0.38
    venda = max(4, round(novo * ratio))
    fb = max(5, round(novo * 0.42))
    vinted = max(4, round(venda * 0.95))
    return {"novo": novo, "venda": venda, "pecas": 0, "fb": fb, "vinted": vinted}


def scenario(venda_sum, pecas_sum, rate):
    return round(venda_sum * rate + pecas_sum, 2)


def main():
    rows = list(csv.DictReader(open(MANIFEST, encoding="utf-8")))
    pricing = json.load(open(PRICING_126, encoding="utf-8"))["items"] if PRICING_126.exists() else []
    pricing_by_num = {p["#"]: p for p in pricing}

    over20_nums = {p["#"] for p in pricing}
    under20_rows = [(i + 1, r) for i, r in enumerate(rows) if (i + 1) not in over20_nums]

    # --- Processar >20€ (do CSV pesquisado) ---
    o_novo = o_venda = o_fb = o_vinted = o_pecas = 0
    o_def = 0
    for p in pricing:
        cond = p["Estado"]
        novo = p["Novo real (€)"]
        fb = p["Facebook (€)"] or 0
        vinted = p["Vinted rápido (€)"] or 0
        pecas = p["Peças (€)"] or 0
        # venda modelo = vinted (preço para rodar stock)
        venda = vinted if cond != "Defective" else 0
        o_novo += novo
        o_venda += venda
        o_fb += fb
        o_vinted += vinted
        o_pecas += pecas
        if cond == "Defective":
            o_def += 1

    # --- Processar <=20€ ---
    u_items = []
    u_novo = u_venda = u_fb = u_vinted = u_pecas = 0
    u_def = 0
    for num, row in under20_rows:
        e = estimate_under20(row)
        cond = row["CONDITION"]
        pvp = float(row["UNIT RETAIL"])
        if cond == "Defective":
            u_def += 1
        u_novo += e["novo"]
        u_venda += e["venda"]
        u_fb += e["fb"]
        u_vinted += e["vinted"]
        u_pecas += e["pecas"]
        u_items.append({
            "#": num, "pvp": pvp, "cond": cond,
            "desc": row["Item Desc"][:60], **e,
        })

    # --- Totais lote ---
    total_novo = o_novo + u_novo
    total_venda = o_venda + u_venda
    total_pecas = o_pecas + u_pecas
    total_def = o_def + u_def

    scenarios_all = {
        k: scenario(total_venda, total_pecas, v)
        for k, v in FUNC.items()
    }
    scenarios_over = {k: scenario(o_venda, o_pecas, v) for k, v in FUNC.items()}
    scenarios_under = {k: scenario(u_venda, u_pecas, v) for k, v in FUNC.items()}

    pvp_total = sum(float(r["UNIT RETAIL"]) for r in rows)
    conds = Counter(r["CONDITION"] for r in rows)

    # Explicação 223€
    explicacao_223 = {
        "artigos": len(under20_rows),
        "nao_defective": len(under20_rows) - u_def,
        "defective": u_def,
        "soma_venda_se_todos_vendessem_ao_preco_vinted": round(u_venda, 2),
        "soma_pecas_defective": round(u_pecas, 2),
        "formula": "Receita = (soma Vinted dos não-Defective × 60%) + peças",
        "calculo_realista": f"({round(u_venda, 2)} × 0.60) + {round(u_pecas, 2)} = {scenarios_under['realista']}",
        "nota": "Os 223€ NÃO é o máximo — é o esperado se só 60% dos baratos venderem ao preço Vinted.",
        "se_100pct_vendessem": round(u_venda + u_pecas, 2),
    }

    scenarios_all_b = {
        k: scenario(3500, 104, v)  # avaliação completa 246 artigos
        for k, v in FUNC.items()
    }

    data = {
        "lote": "A2zA2Z CR SK 20260709 BTS03_024",
        "custo": CUSTO_LOTE,
        "artigos": len(rows),
        "pvp_manifesto": round(pvp_total, 2),
        "condicoes": dict(conds),
        "defective_total": total_def,
        "bloco_maior_20": {
            "quantidade": len(pricing),
            "novo_real": round(o_novo, 2),
            "venda_vinted_se_bons": round(o_venda, 2),
            "pecas": round(o_pecas, 2),
            "preco_fb_total": round(o_fb, 2),
            "cenarios": scenarios_over,
        },
        "bloco_menor_20": {
            "quantidade": len(under20_rows),
            "explicacao_detalhada": explicacao_223,
            "novo_real": round(u_novo, 2),
            "venda_vinted_se_bons": round(u_venda, 2),
            "pecas": round(u_pecas, 2),
            "preco_fb_total": round(u_fb, 2),
            "cenarios": scenarios_under,
        },
        "lote_completo": {
            "novo_real": round(total_novo, 2),
            "venda_vinted_se_bons": round(total_venda, 2),
            "pecas": round(total_pecas, 2),
            "cenarios": scenarios_all,
            "margem_realista": round(scenarios_all["realista"] - CUSTO_LOTE, 2),
            "roi_realista_pct": round((scenarios_all["realista"] / CUSTO_LOTE - 1) * 100, 1),
        },
        "modelo_venda_rapida_pesquisada": {
            "venda_se_bons": 3500,
            "pecas": 104,
            "cenarios": scenarios_all_b,
            "margem_realista": round(scenarios_all_b["realista"] - CUSTO_LOTE, 2),
            "nota": "Preços mercado pesquisados — não preços FB 50%",
        },
    }

    # Top 15 baratos por venda
    top_under = sorted(u_items, key=lambda x: x["venda"], reverse=True)[:15]

    md = f"""# Relatório completo — Lote BTS03 024

**Data:** julho 2026  
**Ficheiro manifesto:** `a2zA2Z_CR_SK_20260709_BTS03_024.csv`  
**Custo pago (com portes):** **{CUSTO_LOTE:,} €**  
**Artigos no lote:** **{len(rows)}**

---

## 1. Resumo executivo (lê isto primeiro)

| | Valor |
|---|---|
| PVP total no manifesto Amazon | **{pvp_total:,.2f} €** *(inflacionado — não usar para decidir)* |
| Valor novo real estimado (mercado) | **~{total_novo:,.0f} €** |
| O que pagaste | **{CUSTO_LOTE:,} €** (= **{CUSTO_LOTE/len(rows):.2f} €/artigo**) |
| **Receita pessimista (40% vendem)** | **~{scenarios_all['pessimista']:,.0f} €** → lucro **{scenarios_all['pessimista']-CUSTO_LOTE:+,.0f} €** |
| **Receita realista (60% vendem)** | **~{scenarios_all['realista']:,.0f} €** → lucro **{scenarios_all['realista']-CUSTO_LOTE:+,.0f} €** |
| **Receita otimista (70% vendem)** | **~{scenarios_all['otimista']:,.0f} €** → lucro **{scenarios_all['otimista']-CUSTO_LOTE:+,.0f} €** |

**Conclusão (preços de anúncio FB/Vinted):** Compraste a ~**{CUSTO_LOTE/total_novo*100:.0f}%** do valor novo real. Se venderes aos preços do CSV de anúncios e só **60%** saírem, recebes **~{scenarios_all['realista']:,.0f} €** — **{scenarios_all['realista']-CUSTO_LOTE:+,.0f} €** vs os 1.650 €.

**Conclusão (modelo pesquisa de mercado — mais optimista):** Se os artigos funcionarem e venderem aos preços de mercado pesquisados (não aos 50% FB), a receita realista sobe para **~{scenarios_all_b['realista']:,.0f} €** — lucro **~{scenarios_all_b['realista']-CUSTO_LOTE:+,.0f} €**.

> Os dois modelos coexistem: o **FB/Vinted** é o que pões no anúncio; o **mercado** é o que podes conseguir se testares bem e venderes ao preço certo (especialmente robots).

---

## 1b. Dois modelos — qual usar?

| Modelo | Realista (60%) | Lucro vs 1.650 € | Quando usar |
|---|---|---|---|
| **A — Preços anúncio** (FB 50% / Vinted rápido) | **~{scenarios_all['realista']:,.0f} €** | **{scenarios_all['realista']-CUSTO_LOTE:+,.0f} €** | Planeamento conservador; «e se só vender a preços baixos?» |
| **B — Venda mercado pesquisada** (conversa + web) | **~{scenarios_all_b['realista']:,.0f} €** | **{scenarios_all_b['realista']-CUSTO_LOTE:+,.0f} €** | Se robots/Hue/Tempur funcionarem e venderem bem |

**Os 223 € (agora ~226 €) referem-se ao Modelo A, só nos baratos.** Não é o lucro total do lote.

---

## 1. Resumo executivo (lê isto primeiro)

Muita gente interpreta mal este número. **Não é o máximo que os 120 artigos baratos valem.**

### A confusão

- Os **120 artigos ≤20 € PVP** representam só **~{u_venda/(total_venda or 1)*100:.0f}%** da receita potencial do lote.
- O valor está nos **126 artigos >20 €** (robots, silicone, Tempur, Hue…).
- Os baratos **somam muitas unidades mas pouco dinheiro cada uma**.

### Os números dos 120 baratos, passo a passo

| Passo | O quê | Valor |
|---|---|---|
| 1 | Quantos artigos ≤20 € PVP | **{len(under20_rows)}** |
| 2 | Destes, quantos Defective | **{u_def}** ({u_def/len(under20_rows)*100:.0f}%) |
| 3 | Quantos podem vender-se funcionais | **{len(under20_rows)-u_def}** |
| 4 | Novo real estimado (total) | **~{u_novo:,.0f} €** |
| 5 | **Se TODOS vendessem** ao preço Vinted rápido | **~{u_venda:,.0f} €** |
| 6 | Peças dos Defective baratos | **~{u_pecas:,.0f} €** |
| 7 | **Máximo teórico baratos** (100% vendidos) | **~{u_venda+u_pecas:,.0f} €** |
| 8 | Taxa realista: só **60%** vendem | × 0,60 |
| 9 | **Receita realista baratos** | **~{scenarios_under['realista']:,.0f} €** |

**Fórmula:**
```
Receita realista = (soma preços Vinted dos não-Defective × 60%) + peças Defective
                 = ({u_venda:.0f} × 0,60) + {u_pecas:.0f}
                 = {scenarios_under['realista']:.0f} €
```

### Tradução simples

- Cada artigo barato vende em média a **~{u_venda/(len(under20_rows)-u_def) if len(under20_rows)>u_def else 0:.1f} €** (preço Vinted rápido).
- Tens **~{len(under20_rows)-u_def}** artigos para vender.
- **Se todos saírem:** ~**{u_venda:.0f} €**.
- **Na vida real (60% vendem):** ~**{scenarios_under['realista']:.0f} €**.

Isto **não é pouco porque o lote é mau** — é pouco porque **são artigos de 4–20 € PVP** (cabos, lâmpadas, acessórios). Mesmo vendendo tudo, cada um rende poucos euros. O trabalho é muito; o dinheiro vem dos caros.

---

## 3. Divisão do lote em dois blocos

| Bloco | Artigos | % do lote | Novo real | Venda se todos bons | Realista (60%) |
|---|---|---|---|---|---|
| **PVP > 20 €** | {len(pricing)} | {len(pricing)/len(rows)*100:.0f}% | ~{o_novo:,.0f} € | ~{o_venda:,.0f} € | **~{scenarios_over['realista']:,.0f} €** |
| **PVP ≤ 20 €** | {len(under20_rows)} | {len(under20_rows)/len(rows)*100:.0f}% | ~{u_novo:,.0f} € | ~{u_venda:,.0f} € | **~{scenarios_under['realista']:,.0f} €** |
| **TOTAL** | {len(rows)} | 100% | ~{total_novo:,.0f} € | ~{total_venda:,.0f} € | **~{scenarios_all['realista']:,.0f} €** |

**Os 126 caros representam ~{scenarios_over['realista']/scenarios_all['realista']*100:.0f}% da receita realista.** Os 120 baratos são «complemento» — úteis em lotes FB, não o motor do negócio.

---

## 4. Método de cálculo (o que combinámos)

### Passo 1 — Defective
- **Não contam como funcionais.**
- Só entram pelo **valor de peças** (robots, Hue, Sizzix, Fluval…).
- Defective barato (<50 € novo): **0 €** peças.

### Passo 2 — Não-Defective
Estimamos que só uma parte vende bem:
- 🔴 **Pessimista:** 40% funcionam e vendem
- 🟡 **Realista:** 60% funcionam e vendem
- 🟢 **Otimista:** 70% funcionam e vendem

### Passo 3 — Preço de venda
- **>20 € PVP:** pesquisa individual (CSV `BTS03_024_precos_anuncios_126.csv`)
- **≤20 € PVP:** estimativa conservadora (~32–38% do novo real = preço Vinted rápido)

### Passo 4 — Receita
```
Receita = Σ(preço venda rápido dos não-Defective) × taxa + Σ(peças)
```

**Não usamos** o PVP do manifesto (9.274 €) — está inflacionado.

---

## 5. Estados do lote

| Estado | Quantidade | % |
|---|---|---|
| Carrier Damage | {conds['Carrier Damage']} | {conds['Carrier Damage']/len(rows)*100:.0f}% |
| Customer Damage | {conds['Customer Damage']} | {conds['Customer Damage']/len(rows)*100:.0f}% |
| Defective | {conds['Defective']} | {conds['Defective']/len(rows)*100:.0f}% |
| Warehouse Damage | {conds['Warehouse Damage']} | {conds['Warehouse Damage']/len(rows)*100:.0f}% |

**{total_def} Defective** = não entram como venda funcional (só peças quando aplicável).

---

## 6. Onde está o dinheiro (top categorias >20 €)

| Tipo | Unidades aprox. | Receita realista estimada |
|---|---|---|
| Robots aspiradores (Lefant, Proscenic, Vexilar) | 7 | **~350–500 €** *(depende de quantos funcionam)* |
| Reschimica silicone 10 kg | 1 | **~60–100 €** se selado |
| Philips Hue / Nanoleaf / iluminação marca | ~15 | **~200–280 €** |
| Tempur + almofadas + toppers | ~8 | **~120–180 €** |
| Pet food (Ultima, Advance, Purina…) | ~12 | **~150–220 €** |
| Joseph Joseph, Fissler, Vileda, cozinha | ~10 | **~120–160 €** |
| Resto >20 € (decoração, estores, LED genérico…) | ~73 | **~300–450 €** |
| **Baratos ≤20 € (120 un.)** | 120 | **~{scenarios_under['realista']:.0f} €** |

---

## 7. Cenários financeiros completos

### Lote inteiro (246 artigos)

| Cenário | Taxa venda | Receita | vs 1.650 € | Resultado |
|---|---|---|---|---|
| 🔴 Pessimista | 40% | **~{scenarios_all['pessimista']:,.0f} €** | {scenarios_all['pessimista']-CUSTO_LOTE:+,.0f} € | {'Prejuízo' if scenarios_all['pessimista']<CUSTO_LOTE else 'Lucro'} |
| 🟡 Realista | 60% | **~{scenarios_all['realista']:,.0f} €** | {scenarios_all['realista']-CUSTO_LOTE:+,.0f} € | Lucro moderado |
| 🟢 Otimista | 70% | **~{scenarios_all['otimista']:,.0f} €** | {scenarios_all['otimista']-CUSTO_LOTE:+,.0f} € | Bom lucro |

### Só se venderes TUDO ao preço listado (100% — cenário raro)

| Bloco | Máximo teórico |
|---|---|
| 126 artigos >20 € (Vinted + peças) | ~{o_venda+o_pecas:,.0f} € |
| 120 artigos ≤20 € (Vinted + peças) | ~{u_venda+u_pecas:,.0f} € |
| **Total máximo** | **~{total_venda+total_pecas:,.0f} €** |

Mesmo no máximo teórico, **não chegas aos 9.274 € do manifesto** — o mercado real de revenda é muito inferior.

---

## 8. Estratégia de venda recomendada

### Canal e preço

| Canal | Preço | Quando |
|---|---|---|
| **Facebook** | ~50% do novo real | Anúncio principal |
| **Vinted** | ~75–80% do FB | Venda rápida |
| **Fleaber** | FB − 5 € | Directo/gravado — testas ao vivo |

### Ordem de prioridade

1. **Testar robots + silicone** (decide se o lote foi excelente)
2. **Anunciar individualmente** os 30–40 melhores (>40 € novo ou alta liquidez)
3. **Lotes FB** para os 120 baratos (ex: «Lote casa 25 peças — 45 €»)
4. **Live Fleaber** semanal — testas e vendes 5–10 artigos/sessão
5. Baixar 10 € o que não mover em 30 dias

### Lotes sugeridos para os 120 baratos

Em vez de 120 anúncios individuais:

| Lote | Conteúdo | Preço sugerido |
|---|---|---|
| Lote Pet | coleiras, comedouros, resguardos, snacks | 35–50 € |
| Lote Casa/Cozinha | organizadores, utensílios, WENKO | 40–55 € |
| Lote LED/Deco | candeeiros, fitas, molduras | 30–40 € |
| Lote «resto» | tudo o que sobrar | 25–35 € |

**Receita realista em lotes:** ~**{scenarios_under['realista']*1.15:.0f}–{scenarios_under['realista']*1.3:.0f} €** (ligeiramente melhor que vender 1 a 1, menos trabalho).

---

## 9. Top 15 artigos baratos (≤20 €) com mais valor individual

| # | PVP | Venda Vinted est. | Descrição |
|---|---|---|---|
"""
    for it in top_under:
        md += f"| {it['#']} | {it['pvp']:.2f} € | {it['venda']} € | {it['desc']} |\n"

    md += f"""
*Mesmo os «melhores» baratos rendem 5–12 € cada.*

---

## 10. Foi bom negócio aos 1.650 €?

| Pergunta | Resposta |
|---|---|
| Paguei caro? | **Não.** {CUSTO_LOTE/len(rows):.2f} €/peça vs ~{total_novo/len(rows):.0f} € novo real médio |
| Posso perder dinheiro? | **Sim**, se cenário pessimista E robots mortos |
| Cenário mais provável? | **Lucro 300–600 €** + muito trabalho |
| O que muda tudo? | **3–4 robots funcionais** + silicone selado |

---

## 11. Ficheiros de apoio

| Ficheiro | Conteúdo |
|---|---|
| `BTS03_024_precos_anuncios_126.csv` | 126 artigos >20 € — preços FB/Vinted/Fleaber + títulos |
| `BTS03_024_avaliacao_completa.csv` | 246 artigos — avaliação modelo |
| `BTS03_024_tabela_conversa_110.csv` | Primeiros 110 analisados na conversa GPT |
| `BTS03_024_RELATORIO_COMPLETO.json` | Dados deste relatório em JSON |

---

## 12. Glossário

| Termo | Significado |
|---|---|
| **PVP manifesto** | Preço Amazon no papel da palete — **enganador** |
| **Novo real** | O que o artigo custa novo hoje em PT/EU |
| **Venda rápida / Vinted** | Preço para vender em 1–4 semanas |
| **FB 50%** | Preço de anúncio no Facebook (~metade do novo) |
| **Receita realista** | Nem tudo vende; nem tudo funciona — 60% × preço |
| **Peças** | Valor residual de Defective (Sizzix, robots mortos…) |

---

*Relatório gerado automaticamente a partir do manifesto e pesquisa de mercado jul/2026.*
"""

    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text(md, encoding="utf-8")
    OUT_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(md[:3000])
    print("\n...\n")
    print(f"Relatório: {OUT_MD}")
    print(f"JSON: {OUT_JSON}")
    print(f"\nBaratos realista: {scenarios_under['realista']}")
    print(f"Caros realista: {scenarios_over['realista']}")
    print(f"Total realista: {scenarios_all['realista']}")


if __name__ == "__main__":
    main()
