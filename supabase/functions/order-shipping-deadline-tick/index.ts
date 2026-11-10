/**
 * ZIP 140 — tick de expiração (delta 48h + prazo envio).
 * NÃO agendar cron até GO `order_ship_deadline_autocancel_enabled`.
 * Só service_role.
 *
 * Fluxo:
 *  1) RPC marca adjustments expired + lista order_ids
 *  2) Se flag autocancel ON → invoca refund-order por cada id (idempotente)
 *  3) Emite kinds C2 (`shipping_delta_expired_cancelled` / `ship_deadline_auto_cancelled`)
 *     via batata_emit — templates email ficam com C2 (wantsCommercialEmail não alargado).
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const url = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const auth = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!service || auth !== service) {
    return new Response(JSON.stringify({ ok: false, error: "forbidden" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  const admin = createClient(url, service, { auth: { persistSession: false } });
  const { data, error } = await admin.rpc(
    "batata_expire_shipping_deltas_and_deadlines",
    { p_now: new Date().toISOString(), p_limit: 40 },
  );
  if (error) {
    return new Response(JSON.stringify({ ok: false, error: error.message }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const result = (data ?? {}) as {
    skipped?: boolean;
    order_ids_need_refund_cancel?: string[];
    delta_expired?: number;
    ship_overdue?: number;
  };

  const refunded: string[] = [];
  const refundErrors: Array<{ order_id: string; error: string }> = [];
  const ids = Array.isArray(result.order_ids_need_refund_cancel)
    ? result.order_ids_need_refund_cancel
    : [];

  // Só com GO: sem flag a RPC já devolve skipped; se houver ids, refund-order.
  if (!result.skipped && ids.length > 0) {
    for (const orderId of ids) {
      try {
        const res = await fetch(`${url}/functions/v1/refund-order`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${service}`,
            apikey: service,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            order_id: orderId,
            reason: "shipping_deadline_or_delta_expired",
            source: "order-shipping-deadline-tick",
          }),
        });
        const t = await res.text();
        let body: { ok?: boolean; skipped?: boolean; reason?: string } = {};
        try {
          body = JSON.parse(t) as typeof body;
        } catch { /* raw */ }
        if (!res.ok) {
          refundErrors.push({ order_id: orderId, error: t.slice(0, 300) });
        } else if (body.skipped) {
          refundErrors.push({
            order_id: orderId,
            error: `refund_skipped:${body.reason ?? "unknown"}`,
          });
        } else {
          refunded.push(orderId);
        }
      } catch (e) {
        refundErrors.push({
          order_id: orderId,
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }
  }

  return new Response(
    JSON.stringify({
      ok: true,
      result,
      refunded,
      refund_errors: refundErrors,
      cron_scheduled: false,
      note:
        "Cron NÃO agendado nesta entrega. GO: order_ship_deadline_autocancel_enabled.",
    }),
    {
      headers: { ...cors, "Content-Type": "application/json" },
    },
  );
});
