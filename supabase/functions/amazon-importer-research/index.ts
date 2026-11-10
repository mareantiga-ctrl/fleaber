/**
 * Amazon Importer — pesquisa pública (sem API paga).
 * Admin-only. Não contorna CAPTCHA. Para ao primeiro bloqueio persistente.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MARKETS: { code: string; host: string }[] = [
  { code: "es", host: "www.amazon.es" },
  { code: "it", host: "www.amazon.it" },
  { code: "de", host: "www.amazon.de" },
  { code: "fr", host: "www.amazon.fr" },
];

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function extractTitle(html: string): string | null {
  const m = html.match(/<title>([^<]+)<\/title>/i);
  if (!m) return null;
  return m[1]
    .replace(/\s*[|:].*Amazon.*$/i, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 500) || null;
}

function isBlocked(html: string, title: string | null): boolean {
  const t = (title ?? "").toLowerCase();
  if (/captcha|robot check|validatecaptcha/i.test(html)) return true;
  if (/robot|captcha/i.test(t)) return true;
  if (/api-services-support@amazon\.com/i.test(html)) return true;
  return false;
}

/** Preço numérico real — só padrões claros; nunca inventa. */
function extractPriceEur(
  html: string,
): { amount: number; currency: string } | null {
  const patterns: RegExp[] = [
    /"priceAmount"\s*:\s*([0-9]+(?:\.[0-9]+)?)/,
    /"displayAmount"\s*:\s*"€\s*([0-9]+(?:[.,][0-9]+)?)"/,
    /class="a-price-whole">([0-9.]+)<[\s\S]{0,120}?a-price-fraction">([0-9]+)/,
    /id="priceblock_ourprice"[^>]*>\s*€?\s*([0-9]+[.,][0-9]{2})/,
    /"price"\s*:\s*"€?\s*([0-9]+[.,][0-9]{2})"/,
  ];
  for (const re of patterns) {
    const m = html.match(re);
    if (!m) continue;
    if (m[2]) {
      const whole = m[1].replace(/\./g, "");
      const amount = Number(`${whole}.${m[2]}`);
      if (Number.isFinite(amount) && amount > 0) {
        return { amount, currency: "EUR" };
      }
    } else {
      const raw = m[1].replace(",", ".");
      const amount = Number(raw);
      if (Number.isFinite(amount) && amount > 0) {
        return { amount, currency: "EUR" };
      }
    }
  }
  return null;
}

function extractAvailability(html: string): string | null {
  const m = html.match(
    /id="availability"[^>]*>[\s\S]{0,500}?<span[^>]*>([^<]{3,120})/i,
  );
  if (m) return m[1].replace(/\s+/g, " ").trim().slice(0, 120);
  const j = html.match(/"availability"\s*:\s*"([^"]+)"/i);
  if (j) return j[1].slice(0, 120);
  if (
    /Currently unavailable|No disponible|Non disponibile|Derzeit nicht verfügbar|Actuellement indisponible/i
      .test(html)
  ) {
    return "unavailable";
  }
  return null;
}

/** URLs de imagem Amazon (referência; direitos a verificar antes de publicar). */
function extractImageUrls(html: string): string[] {
  const urls = new Set<string>();
  const patterns = [
    /"hiRes"\s*:\s*"(https:\/\/[^"]+)"/g,
    /"large"\s*:\s*"(https:\/\/[^"]+)"/g,
    /data-old-hires="(https:\/\/[^"]+)"/g,
    /(https:\/\/m\.media-amazon\.com\/images\/I\/[A-Za-z0-9._%-]+\.(?:jpg|jpeg|png))/gi,
  ];
  for (const re of patterns) {
    let m: RegExpExecArray | null;
    while ((m = re.exec(html)) && urls.size < 8) {
      const u = m[1].replace(/\\u002F/g, "/");
      if (/m\.media-amazon\.com|images-amazon\.com/i.test(u)) urls.add(u);
    }
  }
  return [...urls];
}

