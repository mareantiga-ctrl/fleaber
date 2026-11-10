#!/usr/bin/env python3
import subprocess
from pathlib import Path

import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "supabase/migrations/20261104090000_feature_flags_service_role_select_batata.sql"
PS = open(ROOT / "tool/apply_zip144_hotfix_prod.py", encoding="utf-8").read().split(
    'PS = r"""'
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
conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
cur = conn.cursor()
cur.execute(SQL.read_text(encoding="utf-8"))
cur.execute(
    """
  select has_table_privilege('service_role', 'public.fleaber_feature_flags', 'select')
"""
)
print("GRANT OK select=", cur.fetchone()[0])
cur.close()
conn.close()
