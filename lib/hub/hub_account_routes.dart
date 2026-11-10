import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/perfil/perfil_desktop_nav.dart';

/// Destinos da Conta / H11 — fonte única para o FleaHub web.
///
/// No web, as páginas standalone antigas (`/minhasEncomendas`, `/wallet`, …)
/// abrem o shell Perfil com `?secao=`. Na app nativa mantêm-se as rotas
/// clássicas (lista / ecrãs full-screen).
///
/// Nomes de rota em string (sem `/index.dart`) para evitar ciclos de import
/// com `product_details` / `minhas_encomendas` / inbox.
abstract final class HubAccountRoutes {
  HubAccountRoutes._();

  static const String _perfilPath = '/perfil';
  static const String _rnMinhasEncomendas = 'MinhasEncomendas';
  static const String _rnListaConversas = 'ListaConversas';
  static const String _rnFavoritos = 'Favoritos';
  static const String _rnWallet = 'Wallet';
  static const String _rnContaDefinicoes = 'ContaDefinicoes';
  static const String _rnDescontos = 'DescontosConjuntos';
  static const String _rnFerias = 'ModoFerias';
  static const String _rnReferencias = 'GestaoReferencias';
  static const String _rnEquipa = 'SellerHelpers';
  static const String _rnResultadosLive = 'LiveSalesSessions';
  static const String _rnLegalDocument = 'LegalDocument';
  static const String _rnLegalHub = 'LegalHub';
  static const String _rnPerfil = 'Perfil';

  /// Path GoRouter do Perfil com secção H11.
  static String perfilPath(
    PerfilDesktopPane pane, {
    String? legalDoc,
    String? liveId,
    String? orderId,
  }) {
    if (pane == PerfilDesktopPane.resumo &&
        (legalDoc == null || legalDoc.isEmpty) &&
        (liveId == null || liveId.isEmpty) &&
        (orderId == null || orderId.isEmpty)) {
      return _perfilPath;
    }
    final params = <String, String>{};
    if (pane != PerfilDesktopPane.resumo) {
      params['secao'] = pane.name;
    }
    if (legalDoc != null && legalDoc.isNotEmpty) {
      params['doc'] = legalDoc;
    }
    if (liveId != null && liveId.isNotEmpty) {
      params['liveId'] = liveId;
    }
    final oid = (orderId ?? '').trim();
    if (oid.isNotEmpty) {
      params['orderId'] = oid;
    }
    if (params.isEmpty) return _perfilPath;
    return '$_perfilPath?${Uri(queryParameters: params).query}';
  }

  /// Deep link absoluto (emails / Hub web) para uma encomenda concreta.
  static String encomendaAbsoluteUrl(String orderId) {
    final path = perfilPath(
      PerfilDesktopPane.encomendas,
      orderId: orderId.trim(),
    );
    return 'https://fleaber.pt/fleahub/#$path';
  }

  /// Path in-app (GoRouter) para abrir a encomenda.
  static String encomendaPath(String orderId) => perfilPath(
        PerfilDesktopPane.encomendas,
        orderId: orderId.trim(),
      );

  /// Mapa rota antiga → painel H11 (só páginas absorvidas pelo Perfil).
  static const Map<String, PerfilDesktopPane> legacyPathToPane = {
    '/minhasEncomendas': PerfilDesktopPane.encomendas,
    '/favoritos': PerfilDesktopPane.favoritos,
    '/wallet': PerfilDesktopPane.saldo,
    '/contaDefinicoes': PerfilDesktopPane.contaDefinicoes,
    '/descontosConjuntos': PerfilDesktopPane.descontos,
    '/modoFerias': PerfilDesktopPane.ferias,
    '/gestaoReferencias': PerfilDesktopPane.referencias,
    '/equipaColaboradores': PerfilDesktopPane.equipa,
    '/operacoesLive': PerfilDesktopPane.resultadosLive,
    '/legalHub': PerfilDesktopPane.infoLegal,
  };

  /// Documentos `/legalDocument?kind=` → secção H11 (+ doc opcional).
  static ({PerfilDesktopPane pane, String? doc}) legalDocumentTarget(
    String? kind,
  ) {
    final k = (kind ?? '').trim().toLowerCase();
    switch (k) {
      case 'how':
        return (pane: PerfilDesktopPane.comoFunciona, doc: null);
      case 'buy-safe':
      case 'buy_safe':
      case 'comprar':
        return (pane: PerfilDesktopPane.comprarSeguro, doc: null);
      case 'sell':
      case 'vender':
        return (pane: PerfilDesktopPane.venderFleaber, doc: null);
      case 'faq':
        return (pane: PerfilDesktopPane.faq, doc: null);
      case 'contacts':
      case 'contactos':
        return (pane: PerfilDesktopPane.contactos, doc: null);
      case 'about':
        return (pane: PerfilDesktopPane.sobre, doc: null);
      case 'fleahub-account':
        return (pane: PerfilDesktopPane.fleahub, doc: null);
      default:
        // terms, privacy, cookies, data-deletion, …
        return (
          pane: PerfilDesktopPane.infoLegal,
          doc: k.isEmpty ? null : k,
        );
    }
  }

