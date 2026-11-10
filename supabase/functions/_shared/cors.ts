/** CORS allowlist (SEC-019 + KLM-5A + CY-P2). Native apps sem Origin → `*`. */
const ALLOWED_EXACT = new Set([
  "https://fleaber.pt",
  "https://www.fleaber.pt",
  "https://fleaber.app",
  "https://www.fleaber.app",
  "http://localhost",
  "http://127.0.0.1",
]);

function isAllowedOrigin(origin: string): boolean {
  const o = origin.trim();
  if (!o) return false;
  // Nunca reflectir extensões / file / null
  if (
    o === "null" ||
    o.startsWith("chrome-extension://") ||
    o.startsWith("moz-extension://") ||
    o.startsWith("file:")
  ) {
    return false;
  }
  if (ALLOWED_EXACT.has(o)) return true;
  // Dev local com porta
  if (/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(o)) {
    return true;
  }
  // Sem *.fleaber.pt — só exactos
  return false;
}

/** Headers CORS por pedido. Hostil → fleaber.pt (nunca ecoar Origin). */
export function buildCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin")?.trim() ?? "";
  let allow = "*";
  if (origin) {
    allow = isAllowedOrigin(origin) ? origin : "https://fleaber.pt";
  }
  // Headers do supabase-js / supabase_flutter (sem isto o Chrome no Hub
  // falha o preflight → ClientException Failed to fetch no Pagar).
  // X-Fleaber-Env: header global em SupaFlow.initialize (lib/backend/supabase).
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": [
      "authorization",
      "x-client-info",
      "apikey",
      "content-type",
      "x-device-token",
      "x-cleanup-secret",
      "x-webhook-secret",
      "x-supabase-api-version",
      "x-supabase-client-platform",
      "x-supabase-client-platform-version",
      "x-supabase-client-runtime",
      "x-supabase-client-runtime-version",
      "x-fleaber-env",
      "prefer",
      "accept-profile",
      "content-profile",
    ].join(", "),
    "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
    // Curto: evita cache de preflight antigo a bloquear headers novos.
    "Access-Control-Max-Age": "600",
    Vary: "Origin",
  };
}
