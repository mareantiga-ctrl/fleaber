/**
 * ZIP DPD — lista de pontos Pickup (GetPudoList / MyPudo).
 * Autenticado. Credenciais MyPudo só em secrets.
 * Aceita CP, localidade, ou ambos. Ordena por proximidade quando há coords.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { getPudoList } from "../_shared/dpd_client.ts";

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

function normalizeCp(raw: string): string | null {
  const digits = raw.replace(/\D/g, "");
  if (digits.length !== 7) return null;
  return `${digits.slice(0, 4)}-${digits.slice(4)}`;
}

function haversineKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const R = 6371;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function parseCoord(raw: unknown): number | null {
  if (raw == null) return null;
  const n = typeof raw === "number" ? raw : Number(String(raw).replace(",", "."));
  return Number.isFinite(n) ? n : null;
}

async function resolveCityFromCp(zipCode: string): Promise<{
  city: string | null;
  lat: number | null;
  lon: number | null;
}> {
  try {
    const geo = await fetch(`https://geoapi.pt/cp/${zipCode}?json=1`, {
      headers: { Accept: "application/json" },
    });
    if (!geo.ok) return { city: null, lat: null, lon: null };
    const g = await geo.json() as Record<string, unknown>;
    const loc = String(
      g["Localidade"] ?? g["localidade"] ?? g["municipio"] ?? "",
    ).trim();
    const lat = parseCoord(g["lat"] ?? g["Latitude"] ?? g["latitude"]);
    const lon = parseCoord(g["lon"] ?? g["Longitude"] ?? g["longitude"]);
    return { city: loc || null, lat, lon };
  } catch {
    return { city: null, lat: null, lon: null };
  }
}

/** Localidade → CP representativo (geoapi município / localidade). */
async function resolveCpFromCity(city: string): Promise<{
  zipCode: string | null;
  city: string | null;
  lat: number | null;
  lon: number | null;
}> {
  const q = city.trim();
  if (q.length < 2) return { zipCode: null, city: null, lat: null, lon: null };
  try {
    // 1) Tentativa directa por nome de município
    const mUrl =
      `https://geoapi.pt/municipio/${encodeURIComponent(q)}?json=1`;
    const mRes = await fetch(mUrl, { headers: { Accept: "application/json" } });
    if (mRes.ok) {
      const m = await mRes.json() as Record<string, unknown>;
      const nome = String(m["nome"] ?? q).trim();
      const lat = parseCoord(m["lat"] ?? m["latitude"]);
      const lon = parseCoord(m["lon"] ?? m["longitude"]);
      // Alguns municípios expõem lista de CPs
      const cps = m["codigos_postais"] ?? m["codigos-postais"] ?? m["cps"];
      let zip: string | null = null;
      if (Array.isArray(cps) && cps.length > 0) {
        zip = normalizeCp(String(cps[0]));
      }
      if (!zip) {
        // Fallback: geoapi CP search by locality name via /cp?localidade=
        const cpRes = await fetch(
          `https://geoapi.pt/cp?json=1&localidade=${encodeURIComponent(nome)}`,
          { headers: { Accept: "application/json" } },
        );
        if (cpRes.ok) {
          const cpData = await cpRes.json();
          if (Array.isArray(cpData) && cpData.length > 0) {
            const first = cpData[0] as Record<string, unknown>;
            zip = normalizeCp(String(first["CP"] ?? first["cp"] ?? first));
          } else if (cpData && typeof cpData === "object") {
            zip = normalizeCp(
              String((cpData as Record<string, unknown>)["CP"] ?? ""),
            );
          }
        }
      }
      if (zip) return { zipCode: zip, city: nome, lat, lon };
    }

    // 2) Pesquisa fuzzy de município
    const search = await fetch(
      `https://geoapi.pt/municipio?json=1&nome=${encodeURIComponent(q)}`,
      { headers: { Accept: "application/json" } },
    );
    if (search.ok) {
      const data = await search.json();
      const row = Array.isArray(data) ? data[0] : data;
      if (row && typeof row === "object") {
        const nome = String((row as { nome?: string }).nome ?? q).trim();
        return await resolveCpFromCity(nome);
      }
    }
  } catch {
    /* fallthrough */
  }
  return { zipCode: null, city: q, lat: null, lon: null };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ ok: false, error: "auth_required" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user?.id) {
    return json({ ok: false, error: "auth_required" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  let zipCode = String(body.zipCode ?? body.zip_code ?? "").trim();
  let city = String(body.city ?? "").trim();
  const countrycode = String(body.countrycode ?? body.country ?? "PRT").trim();

  let resolvedCity: string | null = null;
  let originLat: number | null = null;
  let originLon: number | null = null;

  const normalized = normalizeCp(zipCode);
  if (normalized) zipCode = normalized;

  if (zipCode && !city) {
    const geo = await resolveCityFromCp(zipCode);
    if (geo.city) {
      city = geo.city;
      resolvedCity = geo.city;
    }
    originLat = geo.lat;
    originLon = geo.lon;
  } else if (!zipCode && city) {
    const geo = await resolveCpFromCity(city);
    if (geo.zipCode) {
      zipCode = geo.zipCode;
      if (geo.city) {
        city = geo.city;
        resolvedCity = geo.city;
      }
      originLat = geo.lat;
      originLon = geo.lon;
    }
  } else if (zipCode && city) {
    const geo = await resolveCityFromCp(zipCode);
    originLat = geo.lat;
    originLon = geo.lon;
    // Usa a cidade enviada conscientemente; não substitui pela do CP.
  }

  if (!zipCode && !city) {
    return json({
      ok: false,
      error: "search_required",
      hint: "Indica um código postal português e/ou uma localidade.",
      points: [],
    }, 422);
  }
  if (!zipCode) {
    return json({
      ok: false,
      error: "zip_required",
      hint:
        "Não conseguimos deduzir um código postal desta localidade. Indica também o CP (NNNN-NNN).",
      points: [],
      city,
    }, 422);
  }
  if (!city) {
    return json({
      ok: false,
      error: "city_required",
      hint:
        "Não conseguimos deduzir a localidade deste CP. Escreve a cidade (ex. Lisboa).",
      points: [],
      postal_code: zipCode,
    }, 422);
  }

  const result = await getPudoList({ zipCode, city, countrycode });
  if (!result.ok) {
    return json({
      ok: false,
      error: result.rawError ?? "pudo_failed",
      points: [],
      postal_code: zipCode,
      city,
      resolved_city: resolvedCity,
    }, 422);
  }

  let points = result.points.map((p) => {
    const lat = parseCoord(p.latitude);
    const lon = parseCoord(p.longitude);
    let distance_km: number | null = null;
    if (
      originLat != null &&
      originLon != null &&
      lat != null &&
      lon != null
    ) {
      distance_km = Math.round(haversineKm(originLat, originLon, lat, lon) * 10) /
        10;
    }
    return { ...p, distance_km };
  });

  if (points.some((p) => p.distance_km != null)) {
    points = [...points].sort((a, b) => {
      const da = a.distance_km ?? Number.POSITIVE_INFINITY;
      const db = b.distance_km ?? Number.POSITIVE_INFINITY;
      return da - db;
    });
  }

  return json({
    ok: true,
    count: points.length,
    points,
    postal_code: zipCode,
    city,
    resolved_city: resolvedCity,
  });
});
