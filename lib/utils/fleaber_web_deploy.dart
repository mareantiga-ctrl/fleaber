/// URL strategy para deploy fleaber.pt em hosting estático (nginx, sem rewrites).
abstract final class FleaberWebDeploy {
  /// Build fleaber.pt: hash URLs + pasta /fleahub/ — não precisa suporte hosting.
  static const useHashUrlOnWeb = bool.fromEnvironment(
    'FLEABER_WEB_HASH_URL',
    defaultValue: false,
  );
}
