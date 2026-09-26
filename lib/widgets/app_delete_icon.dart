import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Shared delete icon (menu/cart/AR) — one place to restyle.
class AppDeleteIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const AppDeleteIcon({
    super.key,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.delete,
      size: size,
      color: color ?? AppColors.discountRed,
    );
  }
}