/** CDN por ASIN — sem HTML. JPEG real; ignora GIF 1×1 / placeholders. */
async function fetchCdnPhotosByAsin(asin: string): Promise<string[]> {
  const out: string[] = [];
  const seen = new Set<string>();
  for (let i = 1; i <= 5; i++) {
    const nn = String(i).padStart(2, "0");
    const candidates = [
      `https://m.media-amazon.com/images/P/${asin}.${nn}.LZZZZZZZ.jpg`,
      `https://images-eu.ssl-images-amazon.com/images/P/${asin}.${nn}.LZZZZZZZ.jpg`,
    ];
    for (const url of candidates) {
      try {
        const resp = await fetch(url, {
          headers: { "User-Agent": "FleaberImporter/156", Accept: "image/*" },
          redirect: "follow",
        });
        if (!resp.ok) continue;
        const buf = new Uint8Array(await resp.arrayBuffer());
        // JPEG magic FF D8; mínimo ~1.5 KB
        if (buf.length < 1500 || buf[0] !== 0xff || buf[1] !== 0xd8) continue;
        const key = `${buf.length}:${buf[100] ?? 0}:${buf[200] ?? 0}`;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push(url);
        break;
      } catch {
        // next candidate
      }
    }
    if (out.length >= 5) break;
  }
  return out;
}

