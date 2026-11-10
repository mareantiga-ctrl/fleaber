/**
 * Resolução CP/localidade PT via geoapi.pt (fonte postal pública).
 * Não substitui a morada do utilizador — só sugere / preenche.
 * Autenticado (anon JWT). Sem secrets DPD.
 */
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ ok: false, error: "auth_required" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  const localityQuery = String(body.locality_query ?? body.q ?? "").trim();
  if (localityQuery.length >= 2) {
    try {
      const url =
        `https://geoapi.pt/municipio?json=1&nome=${
          encodeURIComponent(localityQuery)
        }`;
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
      });
      if (!res.ok) {
        return json({ ok: true, suggestions: [] });
      }
      const data = await res.json();
      const suggestions: string[] = [];
      if (Array.isArray(data)) {
        for (const row of data) {
          const nome = String(
            (row as { nome?: string }).nome ?? row ?? "",
          ).trim();
          if (nome) suggestions.push(nome);
        }
      } else if (data && typeof data === "object") {
        const nome = String((data as { nome?: string }).nome ?? "").trim();
        if (nome) suggestions.push(nome);
      }
      return json({
        ok: true,
        suggestions: [...new Set(suggestions)].slice(0, 12),
      });
    } catch (e) {
      return json({
        ok: false,
        error: e instanceof Error ? e.message : String(e),
        suggestions: [],
      }, 502);
    }
  }

  const cp = normalizeCp(
    String(body.postal_code ?? body.postalCode ?? body.cp ?? ""),
  );
  if (!cp) {
    return json({
      ok: false,
      error: "invalid_postal_code",
      hint: "Usa o formato NNNN-NNN.",
    }, 422);
  }

  try {
    const res = await fetch(`https://geoapi.pt/cp/${cp}?json=1`, {
      headers: { Accept: "application/json" },
    });
    if (res.status === 404) {
      return json({ ok: false, error: "postal_not_found", postal_code: cp }, 404);
    }
    if (!res.ok) {
      return json({
        ok: false,
        error: `geoapi_http_${res.status}`,
        postal_code: cp,
      }, 502);
    }
    const data = await res.json() as Record<string, unknown>;
    const locality = String(
      data["Localidade"] ?? data["localidade"] ?? data["municipio"] ?? "",
    ).trim();
    const municipality = String(
      data["Concelho"] ?? data["municipio"] ?? "",
    ).trim() || null;
    const district = String(data["Distrito"] ?? "").trim() || null;
    if (!locality) {
      return json({ ok: false, error: "locality_missing", postal_code: cp }, 404);
    }
    return json({
      ok: true,
      postal_code: cp,
      locality,
      municipality,
      district,
    });
  } catch (e) {
    return json({
      ok: false,
      error: e instanceof Error ? e.message : String(e),
      postal_code: cp,
    }, 502);
  }
});
