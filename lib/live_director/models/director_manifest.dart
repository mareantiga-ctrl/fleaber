import 'dart:convert';

import 'director_beat.dart';
import 'director_script.dart';

class DirectorManifest {
  const DirectorManifest({
    required this.scriptId,
    required this.scriptName,
    required this.version,
    required this.checksum,
    required this.mode,
    required this.liveId,
    required this.sellerId,
    required this.operatorId,
    required this.operatorLabel,
    required this.targetProducts,
    required this.castPool,
    required this.beats,
    required this.policy,
    required this.lockedAt,
    this.validationToken,
    this.confirmations = const {},
  });

  final String scriptId;
  final String scriptName;
  final int version;
  final String checksum;
  final DirectorScriptMode mode;
  final String liveId;
  final String sellerId;
  final String operatorId;
  final String operatorLabel;
  final List<DirectorTargetProduct> targetProducts;
  final List<DirectorCastMember> castPool;
  final List<DirectorBeat> beats;
  final DirectorScriptPolicy policy;
  final DateTime lockedAt;
  final String? validationToken;
  final Map<String, bool> confirmations;

  Map<String, dynamic> toJson() => {
        'script_id': scriptId,
        'script_name': scriptName,
        'version': version,
        'checksum': checksum,
        'mode': mode.name == 'productionControlled'
            ? 'production_controlled'
            : mode.name,
        'live_id': liveId,
        'seller_id': sellerId,
        'operator_id': operatorId,
        'operator_label': operatorLabel,
        'target_products':
            targetProducts.map((e) => e.toJson()).toList(growable: false),
        'cast_pool': castPool.map((e) => e.toJson()).toList(growable: false),
        'beats': beats.map((e) => e.toJson()).toList(growable: false),
        'policy': policy.toJson(),
        'locked_at': lockedAt.toUtc().toIso8601String(),
        if (validationToken != null) 'validation_token': validationToken,
        'confirmations': confirmations,
      };

  factory DirectorManifest.fromJson(Map<String, dynamic> json) {
    final script = DirectorScript(
      name: json['script_name']?.toString() ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      mode: DirectorScript.parseMode(json['mode']?.toString()),
      liveId: json['live_id']?.toString(),
      sellerId: json['seller_id']?.toString(),
      operatorId: json['operator_id']?.toString(),
      operatorLabel: json['operator_label']?.toString(),
      targetProducts: (json['target_products'] as List?)
              ?.whereType<Map>()
              .map((e) => DirectorTargetProduct.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList() ??
          const [],
      castPool: (json['cast_pool'] as List?)
              ?.whereType<Map>()
              .map((e) => DirectorCastMember.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList() ??
          const [],
      beats: (json['beats'] as List?)
              ?.whereType<Map>()
              .map((e) =>
                  DirectorBeat.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      policy: DirectorScriptPolicy.fromJson(
        json['policy'] is Map
            ? Map<String, dynamic>.from(json['policy'] as Map)
            : null,
      ),
      checksum: json['checksum']?.toString(),
    );
    return DirectorManifest(
      scriptId: json['script_id']?.toString() ?? '',
      scriptName: script.name,
      version: script.version,
      checksum: json['checksum']?.toString() ?? '',
      mode: script.mode,
      liveId: json['live_id']?.toString() ?? '',
      sellerId: json['seller_id']?.toString() ?? '',
      operatorId: json['operator_id']?.toString() ?? '',
      operatorLabel: json['operator_label']?.toString() ?? '',
      targetProducts: script.targetProducts,
      castPool: script.castPool,
      beats: script.beats.where((b) => b.enabled).toList(),
      policy: script.policy,
      lockedAt: DateTime.tryParse(json['locked_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      validationToken: json['validation_token']?.toString(),
      confirmations: json['confirmations'] is Map
          ? Map<String, bool>.from(
              (json['confirmations'] as Map).map(
                (k, v) => MapEntry(k.toString(), v == true),
              ),
            )
          : const {},
    );
  }

  static String computeChecksum(DirectorScript script) {
    final canonical = jsonEncode({
      'name': script.name,
      'version': script.version,
      'mode': script.mode.name,
      'live_id': script.liveId,
      'beats': script.beats.map((e) => e.toJson()).toList(),
      'policy': script.policy.toJson(),
      'target_products':
          script.targetProducts.map((e) => e.toJson()).toList(),
    });
    // Checksum estável para manifest (não criptográfico; suficiente para versioning).
    return utf8
        .encode(canonical)
        .fold<int>(0, (h, b) => (h * 31 + b) & 0xFFFFFFFF)
        .toRadixString(16)
        .padLeft(8, '0');
  }
}
