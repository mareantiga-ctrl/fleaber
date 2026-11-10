#!/usr/bin/env python3
"""Upload deploy/fleaber_pt/fleahub → FTP (creds from tool/fleahub_ftp.local.env)."""
from __future__ import annotations

import ftplib
import os
import ssl
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "fleahub_ftp.local.env"
LOCAL = ROOT / "deploy" / "fleaber_pt" / "fleahub"


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
    port = int(cfg["FTP_PORT"] or (22 if proto == "sftp" else 21))
    if proto == "sftp":
        raise SystemExit("SFTP: usa WinSCP/FileZilla; este script faz FTP/FTPS.")
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
    if not remote_dir or remote_dir == ".":
        print("cwd:", ftp.pwd())
        return
    # try absolute then stepwise
    try:
        ftp.cwd(remote_dir)
        print("cwd:", ftp.pwd())
        return
    except ftplib.error_perm:
        pass
    parts = [p for p in remote_dir.split("/") if p]
    # if absolute path failed, try from root
    try:
        ftp.cwd("/")
    except ftplib.error_perm:
        pass
    for part in parts:
        try:
            ftp.cwd(part)
        except ftplib.error_perm:
            try:
                ftp.mkd(part)
            except ftplib.error_perm:
                pass
            ftp.cwd(part)
    print("cwd:", ftp.pwd())


def upload_file(ftp: ftplib.FTP, local: Path, remote_name: str) -> None:
    with local.open("rb") as f:
        ftp.storbinary(f"STOR {remote_name}", f, blocksize=1024 * 256)


def upload_tree(ftp: ftplib.FTP, local_dir: Path) -> tuple[int, int]:
    ok = 0
    fail = 0
    for root, dirs, files in os.walk(local_dir):
        rel = Path(root).relative_to(local_dir)
        # navigate from base each time
        ftp.cwd(BASE_PWD)  # type: ignore[name-defined]
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
                upload_file(ftp, local, name)
                ok += 1
                if ok % 10 == 0 or name in (
                    "main.dart.js",
                    "index.html",
                    "FLEAHUB_PREVIEW_STAMP.txt",
                    "flutter_service_worker.js",
                ):
                    print(f"  OK [{ok}] {rel.as_posix()}/{name} ({local.stat().st_size})")
            except Exception as e:
                fail += 1
                print(f"  FAIL {rel.as_posix()}/{name}: {e}")
    return ok, fail


def main() -> int:
    if not ENV_PATH.is_file():
        print("missing", ENV_PATH)
        return 1
    if not LOCAL.is_dir():
        print("missing local", LOCAL)
        return 1
    cfg = load_env(ENV_PATH)
    for k in ("FTP_HOST", "FTP_USER", "FTP_PASSWORD"):
        if not cfg.get(k):
            print("missing", k)
            return 1
    print("host:", cfg["FTP_HOST"])
    print("user:", cfg["FTP_USER"])
    print("local:", LOCAL)
    print("remote_dir:", cfg.get("FTP_REMOTE_DIR") or ".")
    try:
        ftp = connect(cfg)
    except Exception as e:
        print("CONNECT FAIL:", e)
        # typo fallback fleabe -> fleaber
        host = cfg["FTP_HOST"]
        if "fleabe." in host and "fleaber." not in host:
            alt = host.replace("fleabe.", "fleaber.")
            print("retry host:", alt)
            cfg = dict(cfg)
            cfg["FTP_HOST"] = alt
            ftp = connect(cfg)
        else:
            return 2
    print("connected, home:", ftp.pwd())
    ensure_cwd(ftp, cfg.get("FTP_REMOTE_DIR") or ".")
    global BASE_PWD
    BASE_PWD = ftp.pwd()
    print("uploading to", BASE_PWD)
    # list a few names before
    try:
        names = ftp.nlst()[:15]
        print("remote sample:", names)
    except Exception as e:
        print("nlst:", e)
    ok, fail = upload_tree(ftp, LOCAL)
    print(f"done ok={ok} fail={fail}")
    # verify stamp
    try:
        ftp.cwd(BASE_PWD)
        buf: list[bytes] = []
        ftp.retrbinary("RETR FLEAHUB_PREVIEW_STAMP.txt", buf.append)
        stamp = b"".join(buf).decode("utf-8", errors="replace")
        print("--- remote stamp ---")
        print(stamp)
    except Exception as e:
        print("stamp verify fail:", e)
    try:
        size = ftp.size("main.dart.js")
        print("remote main.dart.js size:", size)
    except Exception as e:
        print("size check:", e)
    ftp.quit()
    return 0 if fail == 0 else 3


if __name__ == "__main__":
    sys.exit(main())
