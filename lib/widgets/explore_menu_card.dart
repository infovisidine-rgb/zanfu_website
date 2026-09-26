import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_navigation.dart';
import 'touch_scale_effect.dart';

class ExploreMenuCard extends StatelessWidget {
  final VoidCallback? onTap;
  const ExploreMenuCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return TouchScaleEffect(
      onTap: onTap ??
          () {
            // Clear Cart (and any stacked screens) so back goes to home.
            AppNavigation.openExploreMenu(context);
          },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Explore Menu",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Add more items to your cart",
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            const Icon(Icons.arrow_forward_ios, color: AppColors.primary, size: 14),
          ],
        ),
      ),
    );
  }
}
