import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'product_image_container.dart';

/// Shared discount ribbon used on menu / detail / cart / search image tiles.
class DiscountBadge extends StatelessWidget {
  final String label;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const DiscountBadge({
    super.key,
    required this.label,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.discountRed,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            bottomRight: Radius.circular(10),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// Image tile with optional top-left [DiscountBadge].
class ProductImageWithDiscount extends StatelessWidget {
  final String imagePath;
  final double width;
  final double height;
  final double imageSize;
  final double borderRadius;
  final Color? backgroundColor;
  final String? discountLabel;
  final bool cacheOnly;
  final BoxFit fit;

  const ProductImageWithDiscount({
    super.key,
    required this.imagePath,
    required this.width,
    required this.height,
    required this.imageSize,
    this.borderRadius = 8,
    this.backgroundColor,
    this.discountLabel,
    this.cacheOnly = false,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final label = (discountLabel ?? '').trim();
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ProductImageContainer(
            imagePath: imagePath,
            width: width,
            height: height,
            imageSize: imageSize,
            borderRadius: borderRadius,
            backgroundColor: backgroundColor ?? AppColors.scaffoldBackground,
            cacheOnly: cacheOnly,
            fit: fit,
          ),
          if (label.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              child: DiscountBadge(label: label),
            ),
        ],
      ),
    );
  }
}
