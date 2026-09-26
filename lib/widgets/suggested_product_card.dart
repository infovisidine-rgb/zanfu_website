import 'package:flutter/material.dart';
import '../models/food_model.dart';
import '../utils/app_colors.dart';
import '../screens/detail_screen.dart';
import 'discount_badge.dart';
import 'touch_scale_effect.dart';

class SuggestedProductCard extends StatelessWidget {
  final FoodModel item;
  final bool showName;
  final VoidCallback? onTapBack;
  final VoidCallback? onTap;

  const SuggestedProductCard({
    super.key,
    required this.item,
    this.showName = true,
    this.onTapBack,
    this.onTap,
  });

  String _getPrice(FoodModel model) {
    final original = model.displayOriginalPrice;
    if (original <= 0) {
      final variations = FoodModel.parsePriceVariations(model.price);
      if (variations.isNotEmpty) {
        return variations.first.price.toInt().toString();
      }
      return model.price.replaceAll('Rs ', '').replaceAll('Rs', '');
    }
    return model.discountedFrom(original).toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    final price = _getPrice(item);
    final hasDisc = item.hasDiscount && item.displayOriginalPrice > 0;

    return TouchScaleEffect(
      onTap: onTap ??
          () async {
            await DetailScreen.open(
              context,
              (asDialog) => DetailScreen(model: item, asDialog: asDialog),
            );
            if (onTapBack != null) onTapBack!();
          },
      child: Container(
        width: showName ? 230 : 165,
        height: 96,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Row(
          children: [
            // Fixed square tile — parent list must not squash this.
            ProductImageWithDiscount(
              imagePath: item.imagePath,
              width: 80,
              height: 80,
              imageSize: 80,
              borderRadius: 6,
              backgroundColor: AppColors.surfaceElevated,
              fit: BoxFit.cover,
              discountLabel: hasDisc ? item.discountBadgeLabel : null,
            ),
            if (showName) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.heading,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Rs $price",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Rs $price",
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
