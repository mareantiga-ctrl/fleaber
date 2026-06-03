import 'package:flutter/material.dart';

/// Pull-to-refresh padrão Fleaber (spinner teal).
class FleaberRefresh extends StatelessWidget {
  const FleaberRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  static const Color color = Color(0xFF007782);

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: color,
      onRefresh: onRefresh,
      child: child,
    );
  }
}
