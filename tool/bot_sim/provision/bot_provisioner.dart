import 'dart:convert';
import 'dart:io';

import '../../live_ops_staging_client.dart';
import '../fixtures/chat_phrases.dart';

class BotAccount {
  BotAccount({
    required this.index,
    required this.userId,
    required this.email,
    required this.password,
    required this.accessToken,
    required this.internalTag,
    required this.displayName,
  });

  final int index;
  final String userId;
  final String email;
  final String password;
  final String accessToken;
  final String internalTag;
  final String displayName;
}

class BotProvisioner {
  BotProvisioner({
    required this.client,
    required this.env,
    required this.count,
    required this.prefix,
    required this.demoMode,
  });

  final LiveOpsStagingClient client;
  final Map<String, String> env;
  final int count;
  final String prefix;
  final bool demoMode;

  static const cachePath = 'tool/.bot_pool_cache.json';

  Future<List<BotAccount>> provision() async {
    final domain = env['BOT_SIM_EMAIL_DOMAIN']?.trim().isNotEmpty == true
        ? env['BOT_SIM_EMAIL_DOMAIN']!.trim()
        : 'staging.fleaber.bot';
    final password = env['BOT_SIM_DEFAULT_PASSWORD']?.trim().isNotEmpty == true
        ? env['BOT_SIM_DEFAULT_PASSWORD']!.trim()
        : 'FleaberBotSim_Staging_2026!';

    final cache = _loadCache();
    final accounts = <BotAccount>[];

    for (var i = 1; i <= count; i++) {
      final tag = '${prefix}_${i.toString().padLeft(2, '0')}';
      final email = '${tag.toLowerCase()}@$domain';
      final display = demoMode ? demoDisplayName(i) : tag;

      var userId = cache[email]?['user_id']?.toString() ?? '';
      var pwd = cache[email]?['password']?.toString() ?? password;

      if (userId.isEmpty) {
        try {
          userId = await client.createAdminUser(
            email: email,
            password: pwd,
            userMetadata: {
              'bot_sim': true,
              'internal_tag': tag,
              'display_name': display,
            },
          );
          cache[email] = {'user_id': userId, 'password': pwd};
          await _saveCache(cache);
        } catch (e) {
          // Utilizador pode já existir — tentar sign-in
          final body = e.toString();
          if (!body.contains('already') && !body.contains('422')) {
            rethrow;
          }
        }
      }

      String token;
      try {
        token = await client.signIn(email: email, password: pwd);
      } catch (_) {
        userId = await client.createAdminUser(
          email: email,
          password: pwd,
          userMetadata: {'bot_sim': true, 'internal_tag': tag},
        );
        cache[email] = {'user_id': userId, 'password': pwd};
        await _saveCache(cache);
        token = await client.signIn(email: email, password: pwd);
      }

      if (!isUuid(userId)) {
        userId = await client.userIdForAccessToken(token);
        cache[email] = {'user_id': userId, 'password': pwd};
        await _saveCache(cache);
      }

      try {
        await client.patch(
          'profiles',
          'id=eq.$userId',
          {'full_name': '$display [$tag]'},
        );
      } catch (_) {}

      accounts.add(BotAccount(
        index: i,
        userId: userId,
        email: email,
        password: pwd,
        accessToken: token,
        internalTag: tag,
        displayName: display,
      ));
    }

    return accounts;
  }

  Map<String, Map<String, dynamic>> _loadCache() {
    final f = File(cachePath);
    if (!f.existsSync()) return {};
    try {
      final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCache(Map<String, Map<String, dynamic>> cache) async {
    await File(cachePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(cache),
    );
  }
}
