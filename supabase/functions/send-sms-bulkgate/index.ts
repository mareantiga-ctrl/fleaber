/**
 * Supabase Auth — Send SMS Hook → BulkGate (transactional).
 * Secrets: BULKGATE_APPLICATION_ID, BULKGATE_APPLICATION_TOKEN,
 *          SEND_SMS_HOOK_SECRET, optional BULKGATE_SENDER_LABEL (default Fleaber)
 * Kill-switch: OPS_SMS_SEND_ENABLED must be "1" to call BulkGate (ZIP 190).
 *
 * Erros: HTTP 200 + JSON { error: { http_code, message } } (requisito GoTrue).
 * Nunca registar OTP nem tokens nos logs.
 */
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

const BULKGATE_URL =
  "https://portal.bulkgate.com/api/1.0/simple/transactional";

type ParsedPhone = { number: string; country: string };

/** E.164 → BulkGate `number` + ISO country (pt, es, …). Exported for tests. */
export function parsePhoneForBulkGate(e164: string): ParsedPhone | null {
  const digits = e164.replace(/\D/g, "");
  if (digits.length < 9) return null;

  const known: Array<{ prefix: string; country: string }> = [
    { prefix: "351", country: "pt" },
    { prefix: "34", country: "es" },
    { prefix: "33", country: "fr" },
    { prefix: "44", country: "gb" },
    { prefix: "55", country: "br" },
  ];

  for (const { prefix, country } of known) {
    if (digits.startsWith(prefix) && digits.length >= prefix.length + 9) {
      return { number: digits.slice(prefix.length), country };
    }
  }

  if (digits.length === 9) {
    return { number: digits, country: "pt" };
  }

  return { number: digits, country: "pt" };
}

function smsSendEnabled(): boolean {
  const v = (Deno.env.get("OPS_SMS_SEND_ENABLED") ?? "").trim().toLowerCase();
  return v === "1" || v === "true" || v === "yes";
}

/** Best-effort in-isolate rate limit (resets on cold start). */
const recentByPhone = new Map<string, number[]>();
const MAX_PER_PHONE_WINDOW = 5;
const WINDOW_MS = 15 * 60 * 1000;

function rateLimited(phoneKey: string): boolean {
  const now = Date.now();
  const arr = (recentByPhone.get(phoneKey) ?? []).filter((t) =>
    now - t < WINDOW_MS
  );
  if (arr.length >= MAX_PER_PHONE_WINDOW) {
    recentByPhone.set(phoneKey, arr);
    return true;
  }
  arr.push(now);
  recentByPhone.set(phoneKey, arr);
  return false;
}

function phoneKey(e164: string): string {
  // Hash-like truncate — avoid storing full MSISDN long-term in logs.
  const d = e164.replace(/\D/g, "");
  if (d.length < 4) return "****";
  return `***${d.slice(-4)}`;
}

async function sendBulkGateSms(
  appId: string,
  appToken: string,
  to: ParsedPhone,
  text: string,
  senderLabel: string,
): Promise<{ ok: boolean; status: number; body: string }> {
  const res = await fetch(BULKGATE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-cache",
    },
    body: JSON.stringify({
      application_id: appId,
      application_token: appToken,
      number: to.number,
      country: to.country,
      text,
      unicode: true,
      sender_id: "gText",
      sender_id_value: senderLabel,
    }),
  });

  const body = await res.text();
  return { ok: res.ok, status: res.status, body };
}

/** GoTrue só lê o corpo em HTTP 200/202. */
function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function hookError(message: string, httpCode = 400): Response {
  return jsonResponse({
    error: { http_code: httpCode, message },
  });
}

