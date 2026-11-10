# Fleaber — Ingest cross-canal (Facebook) + fila unificada

> **PS = Projecto Spy** — motor de ingestão cross-canal. **Projecto H** = superfície FleaHub pública + funil (`docs/project-h-fleahub-v1.md`). Fluxo alvo: redes → PS → FleaHub → Fleaber.

**Documento interno de execução** — consolida discussões Cursor (Jun 2026).  
**Âmbito:** unificar reservas Facebook (OCR local) com Fleaber/App/Hub na **mesma fila numerada**, sem APIs Meta de comentários/live (contingência até App Review futura).

**Não é copy pública.** Não substitui `docs/live-hub-master-plan.md` (arquitectura Hub/identidade); complementa-o no ramo «FB sem API de comentários».

---

## 1. Resumo executivo

| Objectivo | Estado |
|-----------|--------|
| Fila única `#1 #2 #3` para App + Facebook (+ futuro TikTok) | **A implementar** — hoje FB está fora de `queue_position` |
| Leitura automática comentários FB sem Graph API | **Contingência OCR** — agente local no PC da seller |
| Login Facebook / reconciliação `buyer_id` | **Fora deste documento** — não bloqueia fila unificada |
| Scraping DOM Facebook | **Rejeitado** — frágil + ToS; OCR em região fixa preferido |
| Graph API comentários | **Adiado** — quando App Review passar, mesma fila + `effective_at` exacto |
| Regra de desempate em empates | **`fleaber_first` sempre** — ver §7 (confidencial) |

---

## 2. O que discutimos e decidimos

### 2.1 Decidido (executar)

1. **Fila unificada** por `live_item_id`: todas as origens (`fleaber_live`, `facebook_manual`, `helper_manual`, futuro `ocr_facebook`) recebem `queue_position` global.
2. **Sem segundo exacto do Facebook** — ordenar por `effective_at` estimado, não pelo relógio FB.
3. **Agente local OCR** (Python standalone, não extensão Chrome) no PC da seller: captura ROI do chat, Tesseract, parser PT.
4. **Pseudo-identidade por live** — `avatar_phash + name_norm` → `external_buyer_ref = sess:{live_id}:{pseudo_id}` (distinuir comentadores na mesma live, não identificar conta Fleaber).
5. **Metadados ricos** em cada reserva FB: `external_display_name`, `detected_at`, `chat_sequence`, `ocr_raw_line`, `ingest_confidence`, `avatar_phash`.
6. **Idempotência** — `idempotency_key = ocr:{sha256(line)}` + dedupe local no agente.
7. **Confirmação seller** quando `ingest_confidence < 0.85` → `ingest_status = needs_review` (card 1 toque no studio).
8. **FleaHub** continua canal principal de conversão (link no live FB); OCR é para quem comenta no FB na mesma.
9. **Mesmo endpoint de ingest** desenhado para migrar depois de OCR → Graph API (só muda a fonte dos campos).

### 2.2 Decidido (não fazer agora)

| Item | Porquê |
|------|--------|
| App Review Meta só com vídeos família | Insuficiente sem OAuth página + código ingest; adiar pós-piloto |
| Scraping DOM / extensão Chrome | Pior manutenção que OCR; MV3 limita captura cross-window |
| Reconhecimento facial nos avatares FB | Avatares 24–40 px — inútil |
| Prometer 100% leitura OCR automática | Tecto ~85–90%; 100% operacional = confiança alta + confirmação seller |
| Login Facebook Hub para reconciliar reservas | Fora do âmbito deste sprint; reclamação manual depois |
| Anunciar regra de prioridade ao público | Ver §7 — segredo comercial |

### 2.3 Em aberto (resolver na implementação)

