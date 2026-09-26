import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_colors.dart';
import '../utils/app_navigation.dart';
import '../controllers/cart_controller.dart';
import '../utils/responsive_helper.dart';
import 'app_cart_icon.dart';
import 'hover_expand_header_icon.dart';

class CustomHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String subtitle;
  final bool showBackButton;
  final bool showSearchIcon;
  final bool showCartIcon;
  final VoidCallback? onSearchTap;
  final double titleSize;
  /// Optional refresh control (right side).
  final VoidCallback? onRefreshTap;
  final bool isRefreshing;
  /// Optional back action (defaults to [Navigator.pop]).
  final VoidCallback? onBackTap;

  const CustomHeader({
    super.key,
    required this.title,
    this.subtitle = "",
    this.showBackButton = false,
    this.showSearchIcon = false,
    this.showCartIcon = true,
    this.onSearchTap,
    this.titleSize = 18,
    this.onRefreshTap,
    this.isRefreshing = false,
    this.onBackTap,
  });

  /// Match item-details AppBar height (`toolbarHeight: 48`).
  double get _toolbarHeight => subtitle.trim().isNotEmpty ? 56.0 : 48.0;

  @override
  Size get preferredSize => Size.fromHeight(_toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final CartController cart = CartController();
    final hasTrailing = showSearchIcon ||
        showCartIcon ||
        onRefreshTap != null;

    return AppBar(
      backgroundColor: AppColors.matteBlack,
      elevation: 0,
      toolbarHeight: _toolbarHeight,
      centerTitle: true,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: AppColors.matteBlack,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      leading: null,
      title: subtitle.trim().isNotEmpty
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          : Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: titleSize,
                fontWeight: FontWeight.w800,
              ),
            ),
      actions: [
        if (showSearchIcon)
          IconButton(
            onPressed: onSearchTap,
            icon: const Icon(Icons.search, color: AppColors.textPrimary),
          ),
        if (onRefreshTap != null)
          Padding(
            padding: EdgeInsets.only(right: showCartIcon ? 0 : 8),
            child: IconButton(
              onPressed: isRefreshing ? null : onRefreshTap,
              icon: isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
            ),
          ),
        if (showCartIcon)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedBuilder(
              animation: cart,
              builder: (context, _) {
                final badge = cart.totalItemsCount > 0
                    ? Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '${cart.totalItemsCount}',
                          style: const TextStyle(
                            color: AppColors.matteBlack,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : null;

                if (ResponsiveHelper.isWide(context)) {
                  return HoverExpandHeaderIcon(
                    icon: AppCartIcons.outlined,
                    label: 'Cart',
                    iconColor: AppColors.textPrimary,
                    size: 36,
                    iconSize: 20,
                    labelFontSize: 13.5,
                    backgroundColor: Colors.transparent,
                    borderColor: AppColors.border,
                    labelOnRight: true,
                    badge: badge,
                    onTap: () => AppNavigation.openCart(context),
                  );
                }

                return GestureDetector(
                  onTap: () => AppNavigation.openCart(context),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.border,
                                width: 1.5,
                              ),
                            ),
                            child: const AppCartIcon(
                              color: AppColors.textPrimary,
                              size: 20,
                            ),
                          ),
                        ),
                        if (badge != null)
                          Positioned(top: 0, right: 0, child: badge),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        // Title stays centered without a back affordance.
        if (!hasTrailing)
          const SizedBox(width: 48),
      ],
    );
  }
}
