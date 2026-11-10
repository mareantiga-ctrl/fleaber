#!/usr/bin/env python3
"""Upload an isolated Hub preview folder (NOT /www/fleahub production).

Usage:
  python tool/upload_fleahub_preview_ftp.py \\
    --local tool/reports/p13_product_desktop/_preview_web \\
    --remote /www/fleahub-p13-preview
"""
from __future__ import annotations

import argparse
import ftplib
import os
import ssl
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "fleahub_ftp.local.env"


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
    port = int(cfg.get("FTP_PORT") or 21)
    if proto == "ftps":
        ctx = ssl.create_default_context()
        ftp: ftplib.FTP = ftplib.FTP_TLS(context=ctx)
        ftp.connect(host, port, timeout=60)
        ftp.login(user, password)
        ftp.prot_p()
    else:
        ftp = ftplib.FTP()
        ftp.connect(host, port, timeout=60)
        ftp.login(user, password)
    ftp.set_pasv(True)
    return ftp


def ensure_cwd(ftp: ftplib.FTP, remote_dir: str) -> None:
    remote_dir = remote_dir.replace("\\", "/").rstrip("/")
    try:
        ftp.cwd(remote_dir)
        print("cwd:", ftp.pwd())
        return
    except ftplib.error_perm:
        pass
    try:
        ftp.cwd("/")
    except ftplib.error_perm:
        pass
    for part in [p for p in remote_dir.split("/") if p]:
        try:
            ftp.cwd(part)
        except ftplib.error_perm:
            try:
                ftp.mkd(part)
            except ftplib.error_perm:
                pass
            ftp.cwd(part)
    print("cwd:", ftp.pwd())


def upload_tree(ftp: ftplib.FTP, local_dir: Path, base_pwd: str) -> tuple[int, int]:
    ok = 0
    fail = 0
    for root, _dirs, files in os.walk(local_dir):
        rel = Path(root).relative_to(local_dir)
        ftp.cwd(base_pwd)
        if str(rel) != ".":
            for part in rel.parts:
                try:
                    ftp.cwd(part)
                except ftplib.error_perm:
                    try:
                        ftp.mkd(part)
                    except ftplib.error_perm as e:
                        print("mkd fail", part, e)
                    ftp.cwd(part)
        for name in files:
            local = Path(root) / name
            try:
                with local.open("rb") as f:
                    ftp.storbinary(f"STOR {name}", f, blocksize=1024 * 256)
                ok += 1
                if ok % 15 == 0 or name in (
                    "main.dart.js",
                    "index.html",
                    "FLEAHUB_PREVIEW_STAMP.txt",
                    "flutter_service_worker.js",
                ):
                    print(f"  OK [{ok}] {rel.as_posix()}/{name}")
            except Exception as e:
                fail += 1
                print(f"  FAIL {rel.as_posix()}/{name}: {e}")
    return ok, fail


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--local", required=True, help="Local folder with index.html")
    ap.add_argument(
        "--remote",
        required=True,
        help="Remote dir e.g. /www/fleahub-p13-preview (must NOT be /www/fleahub)",
    )
    args = ap.parse_args()
    local = Path(args.local)
    remote = args.remote.replace("\\", "/").rstrip("/")
    if remote in ("/www/fleahub", "www/fleahub", "/fleahub"):
        print("REFUSED: will not upload over production /www/fleahub")
        return 4
    if "fleahub-p13" not in remote and "preview" not in remote.lower():
        print("REFUSED: remote must be an isolated preview path")
        return 4
    if not local.is_dir() or not (local / "index.html").is_file():
        print("missing local build", local)
        return 1
    if not ENV_PATH.is_file():
        print("missing", ENV_PATH)
        return 1
    cfg = load_env(ENV_PATH)
    print("host:", cfg.get("FTP_HOST"))
    print("local:", local)
    print("remote:", remote)
    try:
        ftp = connect(cfg)
    except Exception as e:
        host = cfg.get("FTP_HOST", "")
        if "fleabe." in host and "fleaber." not in host:
            cfg = dict(cfg)
            cfg["FTP_HOST"] = host.replace("fleabe.", "fleaber.")
            print("retry host:", cfg["FTP_HOST"])
            ftp = connect(cfg)
        else:
            print("CONNECT FAIL:", e)
            return 2
    ensure_cwd(ftp, remote)
    base_pwd = ftp.pwd()
    print("uploading to", base_pwd)
    ok, fail = upload_tree(ftp, local, base_pwd)
    print(f"done ok={ok} fail={fail}")
    try:
        ftp.cwd(base_pwd)
        buf: list[bytes] = []
        ftp.retrbinary("RETR FLEAHUB_PREVIEW_STAMP.txt", buf.append)
        print("--- remote stamp ---")
        print(b"".join(buf).decode("utf-8", errors="replace"))
    except Exception as e:
        print("stamp verify:", e)
    ftp.quit()
    return 0 if fail == 0 else 3


if __name__ == "__main__":
    sys.exit(main())