- Buffer OCR exacto: **3 s** default (`effective_at = detected_at - 3s`), tunable por seller em `profiles.ocr_latency_buffer_ms`.
- Janela de ambiguidade: **10 s** default entre `effective_at` de dois pedidos no mesmo `live_item_id`.
- Auto-aceite OCR com confiança ≥ 0.85: sim ou sempre `needs_review` no piloto? → **sugerido:** piloto com `needs_review` até métricas; depois auto.
- Novo valor `source`: manter `facebook_manual` ou criar `ocr_facebook`? → **sugerido:** `facebook_manual` + coluna `ingest_channel = ocr|manual|graph` para auditoria.

---

## 3. Estado actual do código (baseline)

### 3.1 Já existe

| Peça | Local |
|------|-------|
| `facebook_manual` / `helper_manual` no CHECK | `supabase/sql/live_reservation_requests_batata.sql` |
| Reserva manual FB no studio | `lib/widgets/live_vendor_studio_panel.dart` |
| `LiveReservationSource.facebookManual` | `lib/utils/live_reservation_queue_service.dart` |
| Trigger `queue_position` **só** `fleaber_live` | `supabase/sql/live_ops_hotfix_batata.sql` → `batata_live_reservation_assign_queue` |
| Stock cross-source | `batata_live_item_stock` (FB manual conta no stock) |
| FOMO «X na fila» | Só `fleaber_live` (`hub_public_views_batata.sql`) |
| Hub reservas pós-login | `lib/hub/widgets/hub_reservations_section.dart` (só esta live, `buyer_id`) |
| Inventário multi-canal | `docs/live-hub-master-plan.md` §2.24 |

### 3.2 Falta (este projecto)

- Colunas novas na tabela + índices
- Trigger unificado + RPC recompactação cross-source
- Edge Function `ingest-ocr-reservation` + device tokens
- Agente Python `tool/fleaber_reader/` (ou repo separado)
- UI studio: card FB com avatar crop, hora estimada, canal, empate resolvido
- Alterar FOMO/stock se necessário para contar fila unificada
- Testes integração fila mista (Maestro + `tool/regression`)

---

## 4. Modelo de ordenação (fila unificada)

### 4.1 Campos temporais

| Campo | Origem | Cálculo |
|-------|--------|---------|
| `created_at` | Servidor | INSERT default |
| `detected_at` | Agente OCR | Quando a linha foi vista no ecrã |
| `effective_at` | Calculado | Ver tabela abaixo |

| `source` / canal | `effective_at` |
|------------------|----------------|
| `fleaber_live` | `created_at` |
| `facebook_manual` + `ingest_channel=ocr` | `detected_at - buffer` (default 3 s) |
| `facebook_manual` + `ingest_channel=manual` | `created_at` (seller carregou no momento) |
| `helper_manual` | `created_at` |
| Futuro Graph API | `comment_created_at` da Meta (exacto) |

### 4.2 Atribuição `queue_position`

Na INSERT ou via RPC `batata_assign_queue_position(p_request_id)`:

```sql
-- Ordenação global por artigo (pending):
ORDER BY effective_at ASC,
         source_priority ASC,  -- ver §7 (interno)
         created_at ASC,
         id ASC
-- Depois renumerar 1..N com batata_recompact_reservation_queue (todos os sources)
```

**Trigger actual a alterar:** remover filtro `and r.source = 'fleaber_live'` no `max(queue_position)` e na recompactação.

### 4.3 Chegada atrasada (FB detectado depois do Fleaber)

Se OCR regista comentário com `effective_at` anterior a reservas já numeradas:

1. INSERT com `effective_at` correcto
2. Chamar `batata_recompact_reservation_queue(p_live_id, p_live_item_id)` — **todos** os `pending`
3. Realtime atualiza studio + comprador

Isto corrige ordem sem precisar do segundo FB — só da estimativa.

---

## 5. Agente local OCR (Fleaber Reader)

### 5.1 Stack

- **Runtime:** Python 3.11+, asyncio
- **Capture:** `mss` (região ROI calibrada)
- **Vision:** OpenCV preprocess + `pytesseract` (`por+eng`, PSM 6)
- **Gate:** `imagehash.phash` — skip frame se igual
- **Envio:** `httpx` → Edge Function
- **Empacotamento:** PyInstaller `.exe` Windows (seller)

