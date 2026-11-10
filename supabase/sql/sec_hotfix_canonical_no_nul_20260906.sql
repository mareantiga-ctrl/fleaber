-- Hotfix: batata_storage_url_path_canonical sem chr(0)
-- Postgres 54000: "null character not permitted" mesmo em replace(v, chr(0), '')
-- Strip de NUL real impossível em text; %00 percent-encoding já é removido no loop.
-- production_touched:false · fase4:false · BATATA

create or replace function public.batata_storage_url_path_canonical(p_url text)
returns text
language plpgsql
immutable
as $$
declare
  v text := coalesce(p_url, '');
  i int;
  prev text;
begin
  v := split_part(split_part(v, '?', 1), '#', 1);
  -- Nunca usar chr(0): Postgres rejeita NUL mesmo como argumento de replace.
  v := replace(v, chr(9), '');
  v := replace(v, chr(10), '');
  v := replace(v, chr(13), '');
  v := regexp_replace(v,
    '[' || chr(8206) || chr(8207) || chr(8234) || chr(8235) || chr(8236)
      || chr(8237) || chr(8238) || chr(8294) || chr(8295) || chr(8296)
      || chr(8297) || chr(8203) || chr(8204) || chr(8205) || chr(173)
      || ']+',
    '', 'g');
  for i in 1..10 loop
    prev := v;
    v := replace(v, E'／', '/');
    v := replace(v, E'＼', '/');
    v := replace(v, E'∕', '/');
    v := replace(v, E'⁄', '/');
    v := replace(v, E'⧸', '/');
    v := replace(v, E'∖', '/');
    v := replace(v, E'．', '.');
    v := replace(v, E'․', '.');
    v := replace(v, E'‥', '..');
    v := replace(v, chr(92), '/');
    v := replace(v, E'％', '%');
    v := regexp_replace(v, '%c0%ae', '.', 'gi');
    v := regexp_replace(v, '%c0%af', '/', 'gi');
    v := regexp_replace(v, '%c1%9c', '/', 'gi');
    v := regexp_replace(v, '%e0%80%ae', '.', 'gi');
    v := regexp_replace(v, '%e0%80%af', '/', 'gi');
    v := regexp_replace(v, '%f0%80%80%ae', '.', 'gi');
    v := regexp_replace(v, '%f0%80%80%af', '/', 'gi');
    v := regexp_replace(v, '%e2%88%95', '/', 'gi');
    v := regexp_replace(v, '%e2%a7%b8', '/', 'gi');
    v := regexp_replace(v, '%e2%81%84', '/', 'gi');
    v := regexp_replace(v, '%ef%bc%8f', '/', 'gi');
    v := regexp_replace(v, '%ef%bc%bc', '/', 'gi');
    v := regexp_replace(v, '%u002e', '.', 'gi');
    v := regexp_replace(v, '%u002f', '/', 'gi');
    v := regexp_replace(v, '%u005c', '/', 'gi');
    v := regexp_replace(v, '%u2215', '/', 'gi');
    v := regexp_replace(v, '%u2216', '/', 'gi');
    v := regexp_replace(v, '%00', '', 'gi');
    v := regexp_replace(v, '%25252e', '%252e', 'gi');
    v := regexp_replace(v, '%25252f', '%252f', 'gi');
    v := regexp_replace(v, '%25255c', '%255c', 'gi');
    v := regexp_replace(v, '%252e', '.', 'gi');
    v := regexp_replace(v, '%252f', '/', 'gi');
    v := regexp_replace(v, '%255c', '/', 'gi');
    v := regexp_replace(v, '%25%2e', '.', 'gi');
    v := regexp_replace(v, '%25%2f', '/', 'gi');
    v := regexp_replace(v, '%2e', '.', 'gi');
    v := regexp_replace(v, '%2f', '/', 'gi');
    v := regexp_replace(v, '%5c', '/', 'gi');
    exit when v is not distinct from prev;
  end loop;
  return lower(v);
end;
$$;