  static String legalDocumentPerfilPath(String? kind) {
    final t = legalDocumentTarget(kind);
    return perfilPath(t.pane, legalDoc: t.doc);
  }

  static PerfilDesktopPane? paneForLegacyPath(String path) {
    final p = path.split('?').first.trim();
    return legacyPathToPane[p];
  }

  /// Abrir secção da Conta (web → shell H11; nativo → rota standalone).
  static void openSection(
    BuildContext context,
    PerfilDesktopPane pane, {
    bool replace = false,
    String? legalDoc,
  }) {
    if (kIsWeb) {
      final loc = perfilPath(pane, legalDoc: legalDoc);
      if (replace) {
        context.go(loc);
      } else {
        context.push(loc);
      }
      return;
    }
    _openNativeStandalone(context, pane, replace: replace, legalDoc: legalDoc);
  }

  static void openEncomendas(
    BuildContext context, {
    bool replace = false,
    String? orderId,
  }) {
    final oid = (orderId ?? '').trim();
    if (oid.isEmpty) {
      openSection(context, PerfilDesktopPane.encomendas, replace: replace);
      return;
    }
    if (kIsWeb) {
      final loc = perfilPath(PerfilDesktopPane.encomendas, orderId: oid);
      if (replace) {
        context.go(loc);
      } else {
        context.push(loc);
      }
      return;
    }
    final q = <String, String>{'orderId': oid};
    if (replace) {
      context.goNamed(_rnMinhasEncomendas, queryParameters: q);
    } else {
      context.pushNamed(_rnMinhasEncomendas, queryParameters: q);
    }
  }

  /// Mensagens (H10) — lista de conversas. Uniformiza Hub + Conta + sino.
  static void openMensagens(BuildContext context, {bool replace = false}) {
    _openListaConversas(context, replace: replace, initialTab: null);
  }

  /// Aba Notificações dentro de Mensagens (H10).
  static void openNotificacoes(BuildContext context, {bool replace = false}) {
    _openListaConversas(
      context,
      replace: replace,
      initialTab: 'notificacoes',
    );
  }

  static void _openListaConversas(
    BuildContext context, {
    required bool replace,
    String? initialTab,
  }) {
    final tab = (initialTab ?? '').trim();
    final q = <String, String>{
      if (tab.isNotEmpty) 'initialTab': tab,
    };
    if (replace) {
      context.goNamed(_rnListaConversas, queryParameters: q);
    } else {
      context.pushNamed(_rnListaConversas, queryParameters: q);
    }
  }

  static void openFavoritos(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.favoritos, replace: replace);

  static void openSaldo(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.saldo, replace: replace);

  static void openContaDefinicoes(
    BuildContext context, {
    bool replace = false,
  }) =>
      openSection(context, PerfilDesktopPane.contaDefinicoes, replace: replace);

  static void openResultadosLive(
    BuildContext context, {
    bool replace = false,
  }) =>
      openSection(context, PerfilDesktopPane.resultadosLive, replace: replace);

  static void openDescontos(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.descontos, replace: replace);

  static void openFerias(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.ferias, replace: replace);

  static void openReferencias(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.referencias, replace: replace);

  static void openEquipa(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.equipa, replace: replace);

  static void openResumo(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.resumo, replace: replace);

  static void openComoFunciona(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.comoFunciona, replace: replace);

  static void openComprarSeguro(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.comprarSeguro, replace: replace);

  static void openVenderFleaber(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.venderFleaber, replace: replace);

  static void openFaq(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.faq, replace: replace);

  static void openContactos(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.contactos, replace: replace);

  static void openInfoLegal(
    BuildContext context, {
    bool replace = false,
    String? doc,
  }) =>
      openSection(
        context,
        PerfilDesktopPane.infoLegal,
        replace: replace,
        legalDoc: doc,
      );

  static void openSobre(BuildContext context, {bool replace = false}) =>
      openSection(context, PerfilDesktopPane.sobre, replace: replace);

  static void openLegalDocument(
    BuildContext context,
    String? kind, {
    bool replace = false,
  }) {
    final t = legalDocumentTarget(kind);
    openSection(context, t.pane, replace: replace, legalDoc: t.doc);
  }

