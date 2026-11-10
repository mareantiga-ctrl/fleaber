/// Beat de script Live Director — momento → acção → actor.
library;

enum DirectorMomentType {
  approx,
  window,
  afterEvent,
  afterSellerSilent,
  afterRaffleActive,
  afterHumanPurchase,
  manual,
  immediateOnRun,
}

enum DirectorActionType {
  enter,
  exit,
  like,
  likeBurst,
  chat,
  reserve,
  purchase,
  raffleJoin,
  silence,
  wait,
}

enum DirectorPaymentMode { none, simulated, manual, real }

class DirectorBeat {
  const DirectorBeat({
    required this.beatId,
    required this.momentType,
    required this.action,
    this.windowStartSec,
    this.windowEndSec,
    this.approxSec,
    this.afterEvent,
    this.afterSilentSec = 120,
    this.actorTag,
    this.actorPersona,
    this.liveItemId,
    this.productRef,
    this.qty = 1,
    this.messageText,
    this.phraseTag,
    this.enabled = true,
    this.fixedTime = false,
    this.maxSlipSec = 600,
    this.confidence = 1.0,
    this.affectStock = false,
    this.paymentMode = DirectorPaymentMode.none,
    this.notes,
    this.likeBurstMax = 4,
    this.likeBurstWindowSec = 60,
  });

  final String beatId;
  final DirectorMomentType momentType;
  final DirectorActionType action;
  final int? windowStartSec;
  final int? windowEndSec;
  final int? approxSec;
  final String? afterEvent;
  final int afterSilentSec;
  final String? actorTag;
  final String? actorPersona;
  final String? liveItemId;
  final String? productRef;
  final int qty;
  final String? messageText;
  final String? phraseTag;
  final bool enabled;
  final bool fixedTime;
  final int maxSlipSec;
  final double confidence;
  final bool affectStock;
  final DirectorPaymentMode paymentMode;
  final String? notes;
  final int likeBurstMax;
  final int likeBurstWindowSec;

  bool get isCommercial =>
      action == DirectorActionType.reserve ||
      action == DirectorActionType.purchase;

  Map<String, dynamic> toJson() => {
        'beat_id': beatId,
        'moment_type': momentType.name,
        'action': action.name,
        if (windowStartSec != null) 'window_start_sec': windowStartSec,
        if (windowEndSec != null) 'window_end_sec': windowEndSec,
        if (approxSec != null) 'approx_sec': approxSec,
        if (afterEvent != null) 'after_event': afterEvent,
        'after_silent_sec': afterSilentSec,
        if (actorTag != null) 'actor_tag': actorTag,
        if (actorPersona != null) 'actor_persona': actorPersona,
        if (liveItemId != null) 'live_item_id': liveItemId,
        if (productRef != null) 'product_ref': productRef,
        'qty': qty,
        if (messageText != null) 'message_text': messageText,
        if (phraseTag != null) 'phrase_tag': phraseTag,
        'enabled': enabled,
        'fixed_time': fixedTime,
        'max_slip_sec': maxSlipSec,
        'confidence': confidence,
        'affect_stock': affectStock,
        'payment_mode': paymentMode.name,
        if (notes != null) 'notes': notes,
        'like_burst_max': likeBurstMax,
        'like_burst_window_sec': likeBurstWindowSec,
      };

  factory DirectorBeat.fromJson(Map<String, dynamic> json) {
    return DirectorBeat(
      beatId: json['beat_id']?.toString() ?? '',
      momentType: DirectorMomentType.values.firstWhere(
        (e) => e.name == json['moment_type'],
        orElse: () => DirectorMomentType.approx,
      ),
      action: DirectorActionType.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => DirectorActionType.wait,
      ),
      windowStartSec: (json['window_start_sec'] as num?)?.toInt(),
      windowEndSec: (json['window_end_sec'] as num?)?.toInt(),
      approxSec: (json['approx_sec'] as num?)?.toInt(),
      afterEvent: json['after_event']?.toString(),
      afterSilentSec: (json['after_silent_sec'] as num?)?.toInt() ?? 120,
      actorTag: json['actor_tag']?.toString(),
      actorPersona: json['actor_persona']?.toString(),
      liveItemId: json['live_item_id']?.toString(),
      productRef: json['product_ref']?.toString(),
      qty: (json['qty'] as num?)?.toInt() ?? 1,
      messageText: json['message_text']?.toString(),
      phraseTag: json['phrase_tag']?.toString(),
      enabled: json['enabled'] != false,
      fixedTime: json['fixed_time'] == true,
      maxSlipSec: (json['max_slip_sec'] as num?)?.toInt() ?? 600,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      affectStock: json['affect_stock'] == true,
      paymentMode: DirectorPaymentMode.values.firstWhere(
        (e) => e.name == json['payment_mode'],
        orElse: () => DirectorPaymentMode.none,
      ),
      notes: json['notes']?.toString(),
      likeBurstMax: (json['like_burst_max'] as num?)?.toInt() ?? 4,
      likeBurstWindowSec: (json['like_burst_window_sec'] as num?)?.toInt() ?? 60,
    );
  }

  DirectorBeat copyWith({bool? enabled}) => DirectorBeat(
        beatId: beatId,
        momentType: momentType,
        action: action,
        windowStartSec: windowStartSec,
        windowEndSec: windowEndSec,
        approxSec: approxSec,
        afterEvent: afterEvent,
        afterSilentSec: afterSilentSec,
        actorTag: actorTag,
        actorPersona: actorPersona,
        liveItemId: liveItemId,
        productRef: productRef,
        qty: qty,
        messageText: messageText,
        phraseTag: phraseTag,
        enabled: enabled ?? this.enabled,
        fixedTime: fixedTime,
        maxSlipSec: maxSlipSec,
        confidence: confidence,
        affectStock: affectStock,
        paymentMode: paymentMode,
        notes: notes,
        likeBurstMax: likeBurstMax,
        likeBurstWindowSec: likeBurstWindowSec,
      );
}
