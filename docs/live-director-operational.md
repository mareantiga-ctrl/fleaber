# Live Director Platform — Operação

## Pré-requisitos SQL (staging)

1. `supabase/sql/admin_batata.sql` (já aplicado)
2. `supabase/sql/live_director_batata.sql`
3. `supabase/sql/live_director_raffle_sim_batata.sql`

Ou migration: `supabase/migrations/20260705160000_live_director_platform.sql`

## Admin

URL: `/admin/live-director` (perfil admin)

Secções: Scripts · Editor · Pre-flight · Console · Runs · Timeline · Replay · Templates · Relatórios

## Criar script

1. Scripts → **Novo**
2. Editor: nome, live ID, modo (QA/Demo/Produção controlada)
3. **+ Beat** para adicionar linhas (ou editar JSON após guardar)
4. Definir produtos alvo e elenco (via BD `live_director_sim_profiles` ou cast no script)
5. **Guardar**

## Preview

Editor → lista temporal (sem BD) + heat map

## Dry Run

Editor → **Dry Run** — valida executáveis/bloqueados sem escrever

## Iniciar run

1. Pre-flight → **Validar**
2. Marcar confirmações
3. **Bloquear Manifest e criar Run**
4. Console → seleccionar run → **Iniciar Director**

## Console

Durante live: executar agora, adiar, pausar, kill, terminar

## Replay

Replay debug → carrega `live_director_timeline_events` (só leitura)

**Regra:** gravado não executa Director; só lê timeline.

## CLI staging

```bash
dart run tool/fleaber_live_director.dart --run-id <uuid>
```

## Checklist manual

- [ ] SQL aplicado em staging
- [ ] Admin acede `/admin/live-director`
- [ ] Script com live ID válida
- [ ] Pre-flight PASS
- [ ] Director inicia sem erro
- [ ] Kill switch responde
- [ ] Timeline tem eventos após beats
- [ ] Rifa draw exclui sim (`batata_count_real_raffle_participants`)
- [ ] Live normal sem `director_run_id` inalterada

## Guards

- RLS admin-only em tabelas `live_director_*`
- Bots: `profiles.sim_account_kind`
- Compras fora do script: bloqueadas no engine
- Pagamento real: bloqueado em Demo no validator
- Director só `status=running` durante directo
- `timeline_sealed` no fim da run
