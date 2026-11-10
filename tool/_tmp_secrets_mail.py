import json
import subprocess
from pathlib import Path

raw = subprocess.check_output(
    [
        "npx",
        "supabase",
        "secrets",
        "list",
        "--project-ref",
        "bpmpkzwnrbmuqnhgdscf",
    ],
    shell=True,
    text=True,
    encoding="utf-8",
    errors="replace",
)
Path("tool/reports/ponto7_email_audit_20261030/_secrets_raw.json").write_text(
    raw, encoding="utf-8"
)
d = json.loads(raw)
names = sorted(s["name"] for s in d.get("secrets", []))
mailish = [
    n
    for n in names
    if any(x in n.upper() for x in ("RESEND", "MAIL", "SMTP", "FROM"))
]
out = {
    "mailish_secret_names": mailish,
    "has_RESEND_API_KEY": "RESEND_API_KEY" in names,
    "has_MAIL_FROM": "MAIL_FROM" in names,
}
print(json.dumps(out, indent=2))
Path("tool/reports/ponto7_email_audit_20261030/secrets_mail_presence.json").write_text(
    json.dumps(out, indent=2), encoding="utf-8"
)
