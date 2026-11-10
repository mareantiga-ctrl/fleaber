import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _kDeviceIdKey = 'fleaber_signup_device_id_v1';

/// ID estável por instalação — anti-abuso de registo (não é IMEI / advertising id).
Future<String> fleaberSignupDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_kDeviceIdKey)?.trim();
  if (existing != null && existing.isNotEmpty) return existing;
  final id = const Uuid().v4();
  await prefs.setString(_kDeviceIdKey, id);
  return id;
}
