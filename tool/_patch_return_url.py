from pathlib import Path

p = Path("supabase/functions/sec-fase2-e2e-oversell/index.ts")
t = p.read_text(encoding="utf-8")
needle = 'confirm: true,\n'
insert = 'confirm: true,\n      return_url: "https://fleaber.pt/",\n'
# Only add where missing next to confirm:true for paymentIntents.create blocks
count = 0
out = []
lines = t.splitlines(keepends=True)
i = 0
while i < len(lines):
    line = lines[i]
    out.append(line)
    if "confirm: true," in line and i + 1 < len(lines):
        nxt = lines[i + 1]
        if "return_url" not in nxt:
            # preserve indent of confirm line
            indent = line[: len(line) - len(line.lstrip())]
            out.append(f'{indent}return_url: "https://fleaber.pt/",\n')
            count += 1
    i += 1
p.write_text("".join(out), encoding="utf-8")
print("added_return_url", count)
