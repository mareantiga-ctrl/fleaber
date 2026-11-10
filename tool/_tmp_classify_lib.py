from collections import Counter
import subprocess

out = subprocess.check_output(
    ["git", "status", "--porcelain", "--", "lib"], text=True, errors="replace"
)
c = Counter()
for line in out.splitlines():
    path = line[3:].strip().strip('"')
    parts = path.split("/")
    key = "/".join(parts[:3]) if len(parts) >= 3 else path
    c[key] += 1
print("lib TOTAL", sum(c.values()))
for k, v in c.most_common(50):
    print(f"{v:4d} {k}")
