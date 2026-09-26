import 'package:flutter/material.dart';
import '../models/food_model.dart';
import '../utils/app_colors.dart';
import 'discount_badge.dart';

class ProductRowCard extends StatelessWidget {
  final FoodModel model;
  final VoidCallback onTap;
  final VoidCallback? onAddTap;
  final bool showAddButton;
  final Color? imageBackgroundColor;

  const ProductRowCard({
    super.key,
    required this.model,
    required this.onTap,
    this.onAddTap,
    this.showAddButton = true,
    this.imageBackgroundColor,
  });

  String _cleanPrice(String price) {
    final variations = FoodModel.parsePriceVariations(price);
    if (variations.isNotEmpty) {
      return 'Rs ${variations.first.price.toInt()}';
    }
    return price
        .replaceAll('PKR ', 'Rs ')
        .replaceAll('PKR', 'Rs');
  }

  @override
  Widget build(BuildContext context) {
    final original = model.displayOriginalPrice;
    final hasDisc = model.hasDiscount && original > 0;
    final discounted = hasDisc ? model.discountedFrom(original) : original;
    final priceLabel = original > 0
        ? 'Rs ${discounted.toInt()}'
        : _cleanPrice(model.price);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductImageWithDiscount(
              imagePath: model.imagePath,
              width: 90,
              height: 90,
              imageSize: 82,
              backgroundColor:
                  imageBackgroundColor ?? AppColors.scaffoldBackground,
              discountLabel: hasDisc ? model.discountBadgeLabel : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.heading,
                    ),
                  ),
                  if (model.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      model.description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                      ),
                    ),
                  ] else
                    const SizedBox(height: 18),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                priceLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            if (hasDisc) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Rs ${original.toInt()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (showAddButton)
                        GestureDetector(
                          onTap: onAddTap ?? onTap,
                          child: Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.add,
                                size: 16,
                                color: AppColors.matteBlack,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
