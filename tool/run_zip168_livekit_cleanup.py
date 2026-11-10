#!/usr/bin/env python3
"""ZIP 168 — invoke livekit-egress-cleanup + backfill ended_at (PROD)."""
from __future__ import annotations

import json
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV = ROOT / "tool" / "live_ops_production.env"
SQL = ROOT / "tool" / "sql" / "zip168_live_ended_at_backfill.sql"
OUT = ROOT / "tool" / "reports" / "168-livekit-mux" / "proofs"
OUT.mkdir(parents=True, exist_ok=True)

PS_GET_PW = r"""
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CredMan168 {
  [DllImport("Advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("Advapi32.dll", SetLastError=true)]
  public static extern void CredFree(IntPtr cred);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize;
    public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName;
  }
  public static string Read(string target) {
    IntPtr p; if (!CredRead(target, 1, 0, out p)) return "";
    try {
      var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      if (c.CredentialBlob == IntPtr.Zero || c.CredentialBlobSize <= 0) return "";
      return Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2);
    } finally { CredFree(p); }
  }
}
"@
$pw = [CredMan168]::Read('FleaberProdPostgres')
if (-not $pw) { $pw = [CredMan168]::Read('Supabase CLI:supabase') }
[Console]::Out.Write($pw)
"""


def load_env() -> dict[str, str]:
    out: dict[str, str] = {}
    for line in ENV.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"')
    return out


def _credman_cleanup_secret() -> str:
    """Ops secret: CredMan FleaberLiveKitCleanupSecret (never commit)."""
    ps = r"""
Add-Type @"
using System; using System.Runtime.InteropServices;
public class Cred168c {
  [DllImport("Advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("Advapi32.dll", SetLastError=true)] public static extern void CredFree(IntPtr cred);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize;
    public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName;
  }
  public static string Read(string target) {
    IntPtr p; if (!CredRead(target, 1, 0, out p)) return "";
    try {
      var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      if (c.CredentialBlob == IntPtr.Zero || c.CredentialBlobSize <= 0) return "";
      return Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2);
    } finally { CredFree(p); }
  }
}
"@
[Console]::Out.Write([Cred168c]::Read('FleaberLiveKitCleanupSecret'))
"""
    try:
        return subprocess.check_output(
            ["powershell", "-NoProfile", "-Command", ps], text=True
        ).strip()
    except Exception:  # noqa: BLE001
        return ""


def invoke_cleanup(url: str, sr: str) -> dict:
    headers = {
        "Authorization": f"Bearer {sr}",
        "apikey": sr,
        "Content-Type": "application/json",
    }
    secret = _credman_cleanup_secret()
    if secret:
        headers["x-cleanup-secret"] = secret
    req = urllib.request.Request(
        f"{url.rstrip('/')}/functions/v1/livekit-egress-cleanup",
        data=b"{}",
        method="POST",
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return {"ok": False, "http": e.code, "body": body}


def apply_sql(sql: str) -> None:
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS_GET_PW], text=True
    ).strip()
    if not pw:
        raise SystemExit("no postgres password")
    try:
        import psycopg2
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"]
        )
        import psycopg2

    last = None
    for host, port in (
        ("aws-1-eu-west-1.pooler.supabase.com", 5432),
        ("aws-0-eu-west-1.pooler.supabase.com", 6543),
    ):
        try:
            conn = psycopg2.connect(
                host=host,
                port=port,
                dbname="postgres",
                user="postgres.bpmpkzwnrbmuqnhgdscf",
                password=pw,
                sslmode="require",
                connect_timeout=25,
            )
            conn.autocommit = True
            with conn.cursor() as cur:
                cur.execute(sql)
            for n in conn.notices[-10:]:
                print(n.strip())
            conn.close()
            return
        except Exception as e:  # noqa: BLE001
            last = e
    raise RuntimeError(last)


def main() -> int:
    env = load_env()
    url = env.get("SUPABASE_URL", "").rstrip("/")
    sr = env.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or len(sr) < 40:
        print("missing SUPABASE_URL / SERVICE_ROLE")
        return 2

    print("INVOKE livekit-egress-cleanup…")
    cleanup = invoke_cleanup(url, sr)
    (OUT / "livekit_egress_cleanup.json").write_text(
        json.dumps(cleanup, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps(cleanup, indent=2)[:1200])

    print("SQL backfill ended_at…")
    apply_sql(SQL.read_text(encoding="utf-8"))
    print("SQL_OK")
    return 0 if cleanup.get("ok") is True or cleanup.get("http") in (None, 200) else 1


if __name__ == "__main__":
    raise SystemExit(main())
