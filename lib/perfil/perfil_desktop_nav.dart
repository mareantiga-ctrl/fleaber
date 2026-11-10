import 'package:flutter/material.dart';

/// Identificadores do painel direito H11 (desktop shell).
enum PerfilDesktopPane {
  resumo,
  contaDefinicoes,
  definicoesLoja,
  favoritos,
  encomendas,
  resultadosLive,
  novoAnuncio,
  saldo,
  fleahub,
  descontos,
  ferias,
  referencias,
  equipa,
  convites,
  acessoColaborador,
  explorarFleahub,
  comoFunciona,
  comprarSeguro,
  venderFleaber,
  faq,
  contactos,
  infoLegal,
  sobre,
  admin,
  importadorAmazon,
}

extension PerfilDesktopPaneParsing on PerfilDesktopPane {
  /// Query `?secao=` (nome do enum) — painéis embutidos apenas.
  static PerfilDesktopPane? tryParse(String? raw) {
    final key = (raw ?? '').trim();
    if (key.isEmpty) return null;
    for (final pane in PerfilDesktopPane.values) {
      if (pane.name == key) {
        switch (pane) {
          case PerfilDesktopPane.novoAnuncio:
          case PerfilDesktopPane.explorarFleahub:
          case PerfilDesktopPane.admin:
          case PerfilDesktopPane.importadorAmazon:
          case PerfilDesktopPane.convites:
          case PerfilDesktopPane.definicoesLoja:
            return null;
          default:
            return pane;
        }
      }
    }
    return null;
  }

  bool get embedsInShell {
    switch (this) {
      case PerfilDesktopPane.novoAnuncio:
      case PerfilDesktopPane.explorarFleahub:
      case PerfilDesktopPane.admin:
      case PerfilDesktopPane.importadorAmazon:
      case PerfilDesktopPane.convites:
      case PerfilDesktopPane.definicoesLoja:
        return false;
      default:
        return true;
    }
  }
}

class PerfilNavEntry {
  const PerfilNavEntry({
    required this.pane,
    required this.title,
    required this.icon,
    this.subtitle,
    this.external = false,
  });

  final PerfilDesktopPane pane;
  final String title;
  final IconData icon;
  final String? subtitle;

  /// Sai do shell (push / Hub) em vez de embutir.
  final bool external;
}

abstract final class PerfilDesktopNavGroups {
  static const conta = 'Conta';
  static const compras = 'Compras e atividade';
  static const vendas = 'Vendas e FleaHub';
  static const ajuda = 'Ajuda e informação';
}
