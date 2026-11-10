import re
from pathlib import Path

tmp = Path.home() / "AppData/Local/Temp"
for n in range(1, 6):
    p = tmp / f"rtcp_cs_{n}.html"
    t = p.read_text(encoding="utf-8", errors="ignore")
    print(f"=== {n} len={len(t)}")
    for pat in [
        "sessionHasExpired",
        "hasExpired",
        "payment_status",
        "checkout_session",
    ]:
        print(f"  {pat}: {t.count(pat)}")
    cs = set(re.findall(r"cs_test_[A-Za-z0-9]{10,}", t))
    print(f"  cs_in_page: {cs}")
    # init state
    m = re.search(r"<script id=\"serialized-client-state\"[^>]*>(.*?)</script>", t)
    if m:
        print("  serialized", m.group(1)[:300])
    m = re.search(r"window\.__BOOTSTRAP[^\n]{0,400}", t)
    if m:
        print("  bootstrap", m.group(0)[:300])
