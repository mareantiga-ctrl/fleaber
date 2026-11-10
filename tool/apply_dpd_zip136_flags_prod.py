#!/usr/bin/env python3
"""ZIP 136 — activar tarifas DPD Célia em PROD; create/sync continuam OFF."""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

SQL = r"""
-- Tarifas Célia ao comprador (sem create comercial)
update public.fleaber_feature_flags
set enabled = true, updated_at = now()
where key in ('dpd_shipping_rates_live', 'dpd_home_charges_enabled');

-- Garantir create/sync OFF no ledger de flags (se existirem)
update public.fleaber_feature_flags
set enabled = false, updated_at = now()
where key in ('dpd_qa_create_enabled', 'dpd_tracking_sync_enabled');

-- Confirmar tabela Célia
insert into public.dpd_shipping_rates (modality, weight_band, max_kg, price_eur, notes)
values
  ('shop_to_shop', '0_3', 3, 2.99, 'ZIP136 Célia IVA incl.'),
  ('shop_to_shop', '3_6', 6, 3.49, 'ZIP136 Célia IVA incl.'),
  ('shop_to_shop', '6_10', 10, 4.99, 'ZIP136 Célia IVA incl.'),
  ('shop_to_home', '0_3', 3, 4.49, 'ZIP136 Célia + prémio Home/combustível'),
  ('shop_to_home', '3_6', 6, 5.99, 'ZIP136 Célia + prémio Home/combustível'),
  ('shop_to_home', '6_10', 10, 8.99, 'ZIP136 Célia + prémio Home/combustível')
on conflict (modality, weight_band) do update
  set max_kg = excluded.max_kg,
      price_eur = excluded.price_eur,
      notes = excluded.notes,
      active = true,
      updated_at = now();

select key, enabled from public.fleaber_feature_flags
where key like 'dpd_%' order by key;

select modality, weight_band, price_eur, active
from public.dpd_shipping_rates
order by modality, weight_band;

-- Quote smoke (S2S 1kg, S2H 5kg)
select 's2s_1kg' as t, public.batata_dpd_quote_shipping('shop_to_shop', 1, null, false);
select 's2h_5kg' as t, public.batata_dpd_quote_shipping('shop_to_home', 5, null, false);
select 'legacy_off' as t, public.batata_dpd_quote_shipping('shop_to_shop', 1, null, false)->'legacy';
"""


def credman_password(target: str) -> str | None:
    ps = rf"""
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredManDpd136 {{
  [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr ptr);
  [DllImport("advapi32.dll", EntryPoint="CredFree")]
  public static extern void CredFree(IntPtr ptr);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {{
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public int CredentialBlobSize; public IntPtr CredentialBlob;
    public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName;
  }}
  public static string Read(string t) {{
    IntPtr p;
    if (!CredRead(t, 1, 0, out p)) return null;
    var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
    var s = Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2);
    CredFree(p); return s;
  }}
}}
"@
$pw = [CredManDpd136]::Read('{target}')
if ($pw) {{ Write-Output $pw }}
"""
    r = subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    pw = (r.stdout or "").strip()
    return pw or None


def main() -> int:
    pw = credman_password("FleaberProdPostgres")
    if not pw:
        print("no CredMan FleaberProdPostgres")
        return 2
    try:
        import psycopg2
    except ImportError:
        print("pip install psycopg2-binary")
        return 3

    conn = psycopg2.connect(
        host="aws-1-eu-west-1.pooler.supabase.com",
        port=5432,
        dbname="postgres",
        user="postgres.bpmpkzwnrbmuqnhgdscf",
        password=pw,
        sslmode="require",
        connect_timeout=25,
    )
    conn.autocommit = True
    out_lines: list[str] = []
    with conn.cursor() as cur:
        for stmt in SQL.split(";"):
            s = stmt.strip()
            if not s:
                continue
            cur.execute(s)
            if cur.description:
                rows = cur.fetchall()
                cols = [d[0] for d in cur.description]
                out_lines.append(" | ".join(cols))
                for row in rows:
                    out_lines.append(" | ".join(str(x) for x in row))
                out_lines.append("---")
    conn.close()
    report = Path(__file__).resolve().parents[1] / "tool" / "reports" / "136-dpd-qa-labels-portes" / "03-flags-bd.txt"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text("\n".join(out_lines), encoding="utf-8")
    print("WROTE", report)
    print("\n".join(out_lines[:40]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
