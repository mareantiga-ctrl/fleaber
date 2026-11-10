import 'hub_seller_copy.dart';

/// Estado Hub seller na app (handle + publicação).
enum HubSellerPhase {
  /// Sem `profiles.handle`.
  noHandle,

  /// `handle_suggested` preenchido, ainda não claimado.
  suggestedOnly,

  /// Handle claimado, `hub_published=false`.
  handleClaimedHidden,

  /// Handle + vitrine publicada.
  handleClaimedPublished,
}

class HubSellerStatus {
  const HubSellerStatus({
    required this.profileId,
    required this.fullName,
    required this.phoneVerified,
    required this.canClaim,
    required this.canPublish,
    this.handle,
    this.handleSuggested,
    this.hubPublished = false,
    this.publishBlockReason,
  });

  final String profileId;
  final String? fullName;
  final String? handle;
  final String? handleSuggested;
  final bool hubPublished;
  final bool phoneVerified;
  final bool canClaim;
  final bool canPublish;
  final String? publishBlockReason;

  HubSellerPhase get phase {
    if (handle != null && handle!.trim().isNotEmpty) {
      return hubPublished
          ? HubSellerPhase.handleClaimedPublished
          : HubSellerPhase.handleClaimedHidden;
    }
    if (handleSuggested != null && handleSuggested!.trim().isNotEmpty) {
      return HubSellerPhase.suggestedOnly;
    }
    return HubSellerPhase.noHandle;
  }

  bool get hasPublicHub => phase == HubSellerPhase.handleClaimedPublished;

  /// Linha compacta no Perfil Seller — marca FleaHub.
  String get profilePublicLineLabel {
    final h = handle?.trim();
    if (h != null && h.isNotEmpty) return HubSellerCopy.profileLineManage;
    return HubSellerCopy.profileLineCreate;
  }

  bool get hasClaimedFleaHub {
    final h = handle?.trim();
    return h != null && h.isNotEmpty;
  }

  String? get effectiveHandlePreview {
    final h = handle?.trim();
    if (h != null && h.isNotEmpty) return h;
    final s = handleSuggested?.trim();
    if (s != null && s.isNotEmpty) return s;
    return null;
  }

  factory HubSellerStatus.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    return HubSellerStatus(
      profileId: id,
      fullName: map['full_name']?.toString(),
      handle: map['handle']?.toString(),
      handleSuggested: map['handle_suggested']?.toString(),
      hubPublished: map['hub_published'] == true,
      phoneVerified: map['phone_verified_at'] != null,
      canClaim: map['phone_verified_at'] != null &&
          (map['handle'] == null || map['handle'].toString().trim().isEmpty),
      canPublish: _deriveCanPublish(map),
      publishBlockReason: _derivePublishBlock(map),
    );
  }

  static bool _deriveCanPublish(Map<String, dynamic> map) {
    if (map['phone_verified_at'] == null) return false;
    final handle = map['handle']?.toString().trim() ?? '';
    if (handle.isEmpty) return false;
    return true;
  }

  static String? _derivePublishBlock(Map<String, dynamic> map) {
    if (map['phone_verified_at'] == null) {
      return 'Verifica o telemóvel para criares o teu FleaHub.';
    }
    final handle = map['handle']?.toString().trim() ?? '';
    if (handle.isEmpty) {
      return 'Escolhe primeiro o endereço do teu FleaHub.';
    }
    return null;
  }

  HubSellerStatus copyWith({
    String? handle,
    String? handleSuggested,
    bool? hubPublished,
  }) {
    return HubSellerStatus.fromMap({
      'id': profileId,
      'full_name': fullName,
      'handle': handle ?? this.handle,
      'handle_suggested': handleSuggested ?? this.handleSuggested,
      'hub_published': hubPublished ?? this.hubPublished,
      'phone_verified_at': phoneVerified ? '1970-01-01' : null,
    });
  }
}

