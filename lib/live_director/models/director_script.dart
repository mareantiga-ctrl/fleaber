import 'director_beat.dart';

enum DirectorScriptMode { qa, demo, productionControlled }

class DirectorTargetProduct {
  const DirectorTargetProduct({
    required this.liveItemId,
    this.refCode,
    this.title,
    this.allowReserve = true,
    this.allowPurchase = true,
  });

  final String liveItemId;
  final String? refCode;
  final String? title;
  final bool allowReserve;
  final bool allowPurchase;

  Map<String, dynamic> toJson() => {
        'live_item_id': liveItemId,
        if (refCode != null) 'ref_code': refCode,
        if (title != null) 'title': title,
        'allow_reserve': allowReserve,
        'allow_purchase': allowPurchase,
      };

  factory DirectorTargetProduct.fromJson(Map<String, dynamic> json) =>
      DirectorTargetProduct(
        liveItemId: json['live_item_id']?.toString() ?? '',
        refCode: json['ref_code']?.toString(),
        title: json['title']?.toString(),
        allowReserve: json['allow_reserve'] != false,
        allowPurchase: json['allow_purchase'] != false,
      );
}

class DirectorCastMember {
  const DirectorCastMember({
    required this.internalTag,
    required this.profileId,
    required this.displayName,
    this.persona = 'observer',
    this.email,
  });

  final String internalTag;
  final String profileId;
  final String displayName;
  final String persona;
  final String? email;

  Map<String, dynamic> toJson() => {
        'internal_tag': internalTag,
        'profile_id': profileId,
        'display_name': displayName,
        'persona': persona,
        if (email != null) 'email': email,
      };

  factory DirectorCastMember.fromJson(Map<String, dynamic> json) =>
      DirectorCastMember(
        internalTag: json['internal_tag']?.toString() ?? '',
        profileId: json['profile_id']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
        persona: json['persona']?.toString() ?? 'observer',
        email: json['email']?.toString(),
      );
}

class DirectorScriptPolicy {
  const DirectorScriptPolicy({
    this.maxPurchasesPerLive = 2,
    this.maxReservationsPerLive = 5,
    this.maxUnitsPerBotPerProduct = 2,
    this.maxMessagesPerHour = 14,
    this.maxLikesPerHour = 12,
    this.minSilenceBetweenBeatsSec = 45,
    this.allowRealPayments = false,
    this.jitterSec = 30,
    this.notesTagPrefix = 'DIRECTOR',
  });

  final int maxPurchasesPerLive;
  final int maxReservationsPerLive;
  final int maxUnitsPerBotPerProduct;
  final int maxMessagesPerHour;
  final int maxLikesPerHour;
  final int minSilenceBetweenBeatsSec;
  final bool allowRealPayments;
  final int jitterSec;
  final String notesTagPrefix;

  Map<String, dynamic> toJson() => {
        'max_purchases_per_live': maxPurchasesPerLive,
        'max_reservations_per_live': maxReservationsPerLive,
        'max_units_per_bot_per_product': maxUnitsPerBotPerProduct,
        'max_messages_per_hour': maxMessagesPerHour,
        'max_likes_per_hour': maxLikesPerHour,
        'min_silence_between_beats_sec': minSilenceBetweenBeatsSec,
        'allow_real_payments': allowRealPayments,
        'jitter_sec': jitterSec,
        'notes_tag_prefix': notesTagPrefix,
      };

  factory DirectorScriptPolicy.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const DirectorScriptPolicy();
    return DirectorScriptPolicy(
      maxPurchasesPerLive:
          (json['max_purchases_per_live'] as num?)?.toInt() ?? 2,
      maxReservationsPerLive:
          (json['max_reservations_per_live'] as num?)?.toInt() ?? 5,
      maxUnitsPerBotPerProduct:
          (json['max_units_per_bot_per_product'] as num?)?.toInt() ?? 2,
      maxMessagesPerHour: (json['max_messages_per_hour'] as num?)?.toInt() ?? 14,
      maxLikesPerHour: (json['max_likes_per_hour'] as num?)?.toInt() ?? 12,
      minSilenceBetweenBeatsSec:
          (json['min_silence_between_beats_sec'] as num?)?.toInt() ?? 45,
      allowRealPayments: json['allow_real_payments'] == true,
      jitterSec: (json['jitter_sec'] as num?)?.toInt() ?? 30,
      notesTagPrefix: json['notes_tag_prefix']?.toString() ?? 'DIRECTOR',
    );
  }
}