function extractOtpPayload(verified: unknown): {
  phone?: string;
  otp?: string;
} {
  if (!verified || typeof verified !== "object") return {};
  const root = verified as Record<string, unknown>;
  const user = (root.user ?? root) as Record<string, unknown>;
  const sms = (root.sms ?? {}) as Record<string, unknown>;
  const phone =
    (typeof sms.phone === "string" ? sms.phone : null) ??
    (typeof user.new_phone === "string" ? user.new_phone : null) ??
    (typeof user.phone === "string" ? user.phone : null) ??
    (typeof root.phone === "string" ? root.phone : null);
  const otp =
    (typeof sms.otp === "string" ? sms.otp : null) ??
    (typeof root.otp === "string" ? root.otp : null);
  return {
    phone: phone?.trim() || undefined,
    otp: otp?.trim() || undefined,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return hookError("Method not allowed", 405);
  }

  const hookSecret = Deno.env.get("SEND_SMS_HOOK_SECRET");
  const appId = Deno.env.get("BULKGATE_APPLICATION_ID");
  const appToken = Deno.env.get("BULKGATE_APPLICATION_TOKEN");
  const senderLabel = Deno.env.get("BULKGATE_SENDER_LABEL") ?? "Fleaber";

  if (!hookSecret || !appId || !appToken) {
    return hookError(
      "Missing SEND_SMS_HOOK_SECRET, BULKGATE_APPLICATION_ID or BULKGATE_APPLICATION_TOKEN",
      500,
    );
  }

  if (!smsSendEnabled()) {
    // Config phase: hook may be wired, but paid SMS stays off until GO.
    console.error("send-sms-bulkgate blocked: OPS_SMS_SEND_ENABLED!=1");
    return hookError(
      "Envio de SMS temporariamente desactivado. Tenta mais tarde.",
      503,
    );
  }

  const payload = await req.text();
  const headers = Object.fromEntries(req.headers);
  const base64Secret = hookSecret.replace(/^v1,whsec_/, "");

  try {
    const wh = new Webhook(base64Secret);
    const verified = wh.verify(payload, headers);
    const { phone, otp } = extractOtpPayload(verified);

    if (!phone?.trim() || !otp?.trim()) {
      console.error("send-sms-bulkgate missing fields", {
        has_phone: Boolean(phone),
        has_otp: Boolean(otp),
      });
      return hookError("Missing phone or OTP in hook payload", 400);
    }

    const key = phoneKey(phone);
    if (rateLimited(key)) {
      console.error("send-sms-bulkgate rate_limited", { phone: key });
      return hookError(
        "Demasiados pedidos de SMS. Aguarda alguns minutos.",
        429,
      );
    }

    const parsed = parsePhoneForBulkGate(phone.trim());
    if (!parsed) {
      return hookError(`Invalid phone for BulkGate: ${key}`, 400);
    }

    // OTP never logged.
    const text =
      `Fleaber: o teu codigo de verificacao e ${otp.trim()}. Valido por alguns minutos.`;

    const result = await sendBulkGateSms(
      appId,
      appToken,
      parsed,
      text,
      senderLabel,
    );

    if (!result.ok) {
      console.error("BulkGate error", result.status, result.body.slice(0, 200));
      const low = result.body.toLowerCase();
      if (low.includes("credit") || low.includes("balance") ||
        low.includes("insufficient")) {
        return hookError(
          "Saldo SMS insuficiente. Contacta o suporte Fleaber.",
          502,
        );
      }
      return hookError(
        `BulkGate HTTP ${result.status}: fornecedor indisponivel`,
        502,
      );
    }

    let parsedJson: { data?: { status?: string }; error?: string } = {};
    try {
      parsedJson = JSON.parse(result.body);
    } catch {
      /* non-json ok */
    }

    if (parsedJson.error) {
      return hookError(`BulkGate: ${parsedJson.error}`, 502);
    }

    return jsonResponse({});
  } catch (e) {
    console.error("send-sms-bulkgate", e instanceof Error ? e.message : "err");
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.toLowerCase().includes("signature") ||
      msg.toLowerCase().includes("webhook")) {
      return hookError(
        "Hook secret inválido — confirma SEND_SMS_HOOK_SECRET no Dashboard",
        401,
      );
    }
    return hookError(`Hook failed: ${msg}`, 500);
  }
});
