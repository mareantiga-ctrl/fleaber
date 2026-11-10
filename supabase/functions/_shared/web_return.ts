/** Allowlist de origens de retorno web (anti open-redirect). Alinhado a CORS Fleaber. */

const ALLOWED_HOSTS = new Set([
  "fleaber.pt",
  "www.fleaber.pt",
  "fleaber.app",
  "www.fleaber.app",
  "localhost",
  "127.0.0.1",
]);

function hostAllowed(hostname: string): boolean {
  const h = hostname.toLowerCase();
  // E1930-P3: só hosts exactos (sem *.fleaber.pt → attacker.fleaber.pt).
  return ALLOWED_HOSTS.has(h);
}

/** BI-P2: rejeitar IP decimal/octal/hex e formas curtas (127.1) que o URL parser
 *  normaliza para 127.0.0.1 / localhost. */
function isSuspiciousHostname(hostname: string): boolean {
  const h = hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (/^\d+$/.test(h)) return true; // IPv4 decimal
  if (/^0x[0-9a-f]+$/i.test(h)) return true;
  if (/^0[0-7]+$/.test(h)) return true;
  // 127.1 / 127.0.1 / 8.8 — formas curtas (não 4 octetos)
  if (/^\d{1,3}(\.\d{1,3}){1,2}$/.test(h)) return true;
  return false;
}

/**
 * Aceita bases SPA tipo `https://fleaber.pt/fleahub` ou `https://fleaber.pt/#`.
 * Rejeita `https://evil.com/...`. Devolve a string original se válida; senão null.
 */
export function sanitizeWebReturnOrigin(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (!trimmed || trimmed.length > 256) return null;
  if (/[\s<>"']/.test(trimmed)) return null;

  const withoutHash = trimmed.split("#")[0] ?? trimmed;

  // BP/BI: o parser URL pode colapsar `https://2130706433` → host 127.0.0.1.
  // Verificar o authority CRU antes do parse.
  const auth = withoutHash.match(/^https?:\/\/([^/?#]+)/i);
  if (auth) {
    const rawHost = (auth[1] ?? "").replace(/^\[|\]$/g, "").split(":")[0] ?? "";
    if (isSuspiciousHostname(rawHost)) return null;
  }

  let url: URL;
  try {
    url = new URL(withoutHash);
  } catch {
    return null;
  }

  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  if (isSuspiciousHostname(url.hostname)) return null;
  // Se o input não era literalmente localhost/127.0.0.1, não aceitar após colapso
  if (auth) {
    const rawHost = ((auth[1] ?? "").replace(/^\[|\]$/g, "").split(":")[0] ?? "")
      .toLowerCase();
    const parsed = url.hostname.toLowerCase();
    if (
      (parsed === "127.0.0.1" || parsed === "localhost") &&
      rawHost !== "127.0.0.1" &&
      rawHost !== "localhost"
    ) {
      return null;
    }
  }
  if (
    url.protocol === "http:" &&
    url.hostname !== "localhost" &&
    url.hostname !== "127.0.0.1"
  ) {
    return null;
  }
  if (!hostAllowed(url.hostname)) return null;
  // Sem credenciais / userinfo
  if (url.username || url.password) return null;

  return trimmed;
}

/**
 * Location segura para redirect pós-Connect.
 * ZIP 182: preservar base Hub (`/fleahub/#` ou `/fleahub`) — igual ao regresso
 * Checkout (`webReturnOrigin + /stripe-success`). Antes só `${origin}/wallet`,
 * o que saía da SPA fleahub e podia 404.
 */
export function safeWalletReturnLocation(webReturnOrigin: string): string | null {
  const safe = sanitizeWebReturnOrigin(webReturnOrigin);
  if (!safe) return null;
  try {
    // Validar host no authority sem destruir path/hash do deploy Hub.
    const withoutHash = safe.split("#")[0] ?? safe;
    const u = new URL(
      withoutHash.includes("://") ? withoutHash : `https://${withoutHash}`,
    );
    if (!hostAllowed(u.hostname)) return null;
    const base = safe.replace(/\/$/, "");
    // Ex.: https://fleaber.pt/fleahub/# → …/fleahub/#/wallet
    //      https://fleaber.pt → …/wallet
    return `${base}/wallet`;
  } catch {
    return null;
  }
}
