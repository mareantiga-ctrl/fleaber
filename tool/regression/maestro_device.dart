// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

/// Detecção de emulador/device via `adb devices` + bridge Maestro + instalação APK debug.
class MaestroDeviceProbe {
  MaestroDeviceProbe({
    required this.maestroCliOk,
    required this.maestroEnvOk,
    required this.adbOk,
    required this.devices,
    this.defaultDevice,
    this.maestroConnectedDevice,
    this.apkPath,
    this.apkExists = false,
  });

  final bool maestroCliOk;
  final bool maestroEnvOk;
  final bool adbOk;
  final List<String> devices;
  final String? defaultDevice;
  final String? maestroConnectedDevice;
  final String? apkPath;
  final bool apkExists;

  bool get canRunMaestro =>
      maestroCliOk &&
      maestroEnvOk &&
      adbOk &&
      devices.isNotEmpty &&
      maestroConnectedDevice != null &&
      maestroConnectedDevice!.isNotEmpty;

  String get skipReason {
    if (!maestroCliOk) return 'Maestro CLI em falta (.tools/maestro/)';
    if (!maestroEnvOk) return '.maestro/.env em falta';
    if (!adbOk) return 'adb não encontrado';
    if (devices.isEmpty) return 'Nenhum emulador/device (adb devices vazio)';
    if (maestroConnectedDevice == null || maestroConnectedDevice!.isEmpty) {
      return 'Maestro CLI não vê emulador (adb OK mas bridge Maestro falhou — cold boot AVD)';
    }
    return '';
  }

  static Future<MaestroDeviceProbe> detect(String repoRoot) async {
    final maestroBat = '$repoRoot/.tools/maestro/maestro/bin/maestro.bat';
    final envFile = '$repoRoot/.maestro/.env';
    final apk = '$repoRoot/build/app/outputs/flutter-apk/app-debug.apk';

    final adb = _adbPath();
    final adbOk = adb != null && File(adb).existsSync();
    final devices = adbOk
        ? await _listDevices(adb!, pruneOffline: true)
        : <String>[];

    String? defaultDevice;
    if (File(envFile).existsSync()) {
      for (final line in File(envFile).readAsLinesSync()) {
        final t = line.trim();
        if (t.startsWith('MAESTRO_DEVICE_DEFAULT=')) {
          defaultDevice = t.split('=').skip(1).join('=').trim();
        } else if (t.startsWith('MAESTRO_DEVICE_BUYER=') && defaultDevice == null) {
          defaultDevice = t.split('=').skip(1).join('=').trim();
        }
      }
    }
    if ((defaultDevice == null || defaultDevice.isEmpty) && devices.isNotEmpty) {
      defaultDevice = devices.first;
    }
    if (defaultDevice != null &&
        defaultDevice.isNotEmpty &&
        devices.isNotEmpty &&
        !devices.contains(defaultDevice)) {
      defaultDevice = devices.first;
    }

    final maestroCliOk = File(maestroBat).existsSync();
    String? maestroConnectedDevice;
    if (maestroCliOk && devices.isNotEmpty) {
      maestroConnectedDevice = await _probeMaestroBridge(
        maestroBat: maestroBat,
        devices: devices,
      );
    }

    return MaestroDeviceProbe(
      maestroCliOk: maestroCliOk,
      maestroEnvOk: File(envFile).existsSync(),
      adbOk: adbOk,
      devices: devices,
      defaultDevice: defaultDevice,
      maestroConnectedDevice: maestroConnectedDevice,
      apkPath: apk,
      apkExists: File(apk).existsSync(),
    );
  }

  /// Tenta `maestro hierarchy` em cada device adb até um responder.
  static Future<String?> _probeMaestroBridge({
    required String maestroBat,
    required List<String> devices,
  }) async {
    for (final device in devices) {
      print('Maestro bridge probe em $device…');
      try {
        final r = await Process.run(
          maestroBat,
          ['--device', device, 'hierarchy'],
          runInShell: true,
          environment: _maestroProcessEnv(),
        ).timeout(const Duration(seconds: 90));
        final out = '${r.stdout}\n${r.stderr}';
        if (r.exitCode == 0 &&
            (out.contains('"children"') || out.contains('hierarchy'))) {
          print('Maestro bridge OK: $device');
          return device;
        }
        if (out.contains('not connected') || out.contains('0 devices connected')) {
          print('Maestro bridge falhou em $device — device not connected');
        } else {
          print('Maestro bridge falhou em $device (exit ${r.exitCode})');
        }
      } on TimeoutException {
        print('Maestro bridge timeout em $device');
      } catch (e) {
        print('Maestro bridge erro em $device: $e');
      }
    }
    return null;
  }

