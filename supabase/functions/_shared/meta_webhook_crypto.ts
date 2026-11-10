/** Meta webhook X-Hub-Signature-256 (HMAC SHA-256, hex). No secrets logged. */

export async function verifyMetaWebhookSignature(
  rawBody: string,
  signatureHeader: string | null,
  appSecret: string,
): Promise<boolean> {
  if (!signatureHeader || !appSecret) return false;
  const m = signatureHeader.match(/^sha256=(.+)$/i);
  if (!m) return false;
  const expectedHex = m[1].trim().toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(expectedHex)) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(appSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(rawBody),
  );
  const actualHex = [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return timingSafeEqualHex(actualHex, expectedHex);
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) {
    out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return out === 0;
}

export function metaAppSecretFromEnv(): string {
  return (
    Deno.env.get("META_APP_SECRET") ??
    Deno.env.get("FACEBOOK_APP_SECRET") ??
    ""
  ).trim();
}

export function metaWebhookVerifyTokenFromEnv(): string {
  return (Deno.env.get("META_WEBHOOK_VERIFY_TOKEN") ?? "").trim();
}
