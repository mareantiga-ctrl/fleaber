/**
 * Sync DPD Trace → estados encomenda.
 * Gated: só corre se DPD_TRACKING_SYNC_ENABLED=1.
 * Não activar cron sem GO.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  dpdTrackingSyncEnabled,
  fetchDpdTrace,
} from "../_shared/dpd_client.ts";

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

function classifyEvent(desc: string): "accept" | "transit" | "pickup" | "delivered" | null {
  const d = desc.toLowerCase();
  if (
    d.includes("entregue") ||
    d.includes("delivered") ||
    d.includes("entrega efectuada")
  ) {
    return "delivered";
  }
  if (
    d.includes("dispon") ||
    d.includes("levantamento") ||
    d.includes("pickup") ||
    d.includes("ponto")
  ) {
    return "pickup";
  }
  if (
    d.includes("aceit") ||
    d.includes("recolh") ||
    d.includes("recepcion") ||
    d.includes("received") ||
    d.includes("hub")
  ) {
    return "accept";
  }
  if (d.includes("trânsito") || d.includes("transit") || d.includes("curso")) {
    return "transit";
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (!dpdTrackingSyncEnabled()) {
    return json({
      ok: false,
      error: "tracking_sync_disabled",
      hint: "DPD_TRACKING_SYNC_ENABLED≠1 — sem cron/auto até GO.",
    }, 403);
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const { data: rows } = await admin
    .from("orders")
    .select("id,status,dpd_tracking_code,dpd_accept_at,dpd_delivered_at")
    .not("dpd_tracking_code", "is", null)
    .not("status", "in", "(cancelado,cancelled,devolvida)")
    .limit(40);

  const updates: unknown[] = [];
  for (const order of rows ?? []) {
    const guide = String(order.dpd_tracking_code ?? "").trim();
    if (!guide) continue;
    const trace = await fetchDpdTrace({ guide });
    if (!trace.ok || trace.events.length === 0) continue;

    let best: ReturnType<typeof classifyEvent> = null;
    for (const ev of trace.events) {
      const c = classifyEvent(ev.description);
      if (c === "delivered") best = "delivered";
      else if (c === "pickup" && best !== "delivered") best = "pickup";
      else if (c === "accept" && best == null) best = "accept";
      else if (c === "transit" && (best == null || best === "accept")) {
        best = "transit";
      }
    }

    const patch: Record<string, unknown> = {};
    const status = String(order.status ?? "").toLowerCase();
    if (best === "accept" || best === "transit" || best === "pickup") {
      if (!order.dpd_accept_at) {
        patch.dpd_accept_at = new Date().toISOString();
      }
      if (status === "pago") {
        // Aceitação física DPD → Enviado
        patch.status = "enviado";
      }
    }
    if (best === "delivered") {
      patch.dpd_delivered_at = new Date().toISOString();
      if (!order.dpd_accept_at) {
        patch.dpd_accept_at = new Date().toISOString();
      }
      if (status !== "entregue" && status !== "concluido") {
        patch.status = "entregue";
      }
    }
    if (Object.keys(patch).length > 0) {
      await admin.from("orders").update(patch).eq("id", order.id);
      updates.push({ id: order.id, patch, best });
    }
  }

  return json({ ok: true, scanned: (rows ?? []).length, updates });
});
