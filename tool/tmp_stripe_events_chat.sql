-- Quem escreveu as msgs recentes no chat 495ea658? + eventos stripe
select event, created_at, detail->>'step' as step, detail->>'order_id' as order_id,
  detail->>'chat_id' as chat_id, detail->>'nav_chat_id' as nav_chat_id,
  left(detail::text, 200) as detail_preview
from stripe_checkout_events
where created_at > now() - interval '3 hours'
order by created_at desc
limit 40;
