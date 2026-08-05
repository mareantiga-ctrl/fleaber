import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

/** Rate limit via RPC `batata_anon_rate_check` (service_role). Se RPC falhar, devolve ok (fail-open). */
export async function checkAnonRate(
  supabase: SupabaseClient,
  rateKey: string,
  rpcName: string,
  maxHits: number,
): Promise<{ ok: boolean; rateLimited: boolean }> {
  try {
    const { data, error } = await supabase.rpc("batata_anon_rate_check", {
      p_rate_key: rateKey,
      p_rpc: rpcName,
      p_max_hits: maxHits,
    });
    if (error) {
      console.warn("batata_anon_rate_check error (fail-open)", error.message);
      return { ok: true, rateLimited: false };
    }
    const row = (data ?? {}) as Record<string, unknown>;
    if (row.ok === false && row.error === "rate_limited") {
      return { ok: false, rateLimited: true };
    }
    return { ok: true, rateLimited: false };
  } catch (e) {
    console.warn("batata_anon_rate_check exception (fail-open)", e);
    return { ok: true, rateLimited: false };
  }
}
