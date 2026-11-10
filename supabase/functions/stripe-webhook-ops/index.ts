/**
 * ONE-SHOT ops — list/disable Stripe TEST webhook endpoints.
 * Auth: Bearer == SUPABASE_SERVICE_ROLE_KEY only.
 * Never touches Live mode endpoints.
 */
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const STAGING_WEBHOOK_URL =
  "https://fxdknzrqjenzqcvnwqqq.supabase.co/functions/v1/stripe-webhook";
const PROD_WEBHOOK_URL =
  "https://bpmpkzwnrbmuqnhgdscf.supabase.co/functions/v1/stripe-webhook";

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

async function stripe(
  sk: string,
  method: string,
  path: string,
  form?: Record<string, string>,
) {
  const body = form
    ? new URLSearchParams(form).toString()
    : undefined;
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${sk}`,
      ...(form
        ? { "Content-Type": "application/x-www-form-urlencoded" }
        : {}),
    },
    body,
  });
  const text = await res.text();
  let parsed: unknown = text;
  try {
    parsed = JSON.parse(text);
  } catch {
    /* raw */
  }
  return { ok: res.ok, status: res.status, data: parsed };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  // One-shot ops token (preferred) OR service_role Bearer.
  const opsToken = (Deno.env.get("STRIPE_WEBHOOK_OPS_TOKEN") ?? "").trim();
  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const auth = (req.headers.get("Authorization") ?? "").trim();
  const bearerOk =
    (opsToken.length > 0 && auth === `Bearer ${opsToken}`) ||
    (serviceKey.length > 0 && auth === `Bearer ${serviceKey}`);
  if (!bearerOk) {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  const sk = (Deno.env.get("STRIPE_SECRET_KEY") ?? "").trim();
  if (!sk) return json({ ok: false, error: "stripe_secret_missing" }, 500);
  if (sk.startsWith("sk_live")) {
    return json({
      ok: false,
      error: "refused_live_key",
      hint: "Esta ops só corre com sk_test_.",
    }, 403);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const action = String(body.action ?? "list").trim();

  const listed = await stripe(sk, "GET", "/webhook_endpoints?limit=100");
  if (!listed.ok) {
    return json({
      ok: false,
      error: "list_failed",
      http_status: listed.status,
      data: listed.data,
    }, 502);
  }

  const raw = listed.data as { data?: Array<Record<string, unknown>> };
  const endpoints = (raw.data ?? []).map((e) => ({
    id: String(e.id ?? ""),
    url: String(e.url ?? ""),
    status: String(e.status ?? ""),
    livemode: e.livemode === true,
    api_version: e.api_version ?? null,
    enabled_events: e.enabled_events ?? null,
  }));

  const staging = endpoints.filter((e) => e.url === STAGING_WEBHOOK_URL);
  const prod = endpoints.filter((e) => e.url === PROD_WEBHOOK_URL);

  if (action === "list") {
    return json({
      ok: true,
      action: "list",
      stripe_mode: "test",
      key_prefix: sk.slice(0, 7),
      endpoints,
      staging_matches: staging,
      prod_matches: prod,
    });
  }

  if (action !== "disable_staging") {
    return json({ ok: false, error: "unknown_action" }, 400);
  }

  // Safety gates
  if (staging.length === 0) {
    return json({
      ok: false,
      error: "staging_endpoint_not_found",
      endpoints,
      prod_matches: prod,
    }, 404);
  }
  if (staging.some((e) => e.livemode)) {
    return json({ ok: false, error: "refused_livemode_staging" }, 403);
  }
  if (prod.length === 0) {
    return json({
      ok: false,
      error: "prod_endpoint_missing_abort",
      hint: "Não desactivo staging se o webhook Prod não estiver listado na mesma conta TEST.",
      staging_matches: staging,
    }, 409);
  }

  const disabled: unknown[] = [];
  for (const ep of staging) {
    if (ep.status === "disabled") {
      disabled.push({ id: ep.id, already: true, status: ep.status });
      continue;
    }
    const upd = await stripe(sk, "POST", `/webhook_endpoints/${ep.id}`, {
      disabled: "true",
    });
    disabled.push({
      id: ep.id,
      url: ep.url,
      http_status: upd.status,
      result: upd.data,
    });
    if (!upd.ok) {
      return json({
        ok: false,
        error: "disable_failed",
        disabled,
        prod_matches: prod,
      }, 502);
    }
  }

  // Re-list for proof
  const listed2 = await stripe(sk, "GET", "/webhook_endpoints?limit=100");
  const raw2 = listed2.data as { data?: Array<Record<string, unknown>> };
  const after = (raw2.data ?? []).map((e) => ({
    id: String(e.id ?? ""),
    url: String(e.url ?? ""),
    status: String(e.status ?? ""),
    livemode: e.livemode === true,
  }));

  return json({
    ok: true,
    action: "disable_staging",
    stripe_mode: "test",
    disabled,
    staging_after: after.filter((e) => e.url === STAGING_WEBHOOK_URL),
    prod_after: after.filter((e) => e.url === PROD_WEBHOOK_URL),
    note: "Staging TEST webhook disabled. Prod unchanged.",
  });
});
