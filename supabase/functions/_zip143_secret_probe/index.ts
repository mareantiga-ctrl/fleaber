Deno.serve(async (req) => {
  const auth = req.headers.get("authorization") || "";
  const sr = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!sr || !auth.includes(sr)) {
    return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), { status: 401 });
  }
  const stripe = Deno.env.get("STRIPE_SECRET_KEY") || "";
  const dpdMode = Deno.env.get("DPD_MODE") || "";
  const dpdQa = Deno.env.get("DPD_QA_CREATE_ENABLED") || "";
  const dpdTrack = Deno.env.get("DPD_TRACKING_SYNC_ENABLED") || "";
  const mbway = Deno.env.get("STRIPE_DELTA_ALLOW_MBWAY");
  const prefix = stripe.slice(0, 7);
  let livemode: boolean | null = null;
  let stripeErr: string | null = null;
  if (stripe.startsWith("sk_")) {
    try {
      const r = await fetch("https://api.stripe.com/v1/balance", {
        headers: { Authorization: `Bearer ${stripe}` },
      });
      const j = await r.json();
      if (typeof j.livemode === "boolean") livemode = j.livemode;
      else stripeErr = JSON.stringify(j).slice(0, 200);
    } catch (e) {
      stripeErr = String(e);
    }
  }
  return new Response(JSON.stringify({
    ok: true,
    stripe_prefix: prefix,
    stripe_livemode: livemode,
    stripe_err: stripeErr,
    dpd_mode: dpdMode,
    dpd_qa_create: dpdQa,
    dpd_tracking_sync: dpdTrack,
    stripe_delta_allow_mbway: mbway === null || mbway === undefined ? null : mbway,
  }), { headers: { "Content-Type": "application/json" } });
});
