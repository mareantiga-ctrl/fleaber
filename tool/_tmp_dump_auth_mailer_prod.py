"""Read-only dump of PROD auth mailer-related config (secrets redacted)."""
from __future__ import annotations

import json
import subprocess
import urllib.request
from pathlib import Path

PS = r"""
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CredManMail2 {
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
[Console]::Out.Write(([CredManMail2]::Read('Supabase CLI:supabase')).Trim())
"""

OUT = Path("tool/reports/ponto7_email_audit_20261030")
OUT.mkdir(parents=True, exist_ok=True)


def main() -> int:
    token = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", PS],
        text=True,
        encoding="utf-8",
        errors="replace",
    ).strip()
    if not token:
        print("NO_TOKEN")
        return 2
    req = urllib.request.Request(
        "https://api.supabase.com/v1/projects/bpmpkzwnrbmuqnhgdscf/config/auth",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        auth = json.loads(resp.read().decode("utf-8"))

    interesting = {}
    templates = {}
    for k, v in sorted(auth.items()):
        lk = k.lower()
        if not any(
            x in lk
            for x in (
                "mail",
                "smtp",
                "subject",
                "sender",
                "template",
                "autoconfirm",
                "confirm",
                "recover",
                "invite",
                "magic",
                "otp",
                "rate",
            )
        ):
            continue
        if any(x in lk for x in ("pass", "secret", "key")):
            interesting[k] = "(set)" if v else "(empty)"
        elif isinstance(v, str) and len(v) > 180 and (
            "html" in lk or "content" in lk or "body" in lk or "template" in lk
        ):
            templates[k] = v
            interesting[k] = f"(html_or_text len={len(v)})"
        else:
            interesting[k] = v

    (OUT / "prod_auth_mailer_config.json").write_text(
        json.dumps(interesting, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    # Save full templates separately for audit (no secrets)
    for k, v in templates.items():
        safe = k.replace(".", "_").replace("/", "_")
        (OUT / f"prod_template_{safe}.html").write_text(v, encoding="utf-8")
    print(json.dumps(interesting, indent=2, ensure_ascii=False))
    print("templates_saved", len(templates))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
