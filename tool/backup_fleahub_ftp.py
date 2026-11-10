#!/usr/bin/env python3
"""Download remote /www/fleahub → local backup folder (FTP)."""
from __future__ import annotations

import ftplib
import ssl
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "fleahub_ftp.local.env"
OUT_ROOT = ROOT / "00-fleahub-zips"


def load_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def connect(cfg: dict[str, str]) -> ftplib.FTP:
    proto = (cfg.get("FTP_PROTOCOL") or "ftp").lower()
    host = cfg["FTP_HOST"]
    user = cfg["FTP_USER"]
    password = cfg["FTP_PASSWORD"]
    port = int(cfg["FTP_PORT"] or 21)
    if proto == "ftps":
        ctx = ssl.create_default_context()
        ftp: ftplib.FTP = ftplib.FTP_TLS(context=ctx)
        ftp.connect(host, port, timeout=90)
        ftp.login(user, password)
        ftp.prot_p()
    else:
        ftp = ftplib.FTP()
        ftp.connect(host, port, timeout=90)
        ftp.login(user, password)
    ftp.set_pasv(True)
    return ftp


def walk_download(ftp: ftplib.FTP, remote: str, local: Path) -> tuple[int, int]:
    ok = fail = 0
    local.mkdir(parents=True, exist_ok=True)
    try:
        entries = []
        ftp.retrlines(f"LIST {remote}", entries.append)
    except ftplib.error_perm:
        # already in dir
        entries = []
        ftp.retrlines("LIST", entries.append)
        remote = ""

    names = []
    for line in entries:
        parts = line.split(maxsplit=8)
        if len(parts) < 9:
            continue
        name = parts[8]
        if name in (".", ".."):
            continue
        is_dir = line.startswith("d")
        names.append((name, is_dir))

    for name, is_dir in names:
        rpath = f"{remote}/{name}".replace("//", "/") if remote else name
        lpath = local / name
        if is_dir:
            # recurse
            try:
                ftp.cwd(name)
            except ftplib.error_perm:
                fail += 1
                continue
            o, f = walk_download(ftp, "", lpath)
            ok += o
            fail += f
            ftp.cwd("..")
        else:
            try:
                with lpath.open("wb") as f:
                    ftp.retrbinary(f"RETR {name}", f.write)
                ok += 1
                if ok % 25 == 0:
                    print(f"  … {ok} files")
            except Exception as e:
                print("FAIL", rpath, e)
                fail += 1
    return ok, fail


def main() -> int:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    label = sys.argv[1] if len(sys.argv) > 1 else "pre_117_1_prod"
    out = OUT_ROOT / f"_backup_ftp_{label}_{stamp}"
    cfg = load_env(ENV_PATH)
    ftp = connect(cfg)
    remote = cfg.get("FTP_REMOTE_DIR") or "/www/fleahub"
    print("backup →", out)
    print("remote", remote)
    # cwd to remote
    try:
        ftp.cwd(remote)
    except ftplib.error_perm:
        for part in [p for p in remote.split("/") if p]:
            ftp.cwd(part)
    print("cwd", ftp.pwd())
    ok, fail = walk_download(ftp, "", out)
    # also save stamp text
    meta = out / "_BACKUP_META.txt"
    meta.write_text(
        f"remote={remote}\nok={ok}\nfail={fail}\nutc={stamp}\n",
        encoding="utf-8",
    )
    try:
        ftp.quit()
    except Exception:
        pass
    print(f"DONE ok={ok} fail={fail} path={out}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