class HubSellerActionResult {
  const HubSellerActionResult({
    required this.ok,
    this.handle,
    this.hubPublished,
    this.errorCode,
    this.errorMessage,
    this.validationReasons = const [],
  });

  final bool ok;
  final String? handle;
  final bool? hubPublished;
  final String? errorCode;
  final String? errorMessage;
  final List<String> validationReasons;

  factory HubSellerActionResult.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const HubSellerActionResult(
        ok: false,
        errorCode: 'invalid_response',
        errorMessage: 'Resposta inválida.',
      );
    }
    final map = Map<String, dynamic>.from(raw);
    final ok = map['ok'] == true || map['ok']?.toString() == 'true';
    if (!ok) {
      final validation = map['validation'];
      final reasons = <String>[];
      if (validation is Map) {
        final r = validation['reasons'];
        if (r is List) {
          for (final e in r) {
            reasons.add(e.toString());
          }
        }
      }
      return HubSellerActionResult(
        ok: false,
        errorCode: map['error']?.toString() ?? 'rpc_error',
        errorMessage: HubSellerErrorMessages.fromCode(map['error']?.toString()),
        validationReasons: reasons,
      );
    }
    return HubSellerActionResult(
      ok: true,
      handle: map['handle']?.toString(),
      hubPublished: map['hub_published'] as bool?,
    );
  }

  factory HubSellerActionResult.fromException(Object e) {
    final code = HubSellerErrorMessages.codeFromException(e);
    return HubSellerActionResult(
      ok: false,
      errorCode: code,
      errorMessage: HubSellerErrorMessages.fromCode(code),
    );
  }
}

abstract final class HubSellerErrorMessages {
  static String codeFromException(Object e) {
    final s = e.toString().toLowerCase();
    for (final code in [
      'phone_not_verified',
      'handle_already_set',
      'handle_not_set',
      'handle_change_cooldown',
      'handle_max_changes_90d',
      'handle_rate_limit',
      'seller_not_ready',
      'handle_required',
      'not_authenticated',
    ]) {
      if (s.contains(code)) return code;
    }
    return 'unknown';
  }

  static String fromCode(String? code, {List<String> validationReasons = const []}) {
    if (validationReasons.isNotEmpty) {
      return _validationMessage(validationReasons);
    }
    return switch (code) {
      'phone_not_verified' =>
        'Verifica o telemóvel nas definições para criares o teu FleaHub.',
      'handle_already_set' => 'Já tens um FleaHub. Usa «Personalizar endereço».',
      'handle_not_set' => 'Escolhe primeiro o endereço do teu FleaHub.',
      'handle_change_cooldown' =>
        'Aguarda 7 dias desde a última alteração de endereço.',
      'handle_max_changes_90d' =>
        'Limite de 2 alterações de endereço a cada 90 dias.',
      'handle_rate_limit' => 'Demasiadas tentativas. Tenta mais tarde.',
      'seller_not_ready' =>
        'Precisas de telemóvel verificado, email confirmado e pelo menos 1 produto ou live.',
      'handle_required' => 'Escolhe um endereço antes de activar o FleaHub.',
      'handle_invalid' => 'Endereço indisponível ou inválido.',
      'not_authenticated' => 'Inicia sessão.',
      _ => 'Não foi possível concluir. Tenta outra vez.',
    };
  }

  static String _validationMessage(List<String> reasons) {
    if (reasons.contains('reserved') || reasons.contains('impersonation')) {
      return 'Este endereço está reservado. Escolhe outro.';
    }
    if (reasons.contains('taken')) {
      return 'Este endereço já está a ser usado.';
    }
    if (reasons.contains('too_short')) {
      return 'Mínimo 3 caracteres.';
    }
    if (reasons.contains('too_long')) {
      return 'Máximo 30 caracteres.';
    }
    if (reasons.contains('invalid_format') || reasons.contains('numeric_only')) {
      return 'Usa letras, números e hífens (ex.: maria-silva).';
    }
    return 'Endereço inválido.';
  }
}
