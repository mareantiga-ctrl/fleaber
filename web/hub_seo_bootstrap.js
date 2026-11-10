/**
 * Hub SEO bootstrap — corre **antes** do Flutter carregar.
 * Fonte: views hub_* + RPC batata_resolve_handle (anon, público).
 * Staging/localhost: sempre noindex. Produção fleaber.pt + Supabase prod: index,follow se publicado.
 *
 * Manter SUPABASE_* alinhado com lib/backend/supabase/supabase.dart (staging até aprovação prod).
 */
(function () {
  'use strict';

  var CONFIG = window.FLEABER_HUB_SEO || {
    supabaseUrl: 'https://fxdknzrqjenzqcvnwqqq.supabase.co',
    supabaseAnonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ4ZGtuenJxamVuenFjdm53cXFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3ODA1NTgsImV4cCI6MjA5MjM1NjU1OH0.cmnPjM0YxNbT6RcSurFEnexzLaN6sJsQrjodCz2Wf5I',
    productionHosts: ['fleaber.pt', 'www.fleaber.pt'],
    stagingProjectRef: 'fxdknzrqjenzqcvnwqqq',
    canonicalHost: 'https://fleaber.pt',
    defaultOgImage:
      'https://storage.googleapis.com/flutterflow-prod-hosting/og_splash_gradient.png',
    appTitle: 'Fleaber',
  };

  var RESERVED_FIRST_SEGMENTS = {
    login: 1,
    registo: 1,
    homepage: 1,
    admin: 1,
    productdetails: 1,
    fleaberliveplayer: 1,
    perfil: 1,
    chatpage: 1,
    wallet: 1,
    legalhub: 1,
    fleahub: 1,
    'stripe-success': 1,
  };

  function hostAllowsIndex(host) {
    host = (host || '').toLowerCase();
    if (CONFIG.productionHosts.indexOf(host) === -1) return false;
    if ((CONFIG.supabaseUrl || '').indexOf(CONFIG.stagingProjectRef) !== -1) {
      return false;
    }
    return true;
  }

  function parseHubPath(pathname) {
    var parts = (pathname || '/').replace(/^\/+|\/+$/g, '').split('/');
    if (!parts[0]) return null;
    // Pastas de deploy (/fleahub/, /fleahub-*-preview/, …) não são handles.
    // Sem isto, previews em subpasta disparam «Página não encontrada» no título.
    while (
      parts.length &&
      (parts[0].toLowerCase() === 'fleahub' ||
        /^fleahub[-_]/.test(parts[0].toLowerCase()))
    ) {
      parts.shift();
    }
    if (!parts[0]) return null;
    var handle = parts[0].toLowerCase();
    if (RESERVED_FIRST_SEGMENTS[handle]) return null;
    var section = parts[1] ? parts[1].toLowerCase() : '';
    if (section && ['live', 'shop', 'reviews'].indexOf(section) === -1) {
      return null;
    }
    return { handle: handle, section: section || 'profile' };
  }

  function setMeta(name, content, isProperty) {
    var sel = isProperty
      ? 'meta[property="' + name + '"]'
      : 'meta[name="' + name + '"]';
    var el = document.querySelector(sel);
    if (!el) {
      el = document.createElement('meta');
      if (isProperty) el.setAttribute('property', name);
      else el.setAttribute('name', name);
      document.head.appendChild(el);
    }
    el.setAttribute('content', content);
  }

  function setCanonical(href) {
    var el = document.querySelector('link[rel="canonical"]');
    if (!el) {
      el = document.createElement('link');
      el.setAttribute('rel', 'canonical');
      document.head.appendChild(el);
    }
    el.setAttribute('href', href);
  }

  function applyMeta(payload) {
    document.title = payload.title;
    setMeta('description', payload.description, false);
    setMeta('robots', payload.robots, false);
    setCanonical(payload.canonical);
    setMeta('og:title', payload.ogTitle, true);
    setMeta('og:description', payload.ogDescription, true);
    setMeta('og:image', payload.ogImage, true);
    setMeta('og:url', payload.ogUrl, true);
    setMeta('og:type', payload.ogType || 'website', true);
    setMeta('og:site_name', 'Fleaber', true);
    setMeta('twitter:card', 'summary_large_image', false);
    setMeta('twitter:title', payload.ogTitle, false);
    setMeta('twitter:description', payload.ogDescription, false);
    setMeta('twitter:image', payload.ogImage, false);
  }

  function notFoundMeta() {
    return {
      title: 'Página não encontrada · ' + CONFIG.appTitle,
      description: 'Este link não está disponível.',
      ogTitle: 'Página não encontrada · ' + CONFIG.appTitle,
      ogDescription: 'Este link não está disponível.',
      ogImage: CONFIG.defaultOgImage,
      canonical: CONFIG.canonicalHost,
      ogUrl: CONFIG.canonicalHost,
      robots: 'noindex,nofollow',
      ogType: 'website',
    };
  }

  function supabaseFetch(path, options) {
    var url = CONFIG.supabaseUrl.replace(/\/$/, '') + path;
    return fetch(url, Object.assign(
      {
        headers: {
          apikey: CONFIG.supabaseAnonKey,
          Authorization: 'Bearer ' + CONFIG.supabaseAnonKey,
          'Content-Type': 'application/json',
        },
      },
      options || {}
    )).then(function (r) {
      if (!r.ok) throw new Error('http_' + r.status);
      return r.json();
    });
  }

  function resolveHandle(handle) {
    return supabaseFetch('/rest/v1/rpc/batata_resolve_handle', {
      method: 'POST',
      body: JSON.stringify({ p_handle: handle }),
    });
  }

  function fetchProfile(handle) {
    return supabaseFetch(
      '/rest/v1/hub_profiles_public?handle=eq.' +
        encodeURIComponent(handle) +
        '&select=handle,full_name,photo_url,location,is_live',
      { method: 'GET' }
    );
  }

  function fetchPrimaryLive(sellerId) {
    return supabaseFetch(
      '/rest/v1/hub_lives_public?seller_id=eq.' +
        encodeURIComponent(sellerId) +
        '&select=title,status,is_active,mux_playback_id,mux_vod_playback_id,viewer_count' +
        '&order=is_active.desc,created_at.desc&limit=3',
      { method: 'GET' }
    );
  }

  function muxThumb(playbackId, isLive) {
    if (!playbackId) return null;
    var h = Math.round(600 * 16 / 9);
    var time = isLive ? 0 : 2;
    return (
      'https://image.mux.com/' +
      playbackId +
      '/thumbnail.jpg?width=600&height=' +
      h +
      '&fit_mode=crop&time=' +
      time
    );
  }

  function canonicalFor(handle, section) {
    var base = CONFIG.canonicalHost + '/' + handle;
    if (section === 'live') return base + '/live';
    if (section === 'shop') return base + '/shop';
    if (section === 'reviews') return base + '/reviews';
    return base;
  }

  function buildPayload(profile, live, section, indexable) {
    var handle = profile.handle;
    var name =
      (profile.full_name && profile.full_name.trim()) ||
      '@' + handle;
    var robots = indexable ? 'index,follow,max-image-preview:large' : 'noindex,nofollow';
    var canonical = canonicalFor(handle, section);
    var image =
      (profile.photo_url && profile.photo_url.indexOf('http') === 0
        ? profile.photo_url
        : null) || CONFIG.defaultOgImage;
    var desc = '';
    var title = '';
    var ogType = 'website';

    if (section === 'live') {
      var isLive =
        live &&
        (live.is_active === true ||
          (live.status || '').toLowerCase() === 'live');
      var liveTitle =
        live && live.title && live.title.trim ? live.title.trim() : '';
      var liveLabel = isLive ? 'AO VIVO' : 'Directo';
      title = liveLabel + ' · ' + name + ' · ' + CONFIG.appTitle;
      desc =
        (liveTitle ? liveTitle + ' · ' : '') +
        'directo de ' +
        name +
        ' na Fleaber.';
      var pid =
        live &&
        (isLive ? live.mux_playback_id : live.mux_vod_playback_id || live.mux_playback_id);
      var thumb = muxThumb(pid, isLive);
      if (thumb) image = thumb;
      if (isLive) ogType = 'video.other';
    } else if (section === 'shop') {
      title = 'Marketplace · @' + handle + ' · ' + CONFIG.appTitle;
      desc = 'Artigos de ' + name + ' no marketplace Fleaber.';
    } else if (section === 'reviews') {
      title = 'Avaliações · @' + handle + ' · ' + CONFIG.appTitle;
      desc = 'Opiniões de compradoras sobre ' + name + '.';
    } else {
      title = name + ' (@' + handle + ') · ' + CONFIG.appTitle;
      var loc = profile.location && profile.location.trim();
      desc = (loc ? loc + ' · ' : '') + 'Live shopping na Fleaber.';
    }

    return {
      title: title,
      description: desc,
      ogTitle: title,
      ogDescription: desc,
      ogImage: image,
      canonical: canonical,
      ogUrl: canonical,
      robots: robots,
      ogType: ogType,
    };
  }

  function run() {
    var route = parseHubPath(window.location.pathname);
    if (!route) return;

    var indexable = hostAllowsIndex(window.location.hostname);

    resolveHandle(route.handle)
      .then(function (resolved) {
        if (!resolved || !resolved.found || resolved.http_status !== 200) {
          applyMeta(notFoundMeta());
          return null;
        }
        if (!resolved.hub_published) {
          applyMeta(notFoundMeta());
          return null;
        }
        return fetchProfile(route.handle).then(function (rows) {
          if (!rows || !rows.length) {
            applyMeta(notFoundMeta());
            return;
          }
          var profile = rows[0];
          if (route.section === 'live') {
            return fetchPrimaryLive(resolved.profile_id).then(function (lives) {
              applyMeta(
                buildPayload(
                  profile,
                  lives && lives.length ? lives[0] : null,
                  route.section,
                  indexable
                )
              );
            });
          }
          applyMeta(buildPayload(profile, null, route.section, indexable));
        });
      })
      .catch(function () {
        applyMeta(notFoundMeta());
      });
  }

  run();
})();