### 5.2 Pipeline por linha de chat

```
ROI → detecção linhas (~48px) → por linha:
  crop_avatar (40×40) → phash
  crop_name           → OCR nome
  crop_text           → OCR "quero o N"
→ parser PT → confidence → POST
```

### 5.3 Pseudo-ID (mesma live)

```
pseudo_id = sha256(avatar_phash + normalize(name))[:16]
external_buyer_ref = "sess:{live_id}:{pseudo_id}"
```

### 5.4 Performance alvo (i5, 16 GB)

- Poll 2.5 fps; CPU ~15–25% com OCR activo
- Só OCR quando frame hash muda

### 5.5 Config vendedora (`%APPDATA%/FleaberReader/config.json`)

```json
{
  "roi": { "left": 0, "top": 0, "width": 400, "height": 500 },
  "live_id": "uuid",
  "device_token": "…",
  "supabase_url": "https://….supabase.co"
}
```

---

## 6. Backend Supabase

### 6.1 DDL (novo ficheiro SQL)

Ficheiro proposto: `supabase/sql/live_cross_channel_ingest_batata.sql`

```sql
-- Colunas novas em live_reservation_requests
alter table public.live_reservation_requests
  add column if not exists effective_at timestamptz,
  add column if not exists detected_at timestamptz,
  add column if not exists external_display_name text,
  add column if not exists external_buyer_ref text,
  add column if not exists chat_sequence int,
  add column if not exists avatar_phash text,
  add column if not exists ocr_raw_line text,
  add column if not exists ingest_channel text
    check (ingest_channel is null or ingest_channel in ('ocr', 'manual', 'graph', 'helper')),
  add column if not exists ingest_confidence numeric(4,3),
  add column if not exists ingest_status text
    check (ingest_status is null or ingest_status in ('auto', 'needs_review', 'seller_confirmed', 'rejected')),
  add column if not exists idempotency_key text;

create unique index if not exists live_reservation_requests_idempotency_uidx
  on public.live_reservation_requests (idempotency_key)
  where idempotency_key is not null;

-- Device tokens (agente local — não service_role no PC)
create table if not exists public.seller_device_tokens (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete cascade,
  device_id text not null,
  token_hash text not null,
  label text,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (seller_id, device_id)
);

-- Buffer OCR por seller (opcional override)
alter table public.profiles
  add column if not exists ocr_latency_buffer_ms int not null default 3000;
```

**Nota:** `idempotency_key` está em `live-hub-master-plan.md` §2.6 mas **ainda não** no SQL versionado — incluir neste script.

### 6.2 RPC / Edge Function

| Artefacto | Função |
|-----------|--------|
| `ingest-ocr-reservation` (Edge) | Valida `device_token`, resolve `ref_number` → `live_item_id`, INSERT, recompact |
| `batata_ingest_ocr_reservation` (RPC) | Lógica SQL; `SECURITY DEFINER` |
| `batata_recompact_reservation_queue` | **Alterar:** incluir todos os `source`, ordenar por `effective_at` |
| `batata_live_reservation_assign_queue` | **Alterar:** trigger BEFORE INSERT calcula `effective_at` + posição |

**Payload ingest OCR:**

```json
{
  "live_id": "uuid",
  "ref_number": 3,
  "external_display_name": "Maria Silva",
  "external_buyer_ref": "sess:live_uuid:abc123",
  "ocr_raw_line": "Maria Silva quero o 3",
  "ocr_line_hash": "a1b2c3…",
  "detected_at": "2026-06-20T14:32:04Z",
  "chat_sequence": 847,
  "avatar_phash": "ff12…",
  "ingest_confidence": 0.82
}
```

### 6.3 Resolver `ref_number` → `live_item_id`

Server-side na RPC:

1. Artigo **activo** (`live_items.is_active` ou `status = showing`) com `ref_code` = N
2. Senão, match por ordem no catálogo da live (documentar regra)
3. Falha → `needs_review` sem `live_item_id` ou rejeitar com log

---

