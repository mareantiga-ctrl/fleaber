/**
 * DPD client helpers (ZIP DPD integração) — BATATA.
 * Credenciais só via Deno.env / proxy Bearer — nunca no cliente.
 * Create de expedição: gated (dry_run por defeito).
 */

export const DPD_QA_BASE = "https://qabusiness.dpd.pt";
export const DPD_MYPUDO_ASMX =
  "https://mypudo.pickup-services.com/mypudo/mypudo.asmx";

/** Subcontas portal Fleaber (QA/contrato) — confirmadas ZIP 124.1 */
export const DPD_SUBACCOUNT_SHOP_TO_SHOP = "03546101";
export const DPD_SUBACCOUNT_SHOP_TO_HOME = "03546102";

export type DpdServiceKind = "shop_to_shop" | "shop_to_home";

export type DpdParty = {
  name: string;
  address1: string;
  address2?: string;
  zipCode: string;
  city: string;
  country: string; // ISO2 preferido nos profiles; Business pode mapear
  phone?: string;
  email?: string;
};

export type DpdPudoPoint = {
  pudoId: string;
  name: string;
  address1: string;
  zipCode: string;
  city: string;
  latitude?: string;
  longitude?: string;
};

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

/** true só se explicitamente ligado — nunca default em PROD */
export function dpdCreateEnabled(): boolean {
  return env("DPD_QA_CREATE_ENABLED") === "1";
}

/** Tarifas novas ao comprador (Célia) — off até GO comercial */
export function dpdShippingRatesLive(): boolean {
  return env("DPD_SHIPPING_RATES_LIVE") === "1";
}

/** Shop→Home com sobretaxa combustível — off até validação financeira */
export function dpdHomeChargesEnabled(): boolean {
  return env("DPD_HOME_CHARGES_ENABLED") === "1";
}

/** Sync automático tracking→estados — off até GO */
export function dpdTrackingSyncEnabled(): boolean {
  return env("DPD_TRACKING_SYNC_ENABLED") === "1";
}

/**
 * LEGADO — não usar para escolher QA/COMERCIAL de encomendas.
 * ZIP 172: usar ops_dpd_mode + resolveDpdOauthForMode / dpdApiBaseForMode.
 * DPD_MODE global NÃO selecciona comercial nas Edges de encomenda.
 */
export function dpdMode(): "qa" | "off" | "live" {
  const m = env("DPD_MODE").toLowerCase();
  if (m === "qa") return "qa";
  if (m === "live") return "live";
  return "off";
}

/** LEGADO default QA — preferir dpdApiBaseForMode(ops_dpd_mode). */
export function dpdApiBase(): string {
  return env("DPD_QA_BASE") || DPD_QA_BASE;
}

/** Endpoint oficial Rui (ZIP 134) — NÃO /expedition/create */
export const DPD_REGISTAR_EXPEDICAO_PATH =
  "/api/v1/pt/expedition/registarExpedicao";

/** Base64 → bytes (PDF seguro; não passar por TextEncoder). */
export function b64ToUint8Array(b64: string): Uint8Array {
  const bin = atob(b64.replace(/\s/g, ""));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export async function dpdForward(opts: {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  body?: string | null;
}): Promise<{
  status: number;
  bodyText: string;
  ok: boolean;
  bodyBytes: Uint8Array | null;
}> {
  const proxyUrl = env("DPD_PROXY_URL") ||
    "https://vps-27d76f35.vps.ovh.net/forward";
  const bearer = env("DPD_PROXY_BEARER");
  if (!bearer) {
    throw new Error("DPD_PROXY_BEARER missing");
  }
  const res = await fetch(proxyUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${bearer}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      url: opts.url,
      method: opts.method ?? "POST",
      headers: opts.headers ?? {},
      body: opts.body ?? null,
    }),
  });
  const text = await res.text();
  let upstreamStatus = res.status;
  let upstreamBody = text;
  let bodyBytes: Uint8Array | null = null;
  try {
    const j = JSON.parse(text) as {
      status?: number;
      body?: string;
      body_b64?: string;
      ok?: boolean;
      error?: string;
    };
    if (typeof j.status === "number") upstreamStatus = j.status;
    // Proxy VPS: respostas grandes/binárias vêm em body_b64 (ZIP 159.1)
    if (typeof j.body_b64 === "string" && j.body_b64.length > 0) {
      try {
        bodyBytes = b64ToUint8Array(j.body_b64);
        upstreamBody = atob(j.body_b64);
      } catch {
        upstreamBody = j.body_b64;
      }
    } else if (typeof j.body === "string") {
      upstreamBody = j.body;
    }
    if (j.ok === false && j.error) {
      return { status: res.status, bodyText: text, ok: false, bodyBytes: null };
    }
  } catch {
    /* raw */
  }
  return {
    status: upstreamStatus,
    bodyText: upstreamBody,
    ok: upstreamStatus >= 200 && upstreamStatus < 300,
    bodyBytes,
  };
}

