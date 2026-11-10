const fs = require('fs');
const j = JSON.parse(fs.readFileSync('tool/_tmp_ingest_v2_out.json', 'utf8'));
let def = j.rows[0].def.replace(/\r\n/g, '\n');

const idx = def.indexOf("if v_intent = 'cancel'");
if (idx < 0) {
  console.error('cancel block not found');
  process.exit(1);
}

const before = def.slice(0, idx);
let after = def.slice(idx);

// Only touch cancel section until next major branch (v_final_conf / reserve path)
const endMarkers = [
  "\n  v_final_conf :=",
  "\n  -- Supersede",
  "\n  v_idem :=",
];
let end = after.length;
for (const m of endMarkers) {
  const i = after.indexOf(m);
  if (i > 0 && i < end) end = i;
}
const cancel = after.slice(0, end);
const rest = after.slice(end);

let patched = cancel
  .replace(/and r2\.status = 'pending'/g, "and r2.status in ('pending', 'accepted')")
  .replace(/and r3\.status = 'pending'/g, "and r3.status in ('pending', 'accepted')");

// Block cancel if already converted or paid order exists
if (!patched.includes('batata_order_status_is_sold_fulfilled')) {
  patched = patched.replace(
    "and r2.status in ('pending', 'accepted')\n          and (",
    `and r2.status in ('pending', 'accepted')
          and not exists (
            select 1 from public.orders o
            where (
              (r2.buyer_id is not null and o.buyer_id = r2.buyer_id)
              or (r2.buyer_id is null and false)
            )
              and o.live_item_id = r2.live_item_id
              and (
                public.batata_order_status_is_sold_fulfilled(o.status)
                or lower(trim(coalesce(o.status, ''))) in (
                  'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
                )
                or coalesce(o.stock_units_applied, 0) > 0
              )
          )
          and (`
  );
}

// After successful cancel: announce in live chat + clearer notes
patched = patched.replace(
  "notes = coalesce(r.notes || ' | ', '') || 'ps:auto_cancel',",
  "notes = coalesce(r.notes || ' | ', '') || case when r.status = 'accepted' then 'ps:auto_cancel_accepted' else 'ps:auto_cancel' end,"
);

// Insert chat announce before return cancelled
if (!patched.includes('batata_live_item_chat_label')) {
  patched = patched.replace(
    `perform public.batata_recompact_reservation_queue(v_row.live_item_id);

    return jsonb_build_object(
      'ok', true,
      'action', 'cancelled',`,
    `perform public.batata_recompact_reservation_queue(v_row.live_item_id);

    begin
      insert into public.live_messages (live_id, user_id, kind, body, sender_label, channel)
      values (
        v_row.live_id,
        coalesce(v_row.buyer_id, v_row.seller_id),
        'system',
        '↩ ' || coalesce(nullif(trim(v_row.external_display_name), ''), 'Comprador')
          || ' cancelou ' || public.batata_live_item_chat_label(v_row.live_item_id),
        'Sistema',
        case when v_row.source = 'facebook_manual' then 'facebook' else 'fleaber' end
      );
    exception when others then
      null;
    end;

    return jsonb_build_object(
      'ok', true,
      'action', 'cancelled',`
  );
}

def = before + patched + rest;
if (!/^create or replace function/i.test(def)) {
  def = def.replace(/^CREATE OR REPLACE FUNCTION/i, 'create or replace function');
}

const out = `-- BATATA: cancel Face/PS também em accepted (não pago)
${def}

notify pgrst, 'reload schema';
`;
fs.writeFileSync('supabase/sql/ps_cancel_accepted_batata.sql', out);
console.log('wrote', out.length, 'bytes');
console.log('pending_left', (out.match(/r2\.status = 'pending'/g) || []).length);
console.log('accepted_in', (out.match(/pending', 'accepted'/g) || []).length);
