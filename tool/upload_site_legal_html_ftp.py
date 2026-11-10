#!/usr/bin/env python3
"""Upload privacy/terms/refunds/cookies/data-deletion.html para /www (raiz do site)."""
from __future__ import annotations

import ftplib
import ssl
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "tool" / "fleahub_ftp.local.env"
LOCAL = ROOT / "deploy" / "fleaber_pt"
FILES = (
    "privacy.html",
    "terms.html",
    "refunds.html",
    "cookies.html",
    "data-deletion.html",
)


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


def main() -> int:
    cfg = load_env(ENV_PATH)
    ftp = connect(cfg)
    # Site root (parent of fleahub)
    remote_hub = (cfg.get("FTP_REMOTE_DIR") or "/www/fleahub").rstrip("/")
    remote_www = remote_hub.rsplit("/", 1)[0] if remote_hub.endswith("fleahub") else "/www"
    ftp.cwd(remote_www)
    print("cwd:", ftp.pwd())
    ok = fail = 0
    for name in FILES:
        local = LOCAL / name
        if not local.is_file():
            print("missing", local)
            fail += 1
            continue
        try:
            with local.open("rb") as f:
                ftp.storbinary(f"STOR {name}", f)
            print("OK", name, local.stat().st_size)
            ok += 1
        except Exception as e:
            print("FAIL", name, e)
            fail += 1
    ftp.quit()
    print(f"done ok={ok} fail={fail}")
    return 0 if fail == 0 else 3


if __name__ == "__main__":
    sys.exit(main())