  static String? _adbPath() {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null) {
      final p = '$local/Android/Sdk/platform-tools/adb.exe';
      if (File(p).existsSync()) return p;
    }
    return 'adb';
  }

  static Future<List<String>> _listDevices(
    String adb, {
    bool pruneOffline = false,
  }) async {
    try {
      if (pruneOffline) {
        await _restartAdbIfOfflinePresent(adb);
      }
      final r = await Process.run(adb, ['devices'], runInShell: true);
      final lines = '${r.stdout}\n${r.stderr}'.split('\n');
      final out = <String>[];
      for (final line in lines) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('List of devices')) continue;
        if (t.endsWith('\tdevice') || t.contains(RegExp(r'\s+device\s*$'))) {
          final id = t.split(RegExp(r'\s+')).first;
          if (id.isNotEmpty) out.add(id);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Emuladores `offline` no adb quebram o bridge Maestro (host:features).
  static Future<void> _restartAdbIfOfflinePresent(String adb) async {
    try {
      final r = await Process.run(adb, ['devices'], runInShell: true);
      final text = '${r.stdout}\n${r.stderr}';
      if (!text.contains(RegExp(r'\s+offline\s*$', multiLine: true))) return;
      print('AVISO adb: device offline detectado — a reiniciar adb server…');
      await Process.run(adb, ['kill-server'], runInShell: true);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await Process.run(adb, ['start-server'], runInShell: true);
    } catch (_) {
      // best-effort
    }
  }

  static Map<String, String> _maestroProcessEnv() {
    final local = Platform.environment['LOCALAPPDATA'];
    final androidHome = Platform.environment['ANDROID_HOME'] ??
        (local != null ? '$local/Android/Sdk' : null);
    final javaHome = Platform.environment['JAVA_HOME'] ??
        r'C:\Program Files\Android\Android Studio\jbr';
    final path = Platform.environment['PATH'] ?? '';
    final extra = <String>[];
    if (javaHome.isNotEmpty) extra.add('$javaHome\\bin');
    if (androidHome != null && androidHome.isNotEmpty) {
      extra.add('$androidHome\\platform-tools');
      extra.add('$androidHome\\emulator');
    }
    return {
      if (androidHome != null) 'ANDROID_HOME': androidHome,
      if (javaHome.isNotEmpty) 'JAVA_HOME': javaHome,
      'PATH': [...extra, path].join(';'),
      'MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED': 'true',
    };
  }

  Future<bool> ensureApkInstalled({List<String>? preferDevices}) async {
    if (!canRunMaestro || !apkExists) return false;
    final adb = _adbPath();
    if (adb == null) return false;

    final candidates = <String>[
      ...?preferDevices,
      if (defaultDevice != null) defaultDevice!,
      ...devices,
    ].where((d) => d.isNotEmpty).toSet().toList();

    var anyOk = false;
    for (final device in candidates) {
      if (!devices.contains(device)) continue;
      print('Instalando APK debug em $device…');
      final r = await Process.run(
        adb,
        ['-s', device, 'install', '-r', apkPath!],
        runInShell: true,
      );
      if (r.exitCode == 0) {
        anyOk = true;
        await _warmLaunch(adb, device);
      } else {
        print('AVISO: install APK em $device falhou — ${r.stderr}'.trim());
      }
    }
    return anyOk;
  }

  /// Abre a app uma vez após (re)instalar e deixa-a em foreground.
  ///
  /// Numa app acabada de instalar (nunca aberta), o `launchApp clearState`
  /// do Maestro pode ressaltar para o launcher; em MIUI o launcher anima
  /// continuamente (App Vault/-1 screen) e o Maestro nunca obtém "idle",
  /// ficando preso indefinidamente. Aquecer a app evita esse ressalto.
  static Future<void> _warmLaunch(String adb, String device) async {
    try {
      print('Aquecendo app em $device (warm-launch)…');
      await Process.run(
        adb,
        [
          '-s',
          device,
          'shell',
          'monkey',
          '-p',
          'pt.fleaber.app',
          '-c',
          'android.intent.category.LAUNCHER',
          '1',
        ],
        runInShell: true,
      );
      await Future<void>.delayed(const Duration(seconds: 6));
    } catch (e) {
      print('AVISO warm-launch em $device: $e');
    }
  }

  /// Abre deep link via adb (Maestro openLink falha com app em foreground / singleTop).
  static Future<bool> openDeepLinkViaAdb({
    required String device,
    required String link,
  }) async {
    final adb = _adbPath();
    if (adb == null || device.isEmpty || link.isEmpty) return false;
    print('adb deep link → $link ($device)');
    try {
      // Aspas obrigatórias: & na query parte o am start no shell Android.
      final shellCmd =
          'am start -a android.intent.action.VIEW -d "$link" pt.fleaber.app';
      final r = await Process.run(
        adb,
        ['-s', device, 'shell', shellCmd],
        runInShell: false,
      );
      if (r.exitCode != 0) {
        print('AVISO adb deep link falhou: ${r.stderr}'.trim());
        return false;
      }
      await Future<void>.delayed(const Duration(seconds: 4));
      return true;
    } catch (e) {
      print('AVISO adb deep link erro: $e');
      return false;
    }
  }
}
