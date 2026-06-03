/**
 * Supabase Auth — Send SMS Hook → BulkGate (transactional).
 * Secrets: BULKGATE_APPLICATION_ID, BULKGATE_APPLICATION_TOKEN,
 *          SEND_SMS_HOOK_SECRET, optional BULKGATE_SENDER_LABEL (default Fleaber)
 *
 * Erros: HTTP 200 + JSON { error: { http_code, message } } (requisito GoTrue).
 */
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

const BULKGATE_URL =
  "https://portal.bulkgate.com/api/1.0/simple/transactional";

type ParsedPhone = { number: string; country: string };

/** E.164 → BulkGate `number` + ISO country (pt, es, …). */
function parsePhoneForBulkGate(e164: string): ParsedPhone | null {
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
    if (digits.startsWith(prefix) && digits.length > prefix.length + 8) {
      return { number: digits.slice(prefix.length), country };
    }
  }

  if (digits.length === 9) {
    return { number: digits, country: "pt" };
  }

  return { number: digits, country: "pt" };
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
    (typeof user.phone === "string" ? user.phone : null) ??
    (typeof root.phone === "string" ? root.phone : null);
  const otp =
    (typeof sms.otp === "string" ? sms.otp : null) ??
    (typeof root.otp === "string" ? root.otp : null);
  return { phone: phone ?? undefined, otp: otp ?? undefined };
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

  const payload = await req.text();
  const headers = Object.fromEntries(req.headers);
  const base64Secret = hookSecret.replace(/^v1,whsec_/, "");

  try {
    const wh = new Webhook(base64Secret);
    const verified = wh.verify(payload, headers);
    const { phone, otp } = extractOtpPayload(verified);

    if (!phone?.trim() || !otp?.trim()) {
      console.error("send-sms-bulkgate missing fields", { phone, otp });
      return hookError("Missing phone or OTP in hook payload", 400);
    }

    const parsed = parsePhoneForBulkGate(phone.trim());
    if (!parsed) {
      return hookError(`Invalid phone for BulkGate: ${phone}`, 400);
    }

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
      console.error("BulkGate error", result.status, result.body);
      return hookError(
        `BulkGate HTTP ${result.status}: ${result.body.slice(0, 500)}`,
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
    console.error("send-sms-bulkgate", e);
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
