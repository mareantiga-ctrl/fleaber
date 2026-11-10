/**
 * Shared fail-closed gates for staging-only destructive harnesses.
 * Never trust client "I am admin" claims.
 */
export const FLEABER_STAGING_PROJECT_REF = "fxdknzrqjenzqcvnwqqq";
export const FLEABER_PROD_PROJECT_REF = "bpmpkzwnrbmuqnhgdscf";

export type DestructiveGateResult =
  | { ok: true }
  | { ok: false; status: number; error: string };

/**
 * Allows destructive test/nuke/e2e harnesses only when ALL hold:
 * - SUPABASE_URL contains staging ref and NOT prod ref
 * - STRIPE_SECRET_KEY is sk_test_ (unless skipStripe)
 * - FLEABER_ALLOW_DESTRUCTIVE_HARNESS === "true" (explicit opt-in)
 */
export function assertDestructiveHarnessAllowed(opts?: {
  skipStripe?: boolean;
}): DestructiveGateResult {
  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").toLowerCase();
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const allow = Deno.env.get("FLEABER_ALLOW_DESTRUCTIVE_HARNESS") === "true";

  if (supabaseUrl.includes(FLEABER_PROD_PROJECT_REF)) {
    return {
      ok: false,
      status: 403,
      error: "Harness destrutivo recusado: URL de produção.",
    };
  }
  if (!supabaseUrl.includes(FLEABER_STAGING_PROJECT_REF)) {
    return {
      ok: false,
      status: 403,
      error: "Harness destrutivo só em staging.",
    };
  }
  if (!opts?.skipStripe && !stripeKey.startsWith("sk_test_")) {
    return {
      ok: false,
      status: 403,
      error: "Harness destrutivo exige STRIPE_SECRET_KEY sk_test_.",
    };
  }
  if (!allow) {
    return {
      ok: false,
      status: 403,
      error:
        "Harness destrutivo desactivado. Define FLEABER_ALLOW_DESTRUCTIVE_HARNESS=true só em staging.",
    };
  }
  return { ok: true };
}
