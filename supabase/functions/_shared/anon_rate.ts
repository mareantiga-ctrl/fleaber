import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

/** Rate limit via RPC `batata_anon_rate_check` (service_role). Fail-closed se RPC falhar. */
export async function checkAnonRate(
  supabase: SupabaseClient,
  rateKey: string,
  rpcName: string,
  maxHits: number,
): Promise<{ ok: boolean; rateLimited: boolean; rpcFailed?: boolean }> {
  try {
    const { data, error } = await supabase.rpc("batata_anon_rate_check", {
      p_rate_key: rateKey,
      p_rpc: rpcName,
      p_max_hits: maxHits,
    });
    if (error) {
      console.error("batata_anon_rate_check error (fail-closed)", error.message);
      return { ok: false, rateLimited: true, rpcFailed: true };
    }
    const row = (data ?? {}) as Record<string, unknown>;
    if (row.ok === false && row.error === "rate_limited") {
      return { ok: false, rateLimited: true };
    }
    // Malformado / {} / ok≠true → fail-closed (não bypass)
    if (row.ok === true) {
      return { ok: true, rateLimited: false };
    }
    console.error(
      "batata_anon_rate_check malformed (fail-closed)",
      JSON.stringify(row),
    );
    return { ok: false, rateLimited: true, rpcFailed: true };
  } catch (e) {
    console.error("batata_anon_rate_check exception (fail-closed)", e);
    return { ok: false, rateLimited: true, rpcFailed: true };
  }
}
