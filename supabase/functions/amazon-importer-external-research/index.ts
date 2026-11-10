/**
 * DESACTIVADO (ZIP 155) — pesquisa de preços só na Amazon (ES→IT→DE→FR).
 * Mantido o endpoint para não partir clientes antigos; responde disabled.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !anonKey) {
    return json({ ok: false, error: "missing_env" }, 200);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  if (!userData.user?.id) return json({ ok: false, error: "auth_required" }, 200);

  const { data: isAdmin } = await userClient.rpc(
    "batata_is_amazon_importer_admin",
  );
  if (isAdmin !== true) {
    return json({ ok: false, error: "forbidden" }, 200);
  }

  return json({
    ok: false,
    disabled: true,
    candidates: [],
    message:
      "Pesquisa noutros sites desactivada. " +
      "Use só Amazon ES → IT → DE → FR ou introduza o preço manualmente. " +
      "Se não houver preço Amazon válido: «Preço não encontrado na Amazon».",
  });
});
