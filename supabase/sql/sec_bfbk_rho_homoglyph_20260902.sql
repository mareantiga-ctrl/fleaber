-- BFBK gap-fill: Greek lookalikes no normalize do chat (BG-P1 Ρix)
-- production_touched: false · fase4: false · BATATA mínimo

create or replace function public.batata_chat_normalize_lie_text(p_text text)
returns text
language sql
immutable
as $$
  select lower(
    translate(
      public.batata_chat_strip_format_controls(coalesce(p_text, '')),
      -- cirílico + grego lookalike + NBSP
      E'еЕаАоОрРсСхХуУіІΑαΡρΟοΕεΙιΚκΤτΥυΧχ' || chr(160),
      E'eeaaooppssxxyyiiAaPpOoEeIiKkTtYyXx '
    )
  );
$$;

notify pgrst, 'reload schema';
