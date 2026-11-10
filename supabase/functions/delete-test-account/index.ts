import { buildCorsHeaders } from "../_shared/cors.ts";
import { checkAnonRate } from "../_shared/anon_rate.ts";
import { assertDestructiveHarnessAllowed } from "../_shared/destructive_harness_gate.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
const CONFIRM_PHRASE = "APAGAR TUDO";

type DeleteTestAccountRequest = {
  confirm?: string;
};

async function removeStoragePrefix(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  prefix: string,
): Promise<number> {
  let removed = 0;
  const { data: entries, error } = await admin.storage.from(bucket).list(prefix, {
    limit: 200,
  });
  if (error || !entries?.length) {
    return removed;
  }

  const paths: string[] = [];
  for (const entry of entries) {
    const path = `${prefix}/${entry.name}`;
    if (entry.id) {
      paths.push(path);
      continue;
    }
    removed += await removeStoragePrefix(admin, bucket, path);
  }

  if (paths.length) {
    const { error: removeError } = await admin.storage.from(bucket).remove(paths);
    if (!removeError) {
      removed += paths.length;
    }
  }
  return removed;
}

let corsHeaders: Record<string, string> = { "Access-Control-Allow-Origin": "*" };

Deno.serve(async (req) => {
  corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const allowNuke = Deno.env.get("ALLOW_TEST_ACCOUNT_NUKE") === "true";
    const allowlistRaw = (Deno.env.get("TEST_NUKE_ALLOWLIST_USER_IDS") ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0);

    // Hard stop: staging + sk_test_ + FLEABER_ALLOW_DESTRUCTIVE_HARNESS=true.
    const gate = assertDestructiveHarnessAllowed();
    if (!gate.ok) {
      return jsonError(gate.error, gate.status);
    }
    if (!allowNuke) {
      return jsonError(
        "Função desactivada. Define ALLOW_TEST_ACCOUNT_NUKE=true no projecto staging.",
        403,
      );
    }
    if (allowlistRaw.length === 0) {
      return jsonError(
        "Nuke bloqueado: define TEST_NUKE_ALLOWLIST_USER_IDS (UUIDs) no staging.",
        403,
      );
    }
    if (!serviceRoleKey) {
      return jsonError("Service role em falta.", 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonError("Sessão em falta.", 401);
    }

    const body = (await req.json()) as DeleteTestAccountRequest;
    if ((body.confirm ?? "").trim() !== CONFIRM_PHRASE) {
      return jsonError(`Confirmação inválida. Escreve exactamente: ${CONFIRM_PHRASE}`, 400);
    }

    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return jsonError("Sessão inválida.", 401);
    }
    if (!allowlistRaw.includes(user.id)) {
      return jsonError(
        "Esta conta não está na allowlist de nuke de testes.",
        403,
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // SEC-038: anti-spam nuke staging — fail-open. 5/h >> uso QA real.
    const nukeRate = await checkAnonRate(
      admin,
      `delete_test_account:${user.id}`,
      "delete-test-account",
      5,
    );
    if (nukeRate.rateLimited) {
      return jsonError("Demasiados pedidos de apagar conta. Espera um pouco.", 429);
    }

    // FASE3B: repor stock claimed antes de apagar orders (anti deriva qty).
    const { data: restoreStats, error: restoreErr } = await admin.rpc(
      "staging_restore_stock_before_nuke",
      { p_user_id: user.id },
    );
    if (restoreErr) {
      throw new Error(`staging_restore_stock_before_nuke: ${restoreErr.message}`);
    }

    const { data: stats, error: rpcError } = await admin.rpc(
      "staging_nuke_user_data",
      { p_user_id: user.id },
    );
    if (rpcError) {
      throw new Error(`staging_nuke_user_data: ${rpcError.message}`);
    }

    let storageRemoved = 0;
    for (const prefix of [`profile_photos/${user.id}`, `product_photos/${user.id}`]) {
      storageRemoved += await removeStoragePrefix(admin, "chat_media", prefix);
    }

    const { error: deleteAuthError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteAuthError) {
      throw new Error(`deleteUser: ${deleteAuthError.message}`);
    }

    return new Response(
      JSON.stringify({
        ok: true,
        user_id: user.id,
        restore: restoreStats,
        stats,
        storage_files_removed: storageRemoved,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonError(message, 500);
  }
});

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ ok: false, error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
