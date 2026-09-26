import 'package:flutter/material.dart';
import '../models/food_model.dart';
import '../utils/app_colors.dart';
import '../utils/responsive_helper.dart';
import 'discount_badge.dart';

/// Menu tile: image on top; name, desc, price below.
/// Stateless — no hover setState so scroll stays smooth on web.
class ProductGridCard extends StatelessWidget {
  final FoodModel model;
  final VoidCallback onTap;
  final double? imageHeight;

  const ProductGridCard({
    super.key,
    required this.model,
    required this.onTap,
    this.imageHeight,
  });

  String _cleanPrice(String price) {
    final variations = FoodModel.parsePriceVariations(price);
    if (variations.isNotEmpty) {
      return 'Rs ${variations.first.price.toInt()}';
    }
    return price.replaceAll('PKR ', 'Rs ').replaceAll('PKR', 'Rs');
  }

  @override
  Widget build(BuildContext context) {
    final original = model.displayOriginalPrice;
    final hasDisc = model.hasDiscount && original > 0;
    final discounted = hasDisc ? model.discountedFrom(original) : original;
    final priceLabel =
        original > 0 ? 'Rs ${discounted.toInt()}' : _cleanPrice(model.price);
    final desc = model.description.trim();
    final mobile = ResponsiveHelper.isMobile(context);
    final resolvedImageHeight = imageHeight;

    Widget buildImageArea(double width, double height) {
      final imgSide = width < height ? width : height;
      return SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF2A2A2C)),
            const Opacity(
              opacity: 0.78,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.menuItemImageGradient,
                ),
              ),
            ),
            ClipRect(
              child: ProductImageWithDiscount(
                imagePath: model.imagePath,
                width: width,
                height: height,
                imageSize: imgSide,
                borderRadius: 0,
                backgroundColor: Colors.transparent,
                fit: BoxFit.cover,
              ),
            ),
            if (hasDisc)
              Positioned(
                top: 0,
                left: 0,
                child: DiscountBadge(
                  label: model.discountBadgeLabel,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.hardEdge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (resolvedImageHeight != null)
                    LayoutBuilder(
                      builder: (context, outer) {
                        return buildImageArea(
                          outer.maxWidth,
                          resolvedImageHeight,
                        );
                      },
                    )
                  else
                    LayoutBuilder(
                      builder: (context, outer) {
                        final side = outer.maxWidth;
                        final height =
                            side *
                            ResponsiveHelper.homeGridImageHeightRatio(
                              context,
                            );
                        return buildImageArea(side, height);
                      },
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        mobile ? 8 : 10,
                        12,
                        mobile ? 8 : 10,
                        14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: ResponsiveHelper.fontSize(context, 16),
                              fontWeight: FontWeight.w800,
                              color: AppColors.heading,
                              height: 1.15,
                            ),
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Expanded(
                              child: Text(
                                desc,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize:
                                      ResponsiveHelper.fontSize(context, 13),
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ] else
                            const Spacer(),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  priceLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize:
                                        ResponsiveHelper.fontSize(context, 21),
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                    height: 1.05,
                                  ),
                                ),
                              ),
                              if (hasDisc) ...[
                                const SizedBox(width: 6),
                                Text(
                                  'Rs ${original.toInt()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize:
                                        ResponsiveHelper.fontSize(context, 12),
                                    color: AppColors.textSecondary,
                                    decoration: TextDecoration.lineThrough,
                                    height: 1.05,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
