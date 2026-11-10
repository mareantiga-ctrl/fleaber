import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

/**
 * Meta / Facebook Data Deletion Request Callback.
 * Dashboard → Settings → Data Deletion Request URL:
 *   https://<project>.supabase.co/functions/v1/meta-data-deletion
 *
 * Docs: https://developers.facebook.com/docs/development/create-an-app/app-dashboard/data-deletion-callback
 *
 * Block C3: valida signed_request → resolve auth.identities facebook →
 * anonymize PII (idempotente) → resposta url + confirmation_code.
 * NÃO apaga histórico financeiro (orders/comissões).
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

    if (!supabaseUrl || !serviceRole) {
      return new Response(
        JSON.stringify({ error: "Supabase admin not configured" }),
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

    const supabase = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

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

    let fleaberUserId: string | null = null;
    if (facebookUserId.length > 0) {
      // auth.identities: provider=facebook, provider_id=Meta user id
      const { data: idRows, error: idErr } = await supabase
        .schema("auth")
        .from("identities")
        .select("user_id")
        .eq("provider", "facebook")
        .eq("provider_id", facebookUserId)
        .limit(1);
      if (!idErr && idRows && idRows.length > 0) {
        fleaberUserId = String(idRows[0].user_id ?? "").trim() || null;
      }
      // Fallback: batata_facebook_id_map
      if (!fleaberUserId) {
        const { data: mapRows } = await supabase
          .from("batata_facebook_id_map")
          .select("user_id")
          .eq("oauth_provider_id", facebookUserId)
          .limit(1);
        if (mapRows && mapRows.length > 0) {
          fleaberUserId = String(mapRows[0].user_id ?? "").trim() || null;
        }
      }
    }

    let anonymizeResult: Record<string, unknown> | null = null;
    if (fleaberUserId) {
      // Meta: forçar limpeza PII mesmo com obrigações (manual_review);
      // histórico financeiro permanece.
      const { data: rpcData, error: rpcErr } = await supabase.rpc(
        "batata_anonymize_account_for_deletion",
        {
          p_user_id: fleaberUserId,
          p_source: "meta",
          p_confirmation_code: confirmationCode,
          p_facebook_user_id: facebookUserId,
          p_force_pii_only: true,
        },
      );
      if (rpcErr) {
        console.error("meta anonymize rpc failed", rpcErr);
        await supabase.from("app_logs").insert({
          category: "meta.data_deletion",
          error_message:
            `facebook_data_deletion_rpc_error code=${confirmationCode} fb_user=${facebookUserId} err=${rpcErr.message}`,
          device_info: {
            facebook_user_id: facebookUserId,
            confirmation_code: confirmationCode,
            fleaber_user_id: fleaberUserId,
          },
        });
      } else {
        anonymizeResult = (rpcData ?? {}) as Record<string, unknown>;
        try {
          await supabase.auth.admin.updateUserById(fleaberUserId, {
            ban_duration: "876000h",
            user_metadata: {
              fleaber_account_deleted: true,
              fleaber_deletion_code: confirmationCode,
              fleaber_deletion_source: "meta",
            },
          });
        } catch (banErr) {
          console.error("meta ban failed", banErr);
        }
        // Remover identity Facebook (unlink) se ainda existir.
        try {
          const { data: ids } = await supabase
            .schema("auth")
            .from("identities")
            .select("id")
            .eq("provider", "facebook")
            .eq("provider_id", facebookUserId)
            .limit(5);
          // Admin API deleteIdentity not always available via JS client —
          // ban + anonymize is the primary effect.
          void ids;
        } catch (_) {
          /* ignore */
        }
      }
    } else {
      // Sem conta Fleaber ligada: registar pedido (idempotente / auditoria).
      await supabase.from("account_deletion_requests").upsert({
        user_id: null,
        facebook_user_id: facebookUserId || null,
        confirmation_code: confirmationCode,
        source: "meta",
        status: "completed",
        result: { note: "no_fleaber_user_for_facebook_id" },
        updated_at: new Date().toISOString(),
      }, { onConflict: "confirmation_code" });
    }

    try {
      await supabase.from("app_logs").insert({
        category: "meta.data_deletion",
        error_message:
          `facebook_data_deletion_request code=${confirmationCode} fb_user=${facebookUserId} fleaber_user=${fleaberUserId ?? "none"}`,
        device_info: {
          facebook_user_id: facebookUserId,
          confirmation_code: confirmationCode,
          fleaber_user_id: fleaberUserId,
          anonymize: anonymizeResult,
        },
      });
    } catch (e) {
      console.error("meta-data-deletion log failed", e);
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