  /// Excepções documentadas (não absorvidas pelo painel H11).
  ///
  /// - **Mensagens / Notificações** (`ListaConversas`) — H10, dono C1.
  /// - **Detalhe de sessão live** (`/resultadosLive?…`) — ecrã de detalhe;
  ///   a lista fica em `resultadosLive` no Perfil.
  /// - **Saco / reservas activas** — abre live do vendedor ou sheet Hub;
  ///   não é a lista de encomendas.
  /// - **Novo anúncio / Explorar FleaHub / Admin** — saem do shell (external).
  /// - **Links legais login/registo** (`FleaberLegalLinksRow` → URLs públicas).
  static const documentedExceptions = <String>[
    'ListaConversas / notificações (H10 C1)',
    'LiveSalesSessionDetail (detalhe; lista → secao=resultadosLive)',
    'Saco Hub → live do vendedor (não MinhasEncomendas)',
    'Novo anúncio, Explorar FleaHub, Admin (external ao shell)',
    'FleaberLegalLinksRow → URLs públicas (fora Conta autenticada)',
  ];

  /// Widget de redirect para rotas legacy no web (GoRouter builder).
  static Widget webLegacyRedirect(
    PerfilDesktopPane pane, {
    String? legalDoc,
    String? orderId,
  }) =>
      _HubWebLegacyAccountRedirect(
        pane: pane,
        legalDoc: legalDoc,
        orderId: orderId,
      );

  /// Detalhe de sessão live → painel H11 (`?secao=resultadosLive&liveId=`).
  static Widget webLiveDetailRedirect(String liveId) =>
      _HubWebLegacyAccountRedirect(
        pane: PerfilDesktopPane.resultadosLive,
        liveId: liveId,
      );

  static void _openNativeStandalone(
    BuildContext context,
    PerfilDesktopPane pane, {
    required bool replace,
    String? legalDoc,
  }) {
    void goNamed(String name, {Map<String, String>? query}) {
      if (replace) {
        context.goNamed(name, queryParameters: query ?? const {});
      } else {
        context.pushNamed(name, queryParameters: query ?? const {});
      }
    }

    switch (pane) {
      case PerfilDesktopPane.encomendas:
        goNamed(_rnMinhasEncomendas);
      case PerfilDesktopPane.favoritos:
        goNamed(_rnFavoritos);
      case PerfilDesktopPane.saldo:
        goNamed(_rnWallet);
      case PerfilDesktopPane.contaDefinicoes:
        goNamed(_rnContaDefinicoes);
      case PerfilDesktopPane.descontos:
        goNamed(_rnDescontos);
      case PerfilDesktopPane.ferias:
        goNamed(_rnFerias);
      case PerfilDesktopPane.referencias:
        goNamed(_rnReferencias);
      case PerfilDesktopPane.equipa:
        goNamed(_rnEquipa);
      case PerfilDesktopPane.resultadosLive:
        goNamed(_rnResultadosLive);
      case PerfilDesktopPane.comoFunciona:
        goNamed(_rnLegalDocument, query: {'kind': 'how'});
      case PerfilDesktopPane.comprarSeguro:
        goNamed(_rnLegalDocument, query: {'kind': 'buy-safe'});
      case PerfilDesktopPane.venderFleaber:
        goNamed(_rnLegalDocument, query: {'kind': 'sell'});
      case PerfilDesktopPane.faq:
        goNamed(_rnLegalDocument, query: {'kind': 'faq'});
      case PerfilDesktopPane.contactos:
        goNamed(_rnLegalDocument, query: {'kind': 'contacts'});
      case PerfilDesktopPane.sobre:
        goNamed(_rnLegalDocument, query: {'kind': 'about'});
      case PerfilDesktopPane.infoLegal:
        if (legalDoc != null && legalDoc.isNotEmpty) {
          goNamed(_rnLegalDocument, query: {'kind': legalDoc});
        } else {
          goNamed(_rnLegalHub);
        }
      case PerfilDesktopPane.resumo:
      default:
        goNamed(_rnPerfil);
    }
  }
}

class _HubWebLegacyAccountRedirect extends StatefulWidget {
  const _HubWebLegacyAccountRedirect({
    required this.pane,
    this.legalDoc,
    this.liveId,
    this.orderId,
  });

  final PerfilDesktopPane pane;
  final String? legalDoc;
  final String? liveId;
  final String? orderId;

  @override
  State<_HubWebLegacyAccountRedirect> createState() =>
      _HubWebLegacyAccountRedirectState();
}

class _HubWebLegacyAccountRedirectState
    extends State<_HubWebLegacyAccountRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fromUri = GoRouterState.of(context).uri.queryParameters['orderId'];
      final oid = (widget.orderId ?? fromUri ?? '').trim();
      context.go(
        HubAccountRoutes.perfilPath(
          widget.pane,
          legalDoc: widget.legalDoc,
          liveId: widget.liveId,
          orderId: oid.isEmpty ? null : oid,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF007782)),
      ),
    );
  }
}
