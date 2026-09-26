import 'package:flutter/material.dart';

/// Shared shopping-cart icon (rounded style) used across the app.
class AppCartIcons {
  static const IconData outlined = Icons.shopping_cart_rounded;
  static const IconData filled = Icons.shopping_cart_rounded;
}

class AppCartIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final bool filled;

  const AppCartIcon({
    super.key,
    this.size = 22,
    this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      filled ? AppCartIcons.filled : AppCartIcons.outlined,
      size: size,
      color: color,
    );
  }
}
