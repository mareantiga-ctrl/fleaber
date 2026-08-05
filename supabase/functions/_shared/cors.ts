/** CORS allowlist (SEC-019). Native apps sem Origin → `*`. */
const ALLOWED_EXACT = new Set([
  "https://fleaber.pt",
  "https://www.fleaber.pt",
  "http://localhost",
  "http://127.0.0.1",
]);

function isAllowedOrigin(origin: string): boolean {
  const o = origin.trim();
  if (!o) return false;
  if (ALLOWED_EXACT.has(o)) return true;
  // Dev local com porta
  if (
    /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(o)
  ) {
    return true;
  }
  // Hub / staging no domínio Fleaber
  if (
    /^https:\/\/([a-z0-9-]+\.)?fleaber\.pt$/i.test(o)
  ) {
    return true;
  }
  // Extensão Chrome PS (pairing / ingest)
  if (o.startsWith("chrome-extension://")) return true;
  return false;
}

/** Headers CORS por pedido. */
export function buildCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin")?.trim() ?? "";
  let allow = "*";
  if (origin) {
    allow = isAllowedOrigin(origin) ? origin : "https://fleaber.pt";
  }
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-device-token, x-cleanup-secret, x-webhook-secret",
    "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
    Vary: "Origin",
  };
}
