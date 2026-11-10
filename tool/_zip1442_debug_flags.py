import json
import os
import subprocess
import urllib.request

import psycopg2
from psycopg2.extras import RealDictCursor

# load env
for line in open("tool/live_ops_production.env", encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    os.environ.setdefault(k.strip(), v.strip())

PS = open("tool/run_zip144_2_stripe_e2e_prod.py", encoding="utf-8").read().split(
    'PS_PW = r"""'
)[1].split('"""')[0]
pw = subprocess.check_output(
    ["powershell", "-NoProfile", "-Command", PS], text=True
).strip()
conn = psycopg2.connect(
    host="aws-1-eu-west-1.pooler.supabase.com",
    port=5432,
    dbname="postgres",
    user="postgres.bpmpkzwnrbmuqnhgdscf",
    password=pw,
    sslmode="require",
)
conn.autocommit = True
cur = conn.cursor(cursor_factory=RealDictCursor)
cur.execute(
    """
  select key, enabled from public.fleaber_feature_flags
  where key like 'order_%' order by 1
"""
)
print("PG flags", cur.fetchall())
cur.execute(
    """
  select policyname, cmd, roles::text, qual::text, with_check::text
  from pg_policies
  where tablename='fleaber_feature_flags'
"""
)
print("RLS policies", cur.fetchall())
cur.execute(
    "select relrowsecurity from pg_class where relname='fleaber_feature_flags'"
)
print("RLS on", cur.fetchone())

# deploy tiny probe returning flag read via supabase-js service role
fn = "supabase/functions/zip1442-flag-probe"
os.makedirs(fn, exist_ok=True)
open(fn + "/index.ts", "w", encoding="utf-8").write(
    """
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
Deno.serve(async (req) => {
  const body = await req.json().catch(() => ({}));
  if (body?.probe_token !== "zip1442-e2e-20261104") {
    return new Response(JSON.stringify({ ok:false }), { status: 401 });
  }
  const url = Deno.env.get("SUPABASE_URL")!;
  const sr = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, sr, { auth: { persistSession: false } });
  const { data, error } = await admin.from("fleaber_feature_flags")
    .select("key,enabled")
    .eq("key", "order_shipping_delta_enabled")
    .maybeSingle();
  const { data: rpc } = await admin.rpc("batata_flag_enabled", { p_key: "order_shipping_delta_enabled" });
  return new Response(JSON.stringify({ ok:true, row:data, error, rpc }), {
    headers: { "Content-Type": "application/json" },
  });
});
"""
)

# enable flag true then probe
cur.execute(
    "update public.fleaber_feature_flags set enabled=true where key='order_shipping_delta_enabled'"
)
print("set true")

Add = r"""
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class CredUtf8Z2 {
  [DllImport("Advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredReadW(string target, int type, int flags, out IntPtr cred);
  [DllImport("Advapi32.dll", SetLastError=true)] public static extern void CredFree(IntPtr cred);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public IntPtr TargetName; public IntPtr Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize;
    public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes;
    public IntPtr TargetAlias; public IntPtr UserName;
  }
  public static string ReadUtf8(string target) {
    IntPtr p; if (!CredReadW(target, 1, 0, out p)) return "";
    try {
      var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      byte[] b = new byte[c.CredentialBlobSize];
      Marshal.Copy(c.CredentialBlob, b, 0, c.CredentialBlobSize);
      return Encoding.UTF8.GetString(b).TrimEnd((char)0).Trim();
    } finally { CredFree(p); }
  }
}
"@
$env:SUPABASE_ACCESS_TOKEN = [CredUtf8Z2]::ReadUtf8('Supabase CLI:supabase')
npx --yes supabase functions deploy zip1442-flag-probe --project-ref bpmpkzwnrbmuqnhgdscf --yes --no-verify-jwt
"""
subprocess.check_call(["powershell", "-NoProfile", "-Command", Add])
req = urllib.request.Request(
    os.environ["SUPABASE_URL"].rstrip("/") + "/functions/v1/zip1442-flag-probe",
    data=json.dumps({"probe_token": "zip1442-e2e-20261104"}).encode(),
    headers={
        "Authorization": "Bearer " + os.environ["SUPABASE_ANON_KEY"],
        "apikey": os.environ["SUPABASE_ANON_KEY"],
        "Content-Type": "application/json",
    },
    method="POST",
)
print("EDGE flag read", urllib.request.urlopen(req).read().decode())
subprocess.call(
    [
        "powershell",
        "-NoProfile",
        "-Command",
        Add.split("npx")[0]
        + "npx --yes supabase functions delete zip1442-flag-probe --project-ref bpmpkzwnrbmuqnhgdscf --yes",
    ]
)
cur.execute(
    "update public.fleaber_feature_flags set enabled=false where key='order_shipping_delta_enabled'"
)
print("reset false")
import shutil

shutil.rmtree(fn, ignore_errors=True)