async function savePhotos(
  admin: ReturnType<typeof createClient>,
  productId: string,
  urls: string[],
  source: "amazon_ref_pending_rights" | "amazon_cdn_pending_rights",
) {
  if (urls.length === 0) return;
  await admin
    .from("amazon_product_photos")
    .delete()
    .eq("product_id", productId)
    .eq("source", source);
  let sort = 0;
  for (const img of urls.slice(0, 6)) {
    await admin.from("amazon_product_photos").insert({
      product_id: productId,
      storage_path: img,
      public_url: img,
      sort_order: sort,
      is_primary: sort === 0,
      source,
    });
    sort++;
  }
  await admin.from("amazon_catalog_products").update({
    primary_image_url: urls[0],
    photo_rights_status: "pending_rights",
    updated_at: new Date().toISOString(),
  }).eq("id", productId);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !serviceKey || !anonKey) {
    return json({ ok: false, error: "missing_env" }, 200);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  const uid = userData.user?.id ?? null;
  if (!uid) return json({ ok: false, error: "auth_required" }, 200);

  const { data: isAdmin } = await userClient.rpc(
    "batata_is_amazon_importer_admin",
  );
  if (isAdmin !== true) {
    return json({ ok: false, error: "forbidden" }, 200);
  }

  const body = await req.json().catch(() => ({}));
  const asin = String(body.asin ?? "").trim().toUpperCase();
  const productId = String(body.product_id ?? "").trim();
  const photosOnly = body.photos_only === true;
  if (!asin || !productId) {
    return json({ ok: false, error: "asin_and_product_id_required" }, 200);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  // Modo só fotografias: CDN; se vazio, uma tentativa HTML /dp (para se CAPTCHA).
  if (photosOnly) {
    let photos = await fetchCdnPhotosByAsin(asin);
    let source: "amazon_cdn_pending_rights" | "amazon_dp_html" =
      "amazon_cdn_pending_rights";
    if (photos.length === 0) {
      try {
        const url = `https://www.amazon.es/dp/${asin}`;
        const resp = await fetch(url, {
          headers: {
            "User-Agent":
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept-Language": "es-ES,es;q=0.9",
          },
          redirect: "follow",
        });
        const html = await resp.text();
        if (!isBlocked(html, extractTitle(html))) {
          const fromHtml = extractImageUrls(html).filter((u) =>
            /images\/I\//i.test(u)
          );
          if (fromHtml.length > 0) {
            photos = fromHtml.slice(0, 6);
            source = "amazon_dp_html";
          }
        }
      } catch {
        // ignore
      }
    }
    await savePhotos(admin, productId, photos, source);
    return json({
      ok: true,
      asin,
      product_id: productId,
      photo_count: photos.length,
      photos,
      photo_source: source,
      rights: "internal_ref — ferramenta privada; origem registada",
      note: photos.length
        ? `Fotografias obtidas (${source}).`
        : "Fotografias em falta (CDN/HTML sem JPEG válido ou CAPTCHA).",
    });
  }

  const offers: Record<string, unknown>[] = [];
  let blocked = false;
  let numericPriceCount = 0;

  for (const m of MARKETS) {
    if (blocked) {
      offers.push({
        marketplace: m.code,
        status: "skipped",
        error_text: "skipped_after_block",
      });
      continue;
    }
    const url = `https://${m.host}/dp/${asin}`;
    try {
      const resp = await fetch(url, {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Accept-Language": "es-ES,es;q=0.9,en;q=0.5",
        },
        redirect: "follow",
      });
      const html = await resp.text();
      const title = extractTitle(html);
      if (isBlocked(html, title) || resp.status === 503) {
        blocked = true;
        const row = {
          product_id: productId,
          marketplace: m.code,
          asin,
          fetched_at: new Date().toISOString(),
          status: "captcha",
          title,
          source_url: url,
          error_text: "blocked_or_captcha",
        };
        await admin.from("amazon_market_offers").insert(row);
        offers.push(row);
        break;
      }
      if (!resp.ok) {
        const row = {
          product_id: productId,
          marketplace: m.code,
          asin,
          fetched_at: new Date().toISOString(),
          status: "error",
          source_url: url,
          error_text: `http_${resp.status}`,
        };
        await admin.from("amazon_market_offers").insert(row);
        offers.push(row);
        continue;
      }
      const price = extractPriceEur(html);
      const availability = extractAvailability(html);
      const availLow = (availability ?? "").toLowerCase();
      const unavailable =
        /unavailable|no disponible|non disponibile|nicht verfügbar|indisponible|currently unavailable/
          .test(availLow);
      let status = "not_found";
      let errorText: string | undefined = "price_not_parsed_no_invention";
      if (price && !unavailable) {
        status = "ok";
        errorText = undefined;
        numericPriceCount++;
      } else if (price && unavailable) {
        status = "not_found";
        errorText = "unavailable_ignored";
      }
      const imageUrls = extractImageUrls(html);
      const row: Record<string, unknown> = {
        product_id: productId,
        marketplace: m.code,
        asin,
        fetched_at: new Date().toISOString(),
        status,
        title,
        price_amount: price?.amount ?? null,
        currency: price?.currency ?? null,
        availability,
        image_urls: imageUrls,
        source_url: url,
        raw_excerpt: html.slice(0, 400),
      };
      if (errorText) row.error_text = errorText;
      await admin.from("amazon_market_offers").insert(row);
      offers.push(row);

      // Título Amazon cru só se produto ainda for rascunho importado.
      // Imagens = referência (direitos pendentes); a app gera PT-PT.
      const patch: Record<string, unknown> = {
        catalog_status: status === "ok" ? "researched" : "needs_review",
        updated_at: new Date().toISOString(),
      };
      if (imageUrls.length > 0) {
        patch.primary_image_url = imageUrls[0];
      }
      const { data: prod } = await admin
        .from("amazon_catalog_products")
        .select("title, catalog_status")
        .eq("id", productId)
        .maybeSingle();
      const curTitle = (prod?.title ?? "").toString().trim();
      const st = (prod?.catalog_status ?? "").toString();
      if ((!curTitle || st === "imported") && title) {
        patch.title = title;
      }
      await admin.from("amazon_catalog_products").update(patch).eq(
        "id",
        productId,
      );

      if (imageUrls.length > 0) {
        await savePhotos(
          admin,
          productId,
          imageUrls,
          "amazon_ref_pending_rights",
        );
      }
      // Throttle mais alto — reduz CAPTCHA; sem contornar bloqueios.
      await new Promise((r) => setTimeout(r, 2800));
    } catch (e) {
      const row = {
        product_id: productId,
        marketplace: m.code,
        asin,
        fetched_at: new Date().toISOString(),
        status: "error",
        source_url: url,
        error_text: String(e),
      };
      await admin.from("amazon_market_offers").insert(row);
      offers.push(row);
    }
  }

  // CDN ASIN primeiro; se falhar e ainda não bloqueado, extrair images/I do HTML já obtido.
  let finalPhotos = await fetchCdnPhotosByAsin(asin);
  let photoSource: "amazon_cdn_pending_rights" | "amazon_dp_html" =
    "amazon_cdn_pending_rights";
  if (finalPhotos.length === 0 && !blocked) {
    // Reutiliza a última página OK (já em offers com image_urls).
    const fromOffers: string[] = [];
    for (const o of offers) {
      const arr = o.image_urls;
      if (Array.isArray(arr)) {
        for (const u of arr) {
          if (typeof u === "string" && /images\/I\//i.test(u)) fromOffers.push(u);
        }
      }
    }
    if (fromOffers.length > 0) {
      finalPhotos = [...new Set(fromOffers)].slice(0, 6);
      photoSource = "amazon_dp_html";
    }
  }
  if (finalPhotos.length > 0) {
    await savePhotos(admin, productId, finalPhotos, photoSource);
  }

  return json({
    ok: true,
    asin,
    product_id: productId,
    blocked,
    numeric_price_count: numericPriceCount,
    offers,
    photo_count: finalPhotos.length,
    photos: finalPhotos,
    photo_source: photoSource,
    note: blocked
      ? "Pesquisa interrompida (CAPTCHA/bloqueio). Sem contornar. CDN/HTML fotos tentadas à parte."
      : "Pesquisa pública concluída. Preços só numéricos parseáveis; nunca inventados.",
  });
});
