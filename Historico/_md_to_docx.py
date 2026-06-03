"""Converte FLEABER_DOCUMENTO.md para .docx (python-docx)."""
from __future__ import annotations

import os
import re
import sys

try:
    from docx import Document
    from docx.enum.text import WD_PARAGRAPH_ALIGNMENT
    from docx.oxml.ns import qn
    from docx.shared import Inches, Pt, RGBColor
except ImportError:
    print("Instala: py -3 -m pip install python-docx")
    sys.exit(1)

BASE = os.path.dirname(os.path.abspath(__file__))
MD_PATH = os.path.join(BASE, "FLEABER_DOCUMENTO.md")
OUT_PATH = os.path.join(BASE, "FLEABER_DOCUMENTO.docx")

TEAL = RGBColor(0x00, 0x77, 0x82)


def set_cell_shading(cell, fill_hex: str) -> None:
    shading = cell._tc.get_or_add_tcPr()
    shd = shading.get_or_add_shd()
    shd.set(qn("w:fill"), fill_hex)
    shd.set(qn("w:val"), "clear")


def add_runs(paragraph, text: str, bold_default: bool = False) -> None:
    """Inline **bold** e `code`."""
    parts = re.split(r"(\*\*[^*]+\*\*|`[^`]+`)", text)
    for part in parts:
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            run = paragraph.add_run(part[2:-2])
            run.bold = True
        elif part.startswith("`") and part.endswith("`"):
            run = paragraph.add_run(part[1:-1])
            run.font.name = "Consolas"
            run.font.size = Pt(9)
        else:
            run = paragraph.add_run(part)
            if bold_default:
                run.bold = True


def parse_table_row(line: str) -> list[str]:
    line = line.strip().strip("|")
    return [c.strip() for c in line.split("|")]


def is_separator_row(cells: list[str]) -> bool:
    return all(re.match(r"^:?-+:?$", c.replace(" ", "")) for c in cells if c)


def main() -> None:
    with open(MD_PATH, encoding="utf-8") as f:
        lines = f.read().splitlines()

    doc = Document()
    section = doc.sections[0]
    section.top_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)

    style = doc.styles["Normal"]
    style.font.name = "Calibri"
    style.font.size = Pt(11)

    i = 0
    in_code = False
    code_lines: list[str] = []
    table_rows: list[list[str]] = []

    def flush_table() -> None:
        nonlocal table_rows
        if not table_rows:
            return
        rows = [r for r in table_rows if not is_separator_row(r)]
        if not rows:
            table_rows = []
            return
        cols = len(rows[0])
        tbl = doc.add_table(rows=len(rows), cols=cols)
        tbl.style = "Table Grid"
        for ri, row in enumerate(rows):
            for ci, cell_text in enumerate(row):
                cell = tbl.rows[ri].cells[ci]
                cell.text = ""
                p = cell.paragraphs[0]
                add_runs(p, cell_text, bold_default=(ri == 0))
                if ri == 0:
                    set_cell_shading(cell, "E8F4F5")
        table_rows = []
        doc.add_paragraph()

    while i < len(lines):
        line = lines[i]

        if line.strip().startswith("```"):
            if in_code:
                p = doc.add_paragraph()
                run = p.add_run("\n".join(code_lines))
                run.font.name = "Consolas"
                run.font.size = Pt(9)
                code_lines = []
                in_code = False
            else:
                flush_table()
                in_code = True
            i += 1
            continue

        if in_code:
            code_lines.append(line)
            i += 1
            continue

        if line.strip().startswith("|") and "|" in line[1:]:
            flush_table()
            table_rows.append(parse_table_row(line))
            i += 1
            continue
        else:
            flush_table()

        if line.strip() == "---":
            doc.add_paragraph()
            i += 1
            continue

        if line.startswith("# "):
            p = doc.add_heading(line[2:].strip(), level=0)
            for run in p.runs:
                run.font.color.rgb = TEAL
            i += 1
            continue
        if line.startswith("## "):
            doc.add_heading(line[3:].strip(), level=1)
            i += 1
            continue
        if line.startswith("### "):
            doc.add_heading(line[4:].strip(), level=2)
            i += 1
            continue

        if line.startswith("> "):
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.35)
            add_runs(p, line[2:].strip())
            i += 1
            continue

        m = re.match(r"^(\d+)\.\s+(.*)", line.strip())
        if m:
            p = doc.add_paragraph(style="List Number")
            add_runs(p, m.group(2))
            i += 1
            continue

        if line.strip().startswith("- "):
            p = doc.add_paragraph(style="List Bullet")
            add_runs(p, line.strip()[2:])
            i += 1
            continue

        if not line.strip():
            i += 1
            continue

        # Metadata lines **Key:** value
        p = doc.add_paragraph()
        add_runs(p, line.strip())
        i += 1

    flush_table()
    if in_code and code_lines:
        p = doc.add_paragraph()
        run = p.add_run("\n".join(code_lines))
        run.font.name = "Consolas"
        run.font.size = Pt(9)

    doc.save(OUT_PATH)
    print(f"OK: {OUT_PATH}")


if __name__ == "__main__":
    main()