## 7. Regra de desempate — CONFIDENCIAL

> **Não expor na UI pública, copy Hub, anúncios live, nem documentação seller.**  
> Implementação só server-side. Logs internos discretos (`dedupe_reason = tiebreak_fleaber`).

### 7.1 Regra

Quando dois pedidos `pending` no **mesmo** `live_item_id` têm:

```
abs(effective_at_a - effective_at_b) <= ambiguity_window_ms  -- default 10_000
```

→ **`fleaber_live` fica sempre à frente** de `facebook_manual` / `helper_manual` / OCR.

Se ambos forem `fleaber_live` → `created_at` ASC (comportamento actual).

Se ambos forem FB/OCR → `effective_at` ASC; empate → `chat_sequence` ASC.

### 7.2 `source_priority` (interno, não documentar fora)

| source | priority (menor = primeiro em empate) |
|--------|--------------------------------------|
| `fleaber_live` | 0 |
| `helper_manual` | 1 |
| `facebook_manual` | 2 |

### 7.3 UI

- **Não** mostrar «empate», «prioridade app», nem ícone especial ao comprador.
- Studio seller: pode mostrar hora estimada `~14:32` para FB; **sem** explicar desempate.
- Se `needs_review`: card neutro «Confirmar reserva Facebook» — sem mencionar prioridade.

---

## 8. Parser português (OCR)

```regex
-- Prioridade decrescente
1) ^(?P<name>.+?)\s+(?:quero|queria|reservo|fico com)\s+(?:o\s+)?(?P<num>\d{1,3})\b
2) ^(?:quero|reservo)\s+(?:o\s+)?(?P<num>\d{1,3})\b
3) ^(?P<name>[A-Za-zÀ-ú][\w\s]{2,30})\s+(?P<num>\d{1,3})$
```

- Só dígitos 1–999 no grupo `num`
- Linha só com número → `needs_review` (sem nome)
- `ingest_confidence` combina: clareza dígitos + OCR nome + match regex + avatar estável

---

## 9. UI Studio (alterações mínimas)

