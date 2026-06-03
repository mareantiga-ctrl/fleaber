import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { createRequire } from "module";

const require = createRequire(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "_docx_tools", "package.json")
);
const {
  Document,
  Packer,
  Paragraph,
  TextRun,
  HeadingLevel,
  Table,
  TableRow,
  TableCell,
  WidthType,
  ShadingType,
  AlignmentType,
} = require("docx");

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MD_PATH = path.join(__dirname, "FLEABER_DOCUMENTO.md");
const OUT_PATH = path.join(__dirname, "FLEABER_DOCUMENTO.docx");

function parseInline(text) {
  const runs = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`)/g;
  let last = 0;
  let m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) runs.push({ text: text.slice(last, m.index) });
    const tok = m[0];
    if (tok.startsWith("**")) runs.push({ text: tok.slice(2, -2), bold: true });
    else runs.push({ text: tok.slice(1, -1), code: true });
    last = m.index + tok.length;
  }
  if (last < text.length) runs.push({ text: text.slice(last) });
  return runs.length ? runs : [{ text }];
}

function runsToParagraphChildren(runs, opts = {}) {
  return runs.flatMap((r) =>
    parseInline(r.text || "").map(
      (p) =>
        new TextRun({
          text: p.text,
          bold: p.bold || r.bold || opts.bold,
          font: p.code || r.code ? "Consolas" : "Calibri",
          size: p.code || r.code ? 18 : 22,
        })
    )
  );
}

function para(text, style) {
  return new Paragraph({ children: runsToParagraphChildren([{ text }]), style });
}

function heading(text, level) {
  const map = {
    0: HeadingLevel.TITLE,
    1: HeadingLevel.HEADING_1,
    2: HeadingLevel.HEADING_2,
  };
  return new Paragraph({
    text,
    heading: map[level] ?? HeadingLevel.HEADING_2,
  });
}

function parseTableRow(line) {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((c) => c.trim());
}

function isSep(cells) {
  return cells.every((c) => /^:?-+:?$/.test(c.replace(/\s/g, "")));
}

function buildTable(rows) {
  const data = rows.filter((r) => !isSep(r));
  if (!data.length) return null;
  const colCount = data[0].length;
  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    rows: data.map((row, ri) =>
      new TableRow({
        children: row.map(
          (cell) =>
            new TableCell({
              children: [
                new Paragraph({
                  children: runsToParagraphChildren([{ text: cell }], {
                    bold: ri === 0,
                  }),
                }),
              ],
              shading:
                ri === 0
                  ? { fill: "E8F4F5", type: ShadingType.CLEAR }
                  : undefined,
            })
        ),
      })
    ),
  });
}

function convert(md) {
  const lines = md.split(/\r?\n/);
  const children = [];
  let i = 0;
  let code = [];
  let inCode = false;
  let table = [];

  const flushTable = () => {
    const t = buildTable(table);
    if (t) children.push(t);
    table = [];
  };

  while (i < lines.length) {
    const line = lines[i];

    if (line.trim().startsWith("```")) {
      if (inCode) {
        children.push(
          new Paragraph({
            children: [
              new TextRun({
                text: code.join("\n"),
                font: "Consolas",
                size: 18,
              }),
            ],
          })
        );
        code = [];
        inCode = false;
      } else {
        flushTable();
        inCode = true;
      }
      i++;
      continue;
    }
    if (inCode) {
      code.push(line);
      i++;
      continue;
    }

    if (line.trim().startsWith("|") && line.includes("|", 1)) {
      table.push(parseTableRow(line));
      i++;
      continue;
    }
    flushTable();

    if (line.trim() === "---") {
      i++;
      continue;
    }
    if (line.startsWith("# ")) {
      children.push(heading(line.slice(2).trim(), 0));
      i++;
      continue;
    }
    if (line.startsWith("## ")) {
      children.push(heading(line.slice(3).trim(), 1));
      i++;
      continue;
    }
    if (line.startsWith("### ")) {
      children.push(heading(line.slice(4).trim(), 2));
      i++;
      continue;
    }
    if (line.startsWith("> ")) {
      children.push(para(line.slice(2).trim()));
      i++;
      continue;
    }
    const num = line.match(/^(\d+)\.\s+(.*)/);
    if (num) {
      children.push(
        new Paragraph({
          children: runsToParagraphChildren([{ text: num[2] }]),
          numbering: { reference: "numbers", level: 0 },
        })
      );
      i++;
      continue;
    }
    if (line.trim().startsWith("- ")) {
      children.push(
        new Paragraph({
          children: runsToParagraphChildren([{ text: line.trim().slice(2) }]),
          bullet: { level: 0 },
        })
      );
      i++;
      continue;
    }
    if (!line.trim()) {
      i++;
      continue;
    }
    children.push(para(line.trim()));
    i++;
  }
  flushTable();
  if (inCode && code.length) {
    children.push(
      new Paragraph({
        children: [new TextRun({ text: code.join("\n"), font: "Consolas", size: 18 })],
      })
    );
  }
  return children;
}

const md = fs.readFileSync(MD_PATH, "utf8");
const doc = new Document({
  styles: {
    default: {
      document: {
        run: { font: "Calibri", size: 22 },
      },
    },
  },
  numbering: {
    config: [
      {
        reference: "numbers",
        levels: [
          {
            level: 0,
            format: "decimal",
            text: "%1.",
            alignment: AlignmentType.START,
          },
        ],
      },
    ],
  },
  sections: [{ children: convert(md) }],
});

const buf = await Packer.toBuffer(doc);
fs.writeFileSync(OUT_PATH, buf);
console.log("OK:", OUT_PATH);
