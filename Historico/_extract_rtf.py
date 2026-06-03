import re
import os
import glob

BASE = os.path.dirname(os.path.abspath(__file__))


def rtf_plain(path: str, max_chars: int = 12000) -> str:
    with open(path, "rb") as f:
        raw = f.read()
    s = raw.decode("latin-1", errors="ignore")
    s = re.sub(r"\\bin\d+[^\\s]*", " ", s)
    s = re.sub(r"\\[a-z]+\d*\s?", " ", s)
    s = re.sub(r"[{}]", " ", s)
    s = re.sub(r"\\'[0-9a-f]{2}", " ", s)
    s = re.sub(r"[^\x20-\x7E\xC0-\xFF\n]", " ", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()[:max_chars]


def main() -> None:
    parts: list[str] = []
    for p in sorted(glob.glob(os.path.join(BASE, "*.rtf"))):
        name = os.path.basename(p)
        if name.startswith("_"):
            continue
        sz = os.path.getsize(p)
        if sz < 100_000:
            limit = 20_000
        elif sz < 500_000:
            limit = 8_000
        else:
            limit = 4_000
        txt = rtf_plain(p, limit)
        sep = "=" * 60
        parts.append(f"\n{sep}\n{name} ({sz} bytes)\n{sep}\n{txt}\n")

    out_path = os.path.join(BASE, "_extract_all.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("".join(parts))
    print(f"wrote {out_path} ({len(parts)} files)")


if __name__ == "__main__":
    main()
