import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

/**
 * Produção: pedido de eliminação da própria conta (JWT).
 * Anonimiza PII via RPC; bane Auth (não apaga UUID — FK orders → auth.users).
 * Staging nuke completo continua em delete-test-account.
 */

const CONFIRM_PHRASE = "ELIMINAR CONTA";

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonError("Method not allowed", 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !anon || !serviceRole) {
      return jsonError("Server misconfigured", 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonError("Sessão em falta.", 401);

    const body = await req.json().catch(() => ({})) as {
      confirm?: string;
      confirmation_code?: string;
    };
    if ((body.confirm ?? "").trim() !== CONFIRM_PHRASE) {
      return jsonError(
        `Confirmação inválida. Escreve exactamente: ${CONFIRM_PHRASE}`,
        400,
      );
    }

    const userClient = createClient(supabaseUrl, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) return jsonError("Sessão inválida.", 401);

    const admin = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const rate = await checkAnonRate(
      admin,
      `acct_del:${user.id}`,
      "request-account-deletion",
      5,
    );
    if (rate.rateLimited) {
      return jsonError("Demasiados pedidos. Tenta mais tarde.", 429);
    }

    const code =
      (body.confirmation_code ?? "").trim() ||
      `APP-${Date.now().toString(36)}-${crypto.randomUUID().slice(0, 8)}`
        .toUpperCase();

    const { data: result, error: rpcError } = await admin.rpc(
      "batata_anonymize_account_for_deletion",
      {
        p_user_id: user.id,
        p_source: "app",
        p_confirmation_code: code,
        p_facebook_user_id: null,
        p_force_pii_only: false,
      },
    );
    if (rpcError) {
      return jsonError(rpcError.message, 500);
    }

    const map = (result ?? {}) as Record<string, unknown>;
    if (map.blocked === true) {
      return new Response(
        JSON.stringify({
          ok: false,
          blocked: true,
          status: map.status,
          confirmation_code: map.confirmation_code ?? code,
          obligations: map.obligations,
          message:
            "Não é possível eliminar a conta enquanto houver encomendas, " +
            "disputas, directos activos ou saldo na carteira. " +
            "Conclui ou resolve esses assuntos e tenta de novo, ou contacta legal@fleaber.pt.",
        }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Impedir novo login sem apagar o UUID (FK orders → auth.users).
    const { error: banError } = await admin.auth.admin.updateUserById(user.id, {
      ban_duration: "876000h",
      user_metadata: {
        ...(user.user_metadata ?? {}),
        fleaber_account_deleted: true,
        fleaber_deletion_code: map.confirmation_code ?? code,
      },
    });
    if (banError) {
      console.error("ban failed", banError);
      return jsonError(
        `Anonimização OK mas ban Auth falhou: ${banError.message}`,
        500,
      );
    }

    return new Response(
      JSON.stringify({
        ok: true,
        status: map.status ?? "anonymized",
        confirmation_code: map.confirmation_code ?? code,
        result: map,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    return jsonError(e instanceof Error ? e.message : String(e), 500);
  }
});

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ ok: false, error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
