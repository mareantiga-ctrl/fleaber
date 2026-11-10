from pathlib import Path

begin = (
    Path("tool/reports/144.3-checkout-align/begin_prod.sql")
    .read_text(encoding="utf-8")
    .replace("\r\n", "\n")
)
# Detect doubled newlines
sample = begin[begin.find("v_sync") : begin.find("v_sync") + 200]
print("SAMPLE", repr(sample))
idx = begin.find("v_ship_cents := coalesce((v_sync")
print("idx", idx)
print(repr(begin[idx : idx + 500]))