| Elemento | Comportamento |
|----------|---------------|
| Fila unificada | Um só `#1 #2 #3` com badge canal: App · Facebook · Equipa |
| Card FB OCR | Nome, `~HH:MM:SS` (effective_at), crop avatar, texto OCR, [Aceitar] [Corrigir #] [Ignorar] |
| `needs_review` | Destaque âmbar; não bloqueia outras acções |
| Reserva manual existente | Mantém-se; `ingest_channel=manual` |

**BATATA:** não alterar layout player live / carrossel — só studio vendedora.

---

## 10. FOMO, stock, saco comprador

| Superfície | Alteração necessária |
|------------|---------------------|
| `batata_live_item_stock` | Verificar se `pending` FB deve contar em `pending_bag_qty` — hoje só `fleaber_live` |
| FOMO «X na fila» | Decidir: contar fila unificada ou só App — **sugerido:** total unificado |
| Saco comprador App | Continua `fleaber_live` only (comprador não vê fila FB alheia) |
| `batata_live_bag_*` RPCs | Manter restrição `fleaber_live` — FB não entra no saco |

---

## 11. Fases de implementação

### Fase 0 — SQL fila unificada (1–2 dias)

- [ ] `live_cross_channel_ingest_batata.sql` em staging
- [ ] Alterar trigger `batata_live_reservation_assign_queue`
- [ ] Alterar `batata_recompact_reservation_queue` (todos sources)
- [ ] Testes RPC: 3 inserts mistos → posições 1,2,3 correctas
- [ ] Teste empate <10 s: Fleaber antes de FB **sem UI a mencionar**

### Fase 1 — Edge ingest (2–3 dias)

- [ ] `seller_device_tokens` + emit token no perfil seller (ecrã simples)
- [ ] Edge `ingest-ocr-reservation`
- [ ] RPC `batata_ingest_ocr_reservation` com idempotency

### Fase 2 — Agente Python (3–5 dias)

- [ ] `tool/fleaber_reader/` — script + calibração ROI
- [ ] Wizard primeira execução
- [ ] PyInstaller build Windows
- [ ] Teste com live staging + comentários simulados

### Fase 3 — Studio UI (2–3 dias)

- [ ] Card `needs_review` + fila unificada visual
- [ ] Corrigir número / ignorar
- [ ] Logs `live_vendor_studio_logs` com `ingest_channel`

### Fase 4 — Piloto (1–2 semanas)

- [ ] 2–3 sellers dual-screen
- [ ] Métricas: precisão OCR, % needs_review, disputas de ordem
- [ ] Afinar `ocr_latency_buffer_ms` e `ambiguity_window_ms`

### Fase 5 — Migração Graph API (quando existir)

- [ ] Mesmo RPC; `ingest_channel=graph`; `effective_at` exacto Meta
- [ ] Desactivar agente OCR por seller via flag
- [ ] `external_buyer_ref = fb:{comment.from.id}`

---

## 12. Testes de aceitação

| ID | Cenário | Esperado |
|----|---------|----------|
| X01 | App #1, FB OCR #2 (effective_at 5 s antes) | FB fica #1 após recompact |
| X02 | FB OCR effective 14:32:00, App 14:32:05 | FB #1, App #2 |
| X03 | FB e App dentro 10 s (empate) | **App #1, FB #2** (silencioso) |
| X04 | Mesmo comentário OCR 2× | 409 idempotency, uma linha |
| X05 | OCR confidence 0.7 | `needs_review`, sem queue até seller confirma? **ou** entra com review flag — decidir piloto |
| X06 | `facebook_manual` seller manual | `effective_at = created_at`, entra na fila |
| X07 | Stock 1, FB #1 App #2 | Aceite FB consome stock; App em espera |

Script sugerido: `tool/live_cross_channel_queue_check.dart`

---

## 13. Riscos

| Risco | Mitigação |
|-------|-----------|
| OCR erra número | `needs_review` + Corrigir no studio |
| Ordem injusta FB vs App | Buffer + recompact; empate interno §7 |
| Seller não corre agente | Fallback reserva manual (já existe) |
| Duas Marias | `pseudo_id` avatar+name |
| Litígio «fui primeiro» | Mesmo problema que hoje no FB manual; regra interna não exposta |
| Trigger só fleaber_live em prod | Deploy SQL obrigatório antes do agente |

---

## 14. O que NÃO está neste projecto

- Login Facebook OAuth Hub
- `external_identities` / reconciliação automática `buyer_id`
- Página global `/minhas-reservas` Hub
- Graph API / App Review Meta
- TikTok / Instagram ingest
- Post automático comentário no FB quando reserva App
- Alterações layout `FleaberLivePlayerWidget` / carrossel

---

## 15. Referências no repo

| Ficheiro | Relação |
|----------|---------|
| `docs/live-hub-master-plan.md` §2.4, §2.6, §2.24 | Arquitectura identidade + inventário sources |
| `supabase/sql/live_ops_hotfix_batata.sql` | Trigger queue actual (alterar) |
| `supabase/sql/live_reservation_requests_batata.sql` | Tabela base |
| `lib/utils/live_reservation_queue_service.dart` | Serviço App |
| `lib/widgets/live_vendor_studio_panel.dart` | UI manual FB |
| `Historico/FLEABER_DOCUMENTO.md` §1.3 | Dual-screen fundador |
| `.cursor/rules/live-ops-batata.mdc` | Regras BATATA studio |

---

## 16. Checklist antes de começar implementação

- [ ] Aplicar SQL staging `live_cross_channel_ingest_batata.sql`
- [ ] Confirmar com utilizador: auto-aceite OCR alto confidence vs sempre review no piloto
- [ ] Definir match `ref_number` quando não há artigo activo com essa ref
- [ ] APK seller com studio actualizado após Fase 3
- [ ] Política interna: §7 nunca em copy pública (revisão PR)

---

*Última actualização: 2026-06-20 — sessão Cursor cross-canal FB/OCR/fila unificada.*
