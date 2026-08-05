import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

/**
 * Meta / Facebook Data Deletion Request Callback.
 * Dashboard → Settings → Data Deletion Request URL:
 *   https://<project>.supabase.co/functions/v1/meta-data-deletion
 *
 * Docs: https://developers.facebook.com/docs/development/create-an-app/app-dashboard/data-deletion-callback
 */

function base64UrlDecode(input: string): Uint8Array {
  const padded = input.replace(/-/g, "+").replace(/_/g, "/");
  const padLen = (4 - (padded.length % 4)) % 4;
  const b64 = padded + "=".repeat(padLen);
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function hmacSha256(secret: string, data: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(data),
  );
  return new Uint8Array(sig);
}

function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a[i] ^ b[i];
  return out === 0;
}

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const appSecret = Deno.env.get("FACEBOOK_APP_SECRET") ??
      Deno.env.get("META_APP_SECRET") ??
      "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const publicStatusBase =
      (Deno.env.get("FLEABER_WEB_APP_URL") ?? "https://fleaber.pt").replace(
        /\/$/,
        "",
      );

    if (req.method === "GET") {
      return new Response(
        JSON.stringify({
          ok: true,
          info:
            "POST signed_request from Meta Data Deletion. Status page: " +
            `${publicStatusBase}/data-deletion.html`,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (req.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    if (!appSecret) {
      return new Response(
        JSON.stringify({ error: "FACEBOOK_APP_SECRET not configured" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const contentType = req.headers.get("content-type") ?? "";
    let signedRequest = "";
    if (contentType.includes("application/x-www-form-urlencoded")) {
      const form = await req.formData();
      signedRequest = String(form.get("signed_request") ?? "");
    } else if (contentType.includes("application/json")) {
      const body = await req.json();
      signedRequest = String(body?.signed_request ?? "");
    } else {
      const raw = await req.text();
      const params = new URLSearchParams(raw);
      signedRequest = params.get("signed_request") ?? "";
    }

    if (!signedRequest.includes(".")) {
      return new Response(JSON.stringify({ error: "Missing signed_request" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const [encodedSig, payload] = signedRequest.split(".", 2);
    const expected = await hmacSha256(appSecret, payload);
    const actual = base64UrlDecode(encodedSig);
    if (!timingSafeEqual(expected, actual)) {
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const data = JSON.parse(
      new TextDecoder().decode(base64UrlDecode(payload)),
    ) as { user_id?: string };
    const facebookUserId = String(data.user_id ?? "").trim();
    const confirmationCode =
      `FBDEL-${Date.now().toString(36)}-${crypto.randomUUID().slice(0, 8)}`
        .toUpperCase();

    // SEC-028b: anti-spam após HMAC válido — fail-open. Não apaga contas.
    if (supabaseUrl && serviceRole) {
      const supabase = createClient(supabaseUrl, serviceRole);
      const fbKey = facebookUserId.length > 0
        ? facebookUserId.slice(0, 64)
        : "unknown";
      const delRate = await checkAnonRate(
        supabase,
        `meta_del:${fbKey}`,
        "meta-data-deletion-post",
        20,
      );
      if (delRate.rateLimited) {
        return new Response(
          JSON.stringify({ error: "Too many deletion requests. Try later." }),
          {
            status: 429,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      try {
        await supabase.from("app_logs").insert({
          category: "meta.data_deletion",
          error_message:
            `facebook_data_deletion_request code=${confirmationCode} fb_user=${facebookUserId}`,
          device_info: {
            facebook_user_id: facebookUserId,
            confirmation_code: confirmationCode,
          },
        });
      } catch (e) {
        console.error("meta-data-deletion log failed", e);
      }
    }

    const statusUrl =
      `${publicStatusBase}/data-deletion.html?code=${encodeURIComponent(confirmationCode)}`;

    return new Response(
      JSON.stringify({
        url: statusUrl,
        confirmation_code: confirmationCode,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
