#!/usr/bin/env python3
from __future__ import annotations

import ftplib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV = ROOT / "tool" / "fleahub_ftp.local.env"


def load_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def walk(ftp: ftplib.FTP, path: str, depth: int = 0, max_depth: int = 2) -> None:
    indent = "  " * depth
    try:
        ftp.cwd(path)
    except ftplib.error_perm as e:
        print(f"{indent}! cwd {path}: {e}")
        return
    pwd = ftp.pwd()
    print(f"{indent}[{pwd}]")
    try:
        entries = []
        ftp.retrlines("LIST", entries.append)
    except ftplib.error_perm as e:
        print(f"{indent}  list fail: {e}")
        return
    dirs = []
    files = []
    for line in entries:
        parts = line.split(maxsplit=8)
        if len(parts) < 9:
            continue
        name = parts[8]
        if name in (".", ".."):
            continue
        is_dir = line.startswith("d")
        if is_dir:
            dirs.append(name)
        else:
            files.append((name, parts[4] if len(parts) > 4 else "?"))
    for name, size in files[:40]:
        print(f"{indent}  f {name} ({size})")
    if len(files) > 40:
        print(f"{indent}  ... +{len(files)-40} files")
    if depth >= max_depth:
        for d in dirs:
            print(f"{indent}  d {d}/")
        return
    for d in dirs:
        print(f"{indent}  d {d}/")
        here = ftp.pwd()
        walk(ftp, d, depth + 1, max_depth)
        ftp.cwd(here)


def main() -> None:
    cfg = load_env(ENV)
    ftp = ftplib.FTP()
    ftp.connect(cfg["FTP_HOST"], int(cfg.get("FTP_PORT") or 21), timeout=60)
    ftp.login(cfg["FTP_USER"], cfg["FTP_PASSWORD"])
    ftp.set_pasv(True)
    print("home:", ftp.pwd())
    walk(ftp, "/", 0, 2)
    # check stamp in candidate paths
    candidates = [
        "/public_html/fleahub",
        "/public_html",
        "/fleahub",
        "/httpdocs/fleahub",
        "/www/fleahub",
        "/domains/fleaber.pt/public_html/fleahub",
        "/domains/fleaber.pt/public_html",
    ]
    print("\n--- stamp probes ---")
    for c in candidates:
        try:
            ftp.cwd(c)
            buf: list[bytes] = []
            try:
                ftp.retrbinary("RETR FLEAHUB_PREVIEW_STAMP.txt", buf.append)
                print(c, "=>", b"".join(buf).decode("utf-8", errors="replace")[:120].replace("\n", " | "))
            except ftplib.error_perm:
                names = ftp.nlst()[:8]
                print(c, "no stamp; sample:", names)
        except ftplib.error_perm as e:
            print(c, "NO", e)
    ftp.quit()


if __name__ == "__main__":
    main()