class DirectorScript {
  const DirectorScript({
    this.id,
    required this.name,
    this.version = 1,
    this.description,
    this.mode = DirectorScriptMode.demo,
    this.liveId,
    this.sellerId,
    this.operatorId,
    this.operatorLabel,
    this.targetProducts = const [],
    this.castPool = const [],
    this.beats = const [],
    this.policy = const DirectorScriptPolicy(),
    this.checksum,
    this.status = 'draft',
    this.parentScriptId,
    this.tags = const [],
  });

  final String? id;
  final String name;
  final int version;
  final String? description;
  final DirectorScriptMode mode;
  final String? liveId;
  final String? sellerId;
  final String? operatorId;
  final String? operatorLabel;
  final List<DirectorTargetProduct> targetProducts;
  final List<DirectorCastMember> castPool;
  final List<DirectorBeat> beats;
  final DirectorScriptPolicy policy;
  final String? checksum;
  final String status;
  final String? parentScriptId;
  final List<String> tags;

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'name': name,
        'version': version,
        if (description != null) 'description': description,
        'mode': mode.name == 'productionControlled'
            ? 'production_controlled'
            : mode.name,
        if (liveId != null) 'live_id': liveId,
        if (sellerId != null) 'seller_id': sellerId,
        if (operatorId != null) 'operator_id': operatorId,
        if (operatorLabel != null) 'operator_label': operatorLabel,
        'target_products':
            targetProducts.map((e) => e.toJson()).toList(growable: false),
        'cast_pool': castPool.map((e) => e.toJson()).toList(growable: false),
        'beats': beats.map((e) => e.toJson()).toList(growable: false),
        'policy': policy.toJson(),
        if (checksum != null) 'checksum': checksum,
        'status': status,
        if (parentScriptId != null) 'parent_script_id': parentScriptId,
        'tags': tags,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory DirectorScript.fromRow(Map<String, dynamic> row) {
    final products = row['target_products'];
    final cast = row['cast_pool'];
    final beatsRaw = row['beats'];
    return DirectorScript(
      id: row['id']?.toString(),
      name: row['name']?.toString() ?? '',
      version: (row['version'] as num?)?.toInt() ?? 1,
      description: row['description']?.toString(),
      mode: parseMode(row['mode']?.toString()),
      liveId: row['live_id']?.toString(),
      sellerId: row['seller_id']?.toString(),
      operatorId: row['operator_id']?.toString(),
      operatorLabel: row['operator_label']?.toString(),
      targetProducts: products is List
          ? products
              .whereType<Map>()
              .map((e) => DirectorTargetProduct.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
      castPool: cast is List
          ? cast
              .whereType<Map>()
              .map((e) => DirectorCastMember.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
      beats: beatsRaw is List
          ? beatsRaw
              .whereType<Map>()
              .map((e) =>
                  DirectorBeat.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      policy: DirectorScriptPolicy.fromJson(
        row['policy'] is Map
            ? Map<String, dynamic>.from(row['policy'] as Map)
            : null,
      ),
      checksum: row['checksum']?.toString(),
      status: row['status']?.toString() ?? 'draft',
      parentScriptId: row['parent_script_id']?.toString(),
      tags: row['tags'] is List
          ? (row['tags'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }

  static DirectorScriptMode parseMode(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'qa':
        return DirectorScriptMode.qa;
      case 'production_controlled':
        return DirectorScriptMode.productionControlled;
      default:
        return DirectorScriptMode.demo;
    }
  }
}
