select cm.id, cm.chat_id, cm.created_at, cm.is_reservation, left(cm.text, 200) as preview
from public.chat_messages cm
where cm.created_at > '2026-08-09 09:20:00+00'
  and (
    cm.text ilike '%seguro_fleaber_paid%'
    or cm.text ilike '%Compra paga%'
    or cm.text ilike '%66aa5f1f%'
    or cm.text ilike '%ab49477b%'
    or cm.text ilike '%92b6dc7f%'
  )
order by cm.created_at;
