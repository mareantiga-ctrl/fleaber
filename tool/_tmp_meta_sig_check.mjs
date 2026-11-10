/** Local mock: HMAC signature verify (mirrors meta_webhook_crypto.ts). No secrets. */
import { createHmac, timingSafeEqual } from "node:crypto";

function verify(raw, header, secret) {
  const m = String(header || "").match(/^sha256=(.+)$/i);
  if (!m) return false;
  const expected = Buffer.from(m[1].trim().toLowerCase(), "hex");
  const actual = createHmac("sha256", secret).update(raw).digest();
  if (expected.length !== actual.length) return false;
  return timingSafeEqual(expected, actual);
}

const secret = "test_app_secret_not_real";
const body = JSON.stringify({ object: "page", entry: [] });
const good = "sha256=" + createHmac("sha256", secret).update(body).digest("hex");
const bad = "sha256=" + "ab".repeat(32);

const results = {
  valid_signature: verify(body, good, secret) === true,
  invalid_signature: verify(body, bad, secret) === false,
  missing_header: verify(body, null, secret) === false,
};
console.log(JSON.stringify(results, null, 2));
process.exit(results.valid_signature && results.invalid_signature && results.missing_header ? 0 : 1);
