import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1606/out/pass1.json').readAsStringSync(),
  ) as Map;
  final keys = [
    'observe',
    'sealed',
    'hostile',
    'PATCH',
    'INSERT',
    'mux_stream',
    'offer',
    'review',
    'user_type',
    'checkout fixture',
    'lives',
    'stripe_checkout',
    'device_token',
    'wallet',
  ];
  for (final m in j['matrix'] as List) {
    final a = '${m['attack']}'.toLowerCase();
    final s = '${m['surface']}'.toLowerCase();
    final hit = keys.any((k) => a.contains(k.toLowerCase()) || s.contains(k.toLowerCase()));
    if (!hit) continue;
    final r = '${m['result']}';
    final clip = r.length > 500 ? '${r.substring(0, 500)}…' : r;
    stdout.writeln('--- ${m['identity']} | ${m['surface']} | ${m['attack']}');
    stdout.writeln(clip);
  }
}