/** GET etiqueta PDF autenticado (OAuth via proxy) — mode sticky da encomenda. */
export async function fetchDpdLabelPdfBytes(
  guide: string,
  mode: "qa" | "commercial" = "qa",
): Promise<Uint8Array | null> {
  const g = guide.trim();
  if (!g) return null;
  const { dpdApiBaseForMode } = await import("./ops_env.ts");
  const token = await dpdOauthTokenForMode(mode);
  const fwd = await dpdForward({
    url: `${dpdApiBaseForMode(mode)}/api/v1/pt/expedition/etiquetaApi/${g}`,
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/pdf,*/*",
    },
    body: null,
  });
  if (!fwd.ok) return null;
  if (fwd.bodyBytes && fwd.bodyBytes.length > 100) {
    // %PDF
    if (fwd.bodyBytes[0] === 0x25 && fwd.bodyBytes[1] === 0x50) {
      return fwd.bodyBytes;
    }
  }
  // Fallback: bodyText Latin1
  if (fwd.bodyText.startsWith("%PDF")) {
    const out = new Uint8Array(fwd.bodyText.length);
    for (let i = 0; i < fwd.bodyText.length; i++) {
      out[i] = fwd.bodyText.charCodeAt(i) & 0xff;
    }
    return out;
  }
  return null;
}

/** MyPudo GetPudoList — HTTPS directo (rede Geopost; não exige IP Business). */
export async function getPudoList(opts: {
  zipCode: string;
  countrycode?: string;
  city: string;
  dateFrom?: string; // dd/mm/yyyy
  requestId?: string;
}): Promise<{ ok: boolean; points: DpdPudoPoint[]; rawError?: string }> {
  const key = env("DPD_MYPUDO_KEY");
  if (!key) {
    return { ok: false, points: [], rawError: "DPD_MYPUDO_KEY missing" };
  }
  const zip = opts.zipCode.trim();
  const city = opts.city.trim();
  if (!zip || !city) {
    return { ok: false, points: [], rawError: "zipCode_and_city_required" };
  }
  const country = (opts.countrycode ?? "PRT").trim().toUpperCase() || "PRT";
  const dateFrom = opts.dateFrom ?? formatDdMmYyyy(new Date());
  const requestId = (opts.requestId ?? `FLEABER_${Date.now()}`).slice(0, 40);

  const soap =
    `<?xml version="1.0" encoding="utf-8"?>` +
    `<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:myp="http://MyPudo.pickup-services.com/">` +
    `<soap:Header/><soap:Body><myp:GetPudoList>` +
    `<myp:carrier>CHR</myp:carrier>` +
    `<myp:key>${xmlEscape(key)}</myp:key>` +
    `<myp:zipCode>${xmlEscape(zip)}</myp:zipCode>` +
    `<myp:pudotype></myp:pudotype>` +
    `<myp:countrycode>${xmlEscape(country)}</myp:countrycode>` +
    `<myp:requestID>${xmlEscape(requestId)}</myp:requestID>` +
    `<myp:city>${xmlEscape(city)}</myp:city>` +
    `<myp:holiday_tolerant>0</myp:holiday_tolerant>` +
    `<myp:date_from>${xmlEscape(dateFrom)}</myp:date_from>` +
    `</myp:GetPudoList></soap:Body></soap:Envelope>`;

  const res = await fetch(DPD_MYPUDO_ASMX, {
    method: "POST",
    headers: {
      "Content-Type": "application/soap+xml; charset=utf-8",
    },
    body: soap,
  });
  const text = await res.text();
  if (!res.ok) {
    return { ok: false, points: [], rawError: `http_${res.status}` };
  }
  const errMatch = text.match(/<ERROR[^>]*>([^<]*)</i);
  if (errMatch && !text.includes("<PUDO_ID>")) {
    return { ok: false, points: [], rawError: errMatch[1] };
  }
  return { ok: true, points: parsePudoXml(text) };
}

export function parsePudoXml(xml: string): DpdPudoPoint[] {
  const chunks = xml.split(/<PUDO_ID>/i).slice(1);
  const out: DpdPudoPoint[] = [];
  for (const chunk of chunks) {
    const pudoId = (chunk.split(/<\/PUDO_ID>/i)[0] ?? "").trim();
    if (!pudoId) continue;
    const rest = chunk;
    out.push({
      pudoId,
      name: xmlTag(rest, "NAME"),
      address1: xmlTag(rest, "ADDRESS1"),
      zipCode: xmlTag(rest, "ZIPCODE"),
      city: xmlTag(rest, "CITY"),
      latitude: xmlTag(rest, "LATITUDE") || undefined,
      longitude: xmlTag(rest, "LONGITUDE") || undefined,
    });
  }
  return out;
}

function xmlTag(s: string, tag: string): string {
  const m = s.match(new RegExp(`<${tag}[^>]*>([^<]*)`, "i"));
  return (m?.[1] ?? "").trim();
}

function xmlEscape(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function formatDdMmYyyy(d: Date): string {
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

export async function dpdOauthToken(): Promise<string> {
  // Compat ZIP≤171: default QA (sem DPD_MODE).
  return dpdOauthTokenForMode("qa");
}

/** ZIP 172: OAuth por modo sticky da encomenda (QA vs LIVE creds). */
export async function dpdOauthTokenForMode(
  mode: "qa" | "commercial",
): Promise<string> {
  // Import dinâmico evitado — resolver inline para não circular com ops_env em todos os callers.
  const { resolveDpdOauthForMode } = await import("./ops_env.ts");
  const resolved = resolveDpdOauthForMode(mode);
  if (!resolved.ok || !resolved.creds) {
    throw new Error(resolved.error ?? "dpd_oauth_unresolved");
  }
  const c = resolved.creds;
  const body = new URLSearchParams({
    username: c.username,
    password: c.password,
    client_id: c.clientId,
    client_secret: c.clientSecret,
    grant_type: "password",
  }).toString();
  const fwd = await dpdForward({
    url: `${c.baseUrl}/api/v1/pt/oauth/token`,
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!fwd.ok) {
    throw new Error(`oauth_failed_${fwd.status}`);
  }
  const j = JSON.parse(fwd.bodyText) as {
    result?: { access_token?: string };
  };
  const token = j.result?.access_token;
  if (!token) throw new Error("oauth_no_token");
  return token;
}

/**
 * Payload oficial Rui — ZIP 134 (`registarExpedicao`).
 * sub_account.code = 03546101 (S2S) | 03546102 (S2H).
 * Pickup: destinatario_usar_endereco_pickup + recipient_pickup_store.number.
 */
export function buildExpeditionPayloadCandidate(opts: {
  service: DpdServiceKind;
  sender: DpdParty;
  recipient: DpdParty;
  pudoId?: string | null;
  orderId: string;
  weightKg?: number;
  expeditionDate?: string; // YYYY-MM-DD
  contactPhone?: string | null;
  contactEmail?: string | null;
}): {
  payload: Record<string, unknown>;
  blockers: string[];
  subAccount: string;
} {
  const subAccount = opts.service === "shop_to_shop"
    ? DPD_SUBACCOUNT_SHOP_TO_SHOP
    : DPD_SUBACCOUNT_SHOP_TO_HOME;

  const tomorrow = new Date();
  tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
  const expeditionDate = opts.expeditionDate ??
    tomorrow.toISOString().slice(0, 10);

  const blockers: string[] = [];
  if (opts.service === "shop_to_shop" && !opts.pudoId) {
    blockers.push(
      "shop_to_shop exige delivery_point_ref (PUDO number, ex. PT11479).",
    );
  }
  if (!opts.sender.name || !opts.sender.address1 || !opts.sender.zipCode) {
    blockers.push("sender/shipper incompleto (morada origem vendedor).");
  }
  if (opts.service === "shop_to_home") {
    if (!opts.recipient.address1 || !opts.recipient.zipCode || !opts.recipient.city) {
      blockers.push("shop_to_home exige morada completa do destinatário.");
    }
  }

  const phone = (opts.contactPhone ?? opts.recipient.phone ?? "").replace(
    /\D/g,
    "",
  ) || "910000000";
  const email = (opts.contactEmail ?? opts.recipient.email ?? "").trim() ||
    "noreply@fleaber.app";
  const weight = Math.max(0.1, Math.min(10, opts.weightKg ?? 1));
  const isPickup = opts.service === "shop_to_shop";

  const payload: Record<string, unknown> = {
    sub_account: { code: subAccount },
    sender: {
      id: null,
      name: opts.sender.name,
      phone: null,
      phone_code: null,
      mobile: null,
      mobile_code: null,
      email: opts.sender.email || "seller@fleaber.app",
      save: false,
    },
    shipper: {
      name: opts.sender.name,
      address: opts.sender.address1,
      zip_code: opts.sender.zipCode,
      location: opts.sender.city,
      country: { id: (opts.sender.country || "PT").slice(0, 2).toUpperCase() },
    },
    recipient: {
      id: null,
      name: opts.recipient.name,
      client_code: null,
      save: false,
    },
    address: {
      id: null,
      country: {
        id: (opts.recipient.country || "PT").slice(0, 2).toUpperCase(),
        iso2: (opts.recipient.country || "PT").slice(0, 2).toUpperCase(),
      },
      address: opts.recipient.address1 || (isPickup ? "Pickup DPD" : ""),
      zip_code: opts.recipient.zipCode || "0000-000",
      location: opts.recipient.city || "Portugal",
      save: false,
    },
    contact: {
      id: null,
      name: opts.recipient.name,
      phone: phone.slice(0, 15),
      phone_code: "351",
      mobile: phone.slice(0, 15),
      mobile_code: "351",
      email,
      save: false,
    },
    destinatario_usar_endereco_pickup: isPickup,
    recipient_pickup_store: {
      number: isPickup ? String(opts.pudoId ?? "").trim() : "",
    },
    pickup_store_name: opts.recipient.name,
    pickup_store_mobile: phone.slice(0, 15),
    pickup_store_mobile_code: "351",
    pickup_store_email: email,
    opcoes_servico_predict_para_entrega: false,
    // DPD QA: referência ≤ 16 chars (ZIP 159.1)
    encomenda_referencia: opts.orderId.replace(/-/g, "").slice(0, 16),
    opcoes_servico_codigo_at: null,
    encomenda_observacao: `Fleaber ${opts.orderId.slice(0, 8)}`,
    expedition_date: expeditionDate,
    expedition_time: "23:59",
    encomenda_peso_envio: String(weight),
    encomenda_num_volumes: 1,
    opcoes_servico_enviar_a_cobranca: false,
    opcoes_servico_montante: null,
    etiqueta_hide_nome: false,
    etiqueta_hide_telemovel: false,
    etiqueta_hide_email: false,
    etiqueta_formato: { id: 3 },
    etiqueta_enviar_etiqueta_por_email: false,
    zpl_response: false,
    pdf_response: true,
    qr_response: false,
  };

  return { payload, blockers, subAccount };
}

/** Extrai guia + URL / PDF base64 da resposta registarExpedicao (ZIP 134). */
export function parseRegistarExpedicaoResult(parsed: unknown): {
  guide: string | null;
  labelUrl: string | null;
  expeditionId: string | null;
  hasPdf: boolean;
  pdfBase64: string | null;
} {
  const root = parsed as {
    result?: Record<string, unknown>;
    message?: string;
  } | null;
  const result = root?.result ?? null;
  if (!result) {
    return {
      guide: null,
      labelUrl: null,
      expeditionId: null,
      hasPdf: false,
      pdfBase64: null,
    };
  }
  let guide: string | null = null;
  const ng = result.num_guia;
  if (Array.isArray(ng) && ng.length > 0) {
    guide = String(ng[0] ?? "").trim() || null;
  } else if (typeof ng === "string") {
    guide = ng.trim() || null;
  }
  if (!guide) {
    const alt = result.tracking ?? result.tracking_code ?? result.guia;
    if (alt != null) guide = String(alt).trim() || null;
  }
  const labelUrl = result.pdf_url != null
    ? String(result.pdf_url).trim()
    : null;
  const expeditionId = result.id != null
    ? String(result.id)
    : (guide ?? null);
  const pdfBase64 = typeof result.pdf === "string" && result.pdf.length > 20
    ? result.pdf
    : null;
  const hasPdf = pdfBase64 != null;
  return { guide, labelUrl, expeditionId, hasPdf, pdfBase64 };
}

/** True se a URL ainda é o endpoint privado DPD (não abre no telemóvel). */
export function isDpdPrivateLabelUrl(url: string | null | undefined): boolean {
  const u = (url ?? "").trim().toLowerCase();
  if (!u) return true;
  return u.includes("dpd.pt/") && u.includes("etiquetaapi");
}

/** Trace API DPD PT (email Rui) — GET wservices.dpd.pt/trace/track */
export const DPD_TRACK_BASE = "https://wservices.dpd.pt/trace/track";

export type DpdTrackEvent = {
  at: string | null;
  code: string | null;
  description: string;
  location: string | null;
  raw: Record<string, unknown>;
};

export type DpdTrackResult = {
  ok: boolean;
  status:
    | "ok"
    | "empty"
    | "not_found"
    | "missing_guide"
    | "config"
    | "upstream_error"
    | "invalid_response";
  guide: string;
  countrycode: string;
  events: DpdTrackEvent[];
  message?: string;
  http_status?: number;
};

export async function fetchDpdTrace(opts: {
  guide: string;
  countrycode?: string; // PT | EN
}): Promise<DpdTrackResult> {
  const guide = opts.guide.trim();
  const countrycode = (opts.countrycode ?? "PT").trim().toUpperCase() === "EN"
    ? "EN"
    : "PT";
  if (!guide) {
    return {
      ok: false,
      status: "missing_guide",
      guide: "",
      countrycode,
      events: [],
      message: "Sem número de guia DPD nesta encomenda.",
    };
  }
  const key = env("DPD_TRACKING_API_KEY");
  if (!key) {
    return {
      ok: false,
      status: "config",
      guide,
      countrycode,
      events: [],
      message: "DPD_TRACKING_API_KEY em falta no backend.",
    };
  }
  const url =
    `${DPD_TRACK_BASE}?countrycode=${encodeURIComponent(countrycode)}` +
    `&search=${encodeURIComponent(guide)}`;
  try {
    const res = await fetch(url, {
      method: "GET",
      headers: {
        apikey: key,
        Accept: "application/json",
      },
    });
    const text = await res.text();
    if (!res.ok) {
      let msg = `Erro DPD (${res.status})`;
      try {
        const j = JSON.parse(text) as {
          title?: string;
          errors?: Record<string, string[]>;
        };
        if (j.title) msg = j.title;
        const searchErr = j.errors?.search?.[0];
        if (searchErr) msg = searchErr;
      } catch { /* keep */ }
      return {
        ok: false,
        status: "upstream_error",
        guide,
        countrycode,
        events: [],
        message: msg,
        http_status: res.status,
      };
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      return {
        ok: false,
        status: "invalid_response",
        guide,
        countrycode,
        events: [],
        message: "Resposta de tracking inválida.",
        http_status: res.status,
      };
    }
    const events = normalizeTrackEvents(parsed);
    if (events.length === 0) {
      return {
        ok: true,
        status: "empty",
        guide,
        countrycode,
        events: [],
        message:
          "Ainda não há eventos de tracking para esta guia (ou a guia ainda não existe na rede DPD).",
        http_status: res.status,
      };
    }
    return {
      ok: true,
      status: "ok",
      guide,
      countrycode,
      events,
      http_status: res.status,
    };
  } catch (e) {
    return {
      ok: false,
      status: "upstream_error",
      guide,
      countrycode,
      events: [],
      message: e instanceof Error ? e.message : String(e),
    };
  }
}

/** Normaliza formatos possíveis sem inventar campos obrigatórios. */
export function normalizeTrackEvents(parsed: unknown): DpdTrackEvent[] {
  const list = extractEventArray(parsed);
  const out: DpdTrackEvent[] = [];
  for (const item of list) {
    if (item == null) continue;
    if (typeof item === "string") {
      const t = item.trim();
      if (t) {
        out.push({
          at: null,
          code: null,
          description: t,
          location: null,
          raw: { value: t },
        });
      }
      continue;
    }
    if (typeof item !== "object") continue;
    const m = item as Record<string, unknown>;
    const description = firstString(m, [
      "description",
      "Description",
      "statusDescription",
      "StatusDescription",
      "event",
      "Event",
      "message",
      "Message",
      "status",
      "Status",
      "detail",
      "Detail",
      "texto",
      "Texto",
    ]) ?? "";
    const at = firstString(m, [
      "date",
      "Date",
      "datetime",
      "DateTime",
      "timestamp",
      "Timestamp",
      "localTime",
      "LocalTime",
      "eventDate",
      "EventDate",
      "data",
      "Data",
      "hora",
      "Hora",
    ]);
    const code = firstString(m, [
      "code",
      "Code",
      "statusCode",
      "StatusCode",
      "eventCode",
      "EventCode",
    ]);
    const location = firstString(m, [
      "location",
      "Location",
      "place",
      "Place",
      "city",
      "City",
      "depot",
      "Depot",
    ]);
    if (!description && !at && !code) continue;
    out.push({
      at,
      code,
      description: description || (code ?? "Atualização DPD"),
      location,
      raw: m,
    });
  }
  return out;
}

function extractEventArray(parsed: unknown): unknown[] {
  if (Array.isArray(parsed)) {
    // Lista de eventos OU lista de parcels com nested events
    if (
      parsed.length > 0 &&
      typeof parsed[0] === "object" &&
      parsed[0] != null &&
      (Array.isArray((parsed[0] as Record<string, unknown>).events) ||
        Array.isArray((parsed[0] as Record<string, unknown>).Events) ||
        Array.isArray((parsed[0] as Record<string, unknown>).details) ||
        Array.isArray((parsed[0] as Record<string, unknown>).Details) ||
        Array.isArray((parsed[0] as Record<string, unknown>).scans))
    ) {
      const nested: unknown[] = [];
      for (const p of parsed) {
        if (typeof p !== "object" || p == null) continue;
        const m = p as Record<string, unknown>;
        const arr =
          m.events ?? m.Events ?? m.details ?? m.Details ?? m.scans ?? m.history;
        if (Array.isArray(arr)) nested.push(...arr);
      }
      return nested.length > 0 ? nested : parsed;
    }
    return parsed;
  }
  if (typeof parsed === "object" && parsed != null) {
    const m = parsed as Record<string, unknown>;
    for (const k of [
      "events",
      "Events",
      "details",
      "Details",
      "scans",
      "history",
      "History",
      "result",
      "Result",
      "data",
      "Data",
    ]) {
      const v = m[k];
      if (Array.isArray(v)) return extractEventArray(v);
    }
  }
  return [];
}

function firstString(
  m: Record<string, unknown>,
  keys: string[],
): string | null {
  for (const k of keys) {
    const v = m[k];
    if (v == null) continue;
    const s = String(v).trim();
    if (s) return s;
  }
  // date + time separados
  if (keys.includes("date") || keys.includes("Date")) {
    const d = m["date"] ?? m["Date"] ?? m["data"] ?? m["Data"];
    const t = m["time"] ?? m["Time"] ?? m["hora"] ?? m["Hora"];
    if (d != null) {
      const ds = String(d).trim();
      const ts = t != null ? String(t).trim() : "";
      if (ds && ts) return `${ds} ${ts}`;
      if (ds) return ds;
    }
  }
  return null;
}
