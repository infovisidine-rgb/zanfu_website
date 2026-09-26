import 'package:flutter/material.dart';
import '../controllers/cart_controller.dart';
import '../utils/app_colors.dart';
import '../utils/app_navigation.dart';
import 'product_image_container.dart';

/// Bottom “VIEW CART” strip (same pattern as Explore Menu).
class ViewCartBottomBar extends StatelessWidget {
  final CartController cart;
  /// Max width of the bar; null = full width.
  final double? maxWidth;
  /// Distance from the bottom edge.
  final double bottomInset;
  final double horizontalInset;
  final double height;
  final double imageBoxSize;
  final double imageSize;
  final double countFontSize;
  final double itemsLabelFontSize;

  const ViewCartBottomBar({
    super.key,
    required this.cart,
    this.maxWidth,
    this.bottomInset = 0,
    this.horizontalInset = 0,
    this.height = 64,
    this.imageBoxSize = 48,
    this.imageSize = 40,
    this.countFontSize = 14,
    this.itemsLabelFontSize = 13,
  });

  int _calcCartTotal() {
    int total = 0;
    for (final item in cart.items) {
      double original = 0;
      final priceStr = item.foodModel.price;
      final variation = item.selectedVariation?.trim().toLowerCase() ?? '';
      if (priceStr.contains('|')) {
        if (variation.isNotEmpty) {
          for (final part in priceStr.split('|')) {
            final clean = part.trim();
            final match =
                RegExp(r'^(.+?)\s+(\d+(?:\.\d+)?)\s*$').firstMatch(clean);
            if (match == null) continue;
            var name = match.group(1)!.trim().toLowerCase();
            name = name.replaceAll(RegExp(r'\b(rs|pkr)\b'), '').trim();
            if (name == 's') name = 'small';
            if (name == 'm') name = 'medium';
            if (name == 'l') name = 'large';
            if (name == variation ||
                name.startsWith(variation) ||
                variation.startsWith(name)) {
              original = double.tryParse(match.group(2)!) ?? 0;
              break;
            }
          }
        }
        if (original <= 0) {
          original = item.foodModel.displayOriginalPrice;
        }
      } else {
        original = item.foodModel.displayOriginalPrice;
      }
      total +=
          item.foodModel.discountedFrom(original).round() * item.quantity;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (cart.items.isEmpty) return const SizedBox.shrink();
    final lastAddedItem = cart.items.last;
    final tinyPhone = MediaQuery.sizeOf(context).width < 360;
    final compactHeight = tinyPhone ? (height - 8) : height;
    final cartCtaHeight = tinyPhone
        ? (compactHeight >= 66 ? 42.0 : 38.0)
        : (height >= 66 ? 46.0 : 42.0);

    final bar = GestureDetector(
      onTap: () => AppNavigation.openCart(context),
      child: Container(
        height: compactHeight,
        padding: EdgeInsets.fromLTRB(
          tinyPhone ? 10 : 12,
          tinyPhone ? 3 : 4,
          tinyPhone ? 10 : 12,
          tinyPhone ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: maxWidth != null
              ? BorderRadius.circular(14)
              : BorderRadius.zero,
          border: maxWidth != null
              ? Border.all(color: AppColors.border)
              : const Border(
                  top: BorderSide(color: AppColors.border),
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 15,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          children: [
            ProductImageContainer(
              imagePath: lastAddedItem.foodModel.imagePath,
              width: tinyPhone ? (imageBoxSize - 6) : imageBoxSize,
              height: tinyPhone ? (imageBoxSize - 6) : imageBoxSize,
              imageSize: tinyPhone ? (imageSize - 4) : imageSize,
              borderRadius: 8,
              backgroundColor: AppColors.surfaceElevated,
            ),
            SizedBox(width: tinyPhone ? 8 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${cart.totalItemsCount}',
                    style: TextStyle(
                      fontSize: tinyPhone ? (countFontSize - 1) : countFontSize,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    'Items',
                    style: TextStyle(
                      fontSize: tinyPhone
                          ? (itemsLabelFontSize - 1)
                          : itemsLabelFontSize,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: cartCtaHeight,
              padding: EdgeInsets.symmetric(horizontal: tinyPhone ? 10 : 14),
              decoration: BoxDecoration(
                gradient: AppColors.flameGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Rs ${_calcCartTotal()}',
                    style: TextStyle(
                      fontSize: tinyPhone ? 12.5 : 13.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.onPrimary,
                    ),
                  ),
                  SizedBox(width: tinyPhone ? 10 : 14),
                  Text(
                    'VIEW CART',
                    style: TextStyle(
                      fontSize: tinyPhone ? 10.5 : 11.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.onPrimary,
                      letterSpacing: tinyPhone ? 0.35 : 0.5,
                    ),
                  ),
                  SizedBox(width: tinyPhone ? 2 : 4),
                  Icon(
                    Icons.keyboard_double_arrow_right_rounded,
                    size: tinyPhone ? 16 : 18,
                    color: AppColors.onPrimary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalInset,
        0,
        horizontalInset,
        bottomInset,
      ),
      child: maxWidth == null
          ? bar
          : Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth!),
                child: bar,
              ),
            ),
    );
  }
}
