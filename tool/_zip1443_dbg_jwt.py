import base64
import json
import os
import subprocess
from pathlib import Path

# get edge sr via probe pieces from last run — re-auth probe quickly
import importlib.util

spec = importlib.util.spec_from_file_location(
    "z1442", Path("tool/run_zip144_2_stripe_e2e_prod.py")
)
z = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z)
z.load_env()
probe = z.deploy_secret_probe()
sr = probe["service_role_key"]
print("sr_len", len(sr), "parts", len(sr.split(".")))
part = sr.split(".")[1]
norm = part.replace("-", "+").replace("_", "/")
pad = "" if len(norm) % 4 == 0 else "=" * (4 - len(norm) % 4)
try:
    claims = json.loads(base64.b64decode(norm + pad))
    print("claims_role", claims.get("role"), "ref", claims.get("ref"))
except Exception as e:
    print("parse_fail", e)
# Compare to local env if any
local = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
print("local_same", local == sr if local else "no_local")
