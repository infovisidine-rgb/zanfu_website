import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/responsive_helper.dart';
import '../utils/app_navigation.dart';
import '../controllers/cart_controller.dart';
import 'app_cart_icon.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showBackButton;
  final VoidCallback? onBackTap;
  final bool showSearchIcon;
  final bool showCartIcon;
  final VoidCallback? onSearchTap;
  final double titleSize;

  const SectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.showBackButton = false,
    this.onBackTap,
    this.showSearchIcon = false,
    this.showCartIcon = false,
    this.onSearchTap,
    this.titleSize = 19,
  });

  @override
  Widget build(BuildContext context) {
    final CartController cart = CartController();

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.heading,
                  fontSize: ResponsiveHelper.fontSize(context, titleSize),
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: ResponsiveHelper.fontSize(context, 13),
                  ),
                ),
            ],
          ),
        ),
        if (showSearchIcon)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: onSearchTap,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.search, color: AppColors.primary, size: 20),
              ),
            ),
          ),
        if (showCartIcon)
          GestureDetector(
            onTap: () {
              AppNavigation.openCart(context);
            },
            child: SizedBox(
              width: 38,
              height: 38,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const AppCartIcon(color: AppColors.primary, size: 20),
                    ),
                  ),
                  if (cart.totalItemsCount > 0)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        child: Text(
                          "${cart.totalItemsCount}",
                          style: const TextStyle(color: AppColors.matteBlack, fontSize: 8, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
