"""Read-only probes for email-related PROD facts (no sends)."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tool" / "reports" / "ponto7_email_audit_20261030"
OUT.mkdir(parents=True, exist_ok=True)

PS = r"""
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CredPgMail {
  [DllImport("Advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("Advapi32.dll", SetLastError=true)] public static extern bool CredFree(IntPtr cred);
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
[Console]::Out.Write(([CredPgMail]::Read('FleaberProdPostgres')).Trim())
"""


def main() -> int:
    pw = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS],
        text=True,
        encoding="utf-8",
        errors="replace",
    ).strip()
    pw = pw.replace("\x00", "").strip()
    import psycopg2

    conn = psycopg2.connect(
        host="aws-1-eu-west-1.pooler.supabase.com",
        port=5432,
        dbname="postgres",
        user="postgres.bpmpkzwnrbmuqnhgdscf",
        password=pw,
        sslmode="require",
        connect_timeout=20,
    )
    cur = conn.cursor()
    facts = {}
    # delivery log email channel activity
    cur.execute(
        """
        select status, count(*)
        from public.notification_delivery_log
        where channel = 'email'
        group by 1 order by 2 desc
        """
    )
    facts["delivery_log_email_by_status"] = [
        {"status": r[0], "n": r[1]} for r in cur.fetchall()
    ]
    cur.execute(
        """
        select kind, status, left(coalesce(error_text,''),80), created_at::text
        from public.notification_delivery_log
        where channel = 'email'
        order by created_at desc limit 10
        """
    )
    facts["delivery_log_email_recent"] = [
        {"kind": r[0], "status": r[1], "error": r[2], "at": r[3]}
        for r in cur.fetchall()
    ]
    # kinds that exist in inbox that map to commercial email
    cur.execute(
        """
        select kind, count(*) from public.user_notifications
        where kind in (
          'seguro_fleaber_paid','order_paid_buyer','order_paid_seller',
          'reservation_order_shipped'
        )
        or kind like 'helper_invitation%'
        or kind like 'price_offer%'
        or kind = 'chat_message'
        group by 1 order by 2 desc
        limit 30
        """
    )
    facts["inbox_kinds_sample"] = [
        {"kind": r[0], "n": r[1]} for r in cur.fetchall()
    ]
    conn.close()

    # Code scan: receipt_email in stripe funcs
    stripe_hits = []
    for p in (ROOT / "supabase" / "functions").rglob("*.ts"):
        t = p.read_text(encoding="utf-8", errors="replace")
        if re.search(r"receipt_email|customer_email|email_receipt|send.*mail", t, re.I):
            for i, line in enumerate(t.splitlines(), 1):
                if re.search(
                    r"receipt_email|customer_email|email_receipt|Resend|MAIL_FROM",
                    line,
                    re.I,
                ):
                    stripe_hits.append(
                        {"file": str(p.relative_to(ROOT)), "line": i, "text": line.strip()[:160]}
                    )
    facts["code_email_hits_edge"] = stripe_hits[:40]

    # legal emails from app
    legal = ROOT / "lib" / "legal" / "legal_texts.dart"
    if legal.exists():
        txt = legal.read_text(encoding="utf-8", errors="replace")
        facts["app_contact_emails"] = sorted(
            set(re.findall(r"[a-zA-Z0-9._%+-]+@fleaber\.pt", txt))
        )

    (OUT / "probe_facts.json").write_text(
        json.dumps(facts, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps(facts, indent=2, ensure_ascii=False)[:4000])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
