/// Reconstrói path Hub após redirect permanente de handle (301 metadata).
class HubRouteRedirect {
  HubRouteRedirect._();

  /// `/old-handle/live?utm=1` + `newHandle` → `/new-handle/live?utm=1`
  static String rebuildPath({
    required Uri uri,
    required String newHandle,
  }) {
    final handle = newHandle.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    if (handle.isEmpty) return uri.path;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final suffix = segments.length > 1 ? segments.sublist(1) : <String>[];
    final path = [
      handle,
      ...suffix,
    ].join('/');
    final base = '/$path';
    if (uri.query.isEmpty) return base;
    return '$base?${uri.query}';
  }
}
