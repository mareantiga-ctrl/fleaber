import '/backend/supabase/supabase.dart';

class DpdTrackEvent {
  const DpdTrackEvent({
    required this.description,
    this.at,
    this.code,
    this.location,
  });

  final String description;
  final String? at;
  final String? code;
  final String? location;

  factory DpdTrackEvent.fromJson(Map<String, dynamic> m) {
    return DpdTrackEvent(
      description: (m['description'] ?? '').toString().trim().isEmpty
          ? 'Atualização DPD'
          : (m['description'] ?? '').toString().trim(),
      at: (m['at']?.toString().trim().isEmpty ?? true)
          ? null
          : m['at']?.toString().trim(),
      code: (m['code']?.toString().trim().isEmpty ?? true)
          ? null
          : m['code']?.toString().trim(),
      location: (m['location']?.toString().trim().isEmpty ?? true)
          ? null
          : m['location']?.toString().trim(),
    );
  }
}

class DpdTrackingResult {
  const DpdTrackingResult({
    required this.ok,
    required this.status,
    required this.events,
    this.guide,
    this.message,
  });

  final bool ok;
  final String status;
  final List<DpdTrackEvent> events;
  final String? guide;
  final String? message;

  bool get isEmptyEvents => status == 'empty' || events.isEmpty;
}

class DpdTrackingService {
  DpdTrackingService._();

  static Future<DpdTrackingResult> fetchForOrder({
    required String orderId,
    String countrycode = 'PT',
    String? guideOverride,
  }) async {
    final body = <String, dynamic>{
      'order_id': orderId,
      'countrycode': countrycode,
      if (guideOverride != null && guideOverride.trim().isNotEmpty)
        'guide': guideOverride.trim(),
    };
    final res = await SupaFlow.client.functions.invoke(
      'dpd-tracking',
      body: body,
    );
    final data = res.data;
    if (data is! Map) {
      throw Exception('Não foi possível obter o seguimento DPD.');
    }
    final map = Map<String, dynamic>.from(data);
    final rawEvents = map['events'];
    final events = <DpdTrackEvent>[];
    if (rawEvents is List) {
      for (final e in rawEvents) {
        if (e is Map) {
          events.add(DpdTrackEvent.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return DpdTrackingResult(
      ok: map['ok'] == true,
      status: (map['status'] ?? '').toString(),
      events: events,
      guide: map['guide']?.toString(),
      message: map['message']?.toString(),
    );
  }
}
