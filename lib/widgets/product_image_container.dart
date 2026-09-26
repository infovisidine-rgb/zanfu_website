import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

import 'brand_image.dart';
import 'local_cached_image.dart';
import 'shimmer.dart';

class ProductImageContainer extends StatelessWidget {
  final String imagePath;
  final double width;
  final double height;
  final double imageSize;
  final double borderRadius;
  final Color backgroundColor;
  /// Order history: only show images already cached from catalog — no download.
  final bool cacheOnly;
  final BoxFit fit;

  const ProductImageContainer({
    super.key,
    required this.imagePath,
    required this.width,
    required this.height,
    required this.imageSize,
    this.borderRadius = 8,
    this.backgroundColor = AppColors.scaffoldBackground,
    this.cacheOnly = false,
    this.fit = BoxFit.contain,
  });

  bool get _isNetwork =>
      imagePath.startsWith('http://') || imagePath.startsWith('https://');

  bool get _isAsset => imagePath.startsWith('assets/');

  Widget _missingImageIcon() => Icon(
        Icons.fastfood_outlined,
        size: imageSize * 0.55,
        color: AppColors.primary.withValues(alpha: 0.55),
      );

  @override
  Widget build(BuildContext context) {
    final displayW = fit == BoxFit.cover ? width : imageSize;
    final displayH = fit == BoxFit.cover ? height : imageSize;
    // Square shimmer when tile has no radius — rounded shimmer left
    // gaps at bottom corners where the gradient peeked through.
    final shimmer = Shimmer.rectangular(
      width: displayW,
      height: displayH,
      shapeBorder: RoundedRectangleBorder(
        borderRadius: borderRadius > 0
            ? BorderRadius.circular(borderRadius)
            : BorderRadius.zero,
      ),
    );
    final missingIcon = _missingImageIcon();

    Widget child;
    if (_isNetwork) {
      child = LocalCachedImage(
        imageUrl: imagePath,
        width: displayW,
        height: displayH,
        fit: fit,
        cacheOnly: cacheOnly,
        placeholder: cacheOnly ? missingIcon : shimmer,
        errorWidget: cacheOnly ? missingIcon : shimmer,
      );
    } else if (_isAsset && imagePath.isNotEmpty) {
      child = BrandImage(
        assetPath: imagePath,
        width: displayW,
        height: displayH,
        fit: fit,
      );
    } else {
      child = cacheOnly ? missingIcon : shimmer;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backgroundColor != Colors.transparent)
              const Opacity(
                opacity: 0.78,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.menuItemImageGradient,
                  ),
                ),
              ),
            fit == BoxFit.cover ? child : Center(child: child),
          ],
        ),
      ),
    );
  }
}
