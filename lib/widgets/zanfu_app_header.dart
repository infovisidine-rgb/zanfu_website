import 'package:flutter/material.dart';
import '../controllers/cart_controller.dart';
import '../utils/app_colors.dart';
import '../utils/responsive_helper.dart';
import 'app_cart_icon.dart';
import 'brand_image.dart';
import 'circular_header_icon.dart';
import 'hover_expand_header_icon.dart';

class ZanfuAppHeader extends StatelessWidget {
  final VoidCallback onProfileTap;
  final VoidCallback onOrdersTap;
  final VoidCallback onCartTap;
  final VoidCallback? onMenuTap;
  final bool includeStatusBar;
  final bool showOrderHistoryOnMobile;

  const ZanfuAppHeader({
    super.key,
    required this.onProfileTap,
    required this.onOrdersTap,
    required this.onCartTap,
    this.onMenuTap,
    this.includeStatusBar = false,
    this.showOrderHistoryOnMobile = true,
  });

  @override
  Widget build(BuildContext context) {
    final wide = ResponsiveHelper.isWide(context);
    final iconSize = ResponsiveHelper.headerIconGlyph(context);
    final circleSize = ResponsiveHelper.headerIconCircle(context);
    const iconGap = 8.0;
    final logoHeight = ResponsiveHelper.headerLogoHeight(context);
    final cart = CartController();

    Widget cartIcon() {
      return ListenableBuilder(
        listenable: cart,
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
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              : null;

          if (wide) {
            return HoverExpandHeaderIcon(
              icon: AppCartIcons.outlined,
              label: 'Cart',
              iconColor: Colors.white,
              size: circleSize + 4,
              iconSize: iconSize + 2,
              labelFontSize: 14.5,
              backgroundColor: Colors.transparent,
              borderColor: Colors.transparent,
              labelOnRight: true,
              onTap: onCartTap,
              badge: badge,
            );
          }

          return CircularHeaderIcon(
            icon: AppCartIcons.outlined,
            iconColor: Colors.white,
            size: circleSize,
            iconSize: iconSize,
            backgroundColor: Colors.transparent,
            borderColor: Colors.transparent,
            onTap: onCartTap,
            badge: badge,
          );
        },
      );
    }

    final bar = Container(
      color: AppColors.matteBlack,
      padding: EdgeInsets.fromLTRB(
        wide ? 20.0 : 16.0,
        wide ? 4.0 : 2.0,
        wide ? 20.0 : 16.0,
        wide ? 4.0 : 2.0,
      ),
      child: SizedBox(
        height: logoHeight + (wide ? 2 : 0),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: BrandImage(
                assetPath: 'assets/zanfuwhitelogo.png',
                height: logoHeight,
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Row(
                children: [
                  if (wide || onMenuTap == null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HoverExpandHeaderIcon(
                          icon: Icons.person_outline_rounded,
                          label: 'Profile',
                          iconColor: Colors.white,
                          size: circleSize,
                          iconSize: iconSize,
                          backgroundColor: Colors.transparent,
                          borderColor: Colors.transparent,
                          onTap: onProfileTap,
                        ),
                        if (wide || showOrderHistoryOnMobile) ...[
                          const SizedBox(width: iconGap),
                          HoverExpandHeaderIcon(
                            icon: Icons.receipt_long_outlined,
                            label: 'Order History',
                            iconColor: Colors.white,
                            size: circleSize,
                            iconSize: iconSize,
                            backgroundColor: Colors.transparent,
                            borderColor: Colors.transparent,
                            onTap: onOrdersTap,
                          ),
                        ],
                      ],
                    )
                  else
                    CircularHeaderIcon(
                      icon: Icons.menu,
                      iconColor: Colors.white,
                      size: circleSize,
                      iconSize: iconSize,
                      backgroundColor: Colors.transparent,
                      borderColor: Colors.transparent,
                      onTap: onMenuTap,
                    ),
                  const Spacer(),
                  cartIcon(),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!includeStatusBar) return bar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColoredBox(
          color: AppColors.matteBlack,
          child: SizedBox(height: MediaQuery.paddingOf(context).top),
        ),
        bar,
      ],
    );
  }
}
