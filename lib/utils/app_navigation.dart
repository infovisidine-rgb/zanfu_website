import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/cart_screen.dart';
import '../screens/faqs_screen.dart';
import '../screens/my_orders_screen.dart';
import '../screens/privacy_policy_screen.dart';
import '../screens/terms_conditions_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/search_screen.dart';
import '../screens/view_all_screen.dart';
import 'responsive_helper.dart';

/// Shared navigation that avoids Menu → Cart → Menu/Search stacking.
/// New route sits on top of the root (home); back returns home.
class AppNavigation {
  AppNavigation._();

  /// Side slide panel on laptop/desktop; full-screen route on mobile.
  static void _openWideSidePanel({
    required BuildContext context,
    required String barrierLabel,
    required Widget panelChild,
    required Alignment alignment,
    required Offset slideBegin,
  }) {
    final width = ResponsiveHelper.cartPanelWidth(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim, secondary) {
        return Align(
          alignment: alignment,
          child: Material(
            color: const Color(0xFF121212),
            elevation: 16,
            child: SizedBox(
              width: width,
              height: MediaQuery.sizeOf(ctx).height,
              child: panelChild,
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: slideBegin,
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  static void openCart(BuildContext context) {
    // Tablet uses a full screen like mobile; laptop/desktop keep the side panel.
    if (ResponsiveHelper.isDesktop(context)) {
      _openWideSidePanel(
        context: context,
        barrierLabel: 'Close cart',
        alignment: Alignment.centerRight,
        slideBegin: const Offset(1, 0),
        panelChild: const CartScreen(asSidePanel: true),
      );
      return;
    }

    context.push('/cart');
  }

  static void openProfile(BuildContext context) {
    if (ResponsiveHelper.isWide(context)) {
      _openWideSidePanel(
        context: context,
        barrierLabel: 'Close profile',
        alignment: Alignment.centerLeft,
        slideBegin: const Offset(-1, 0),
        panelChild: const ProfileScreen(asSidePanel: true),
      );
      return;
    }

    context.push('/profile');
  }

  static void openOrders(
    BuildContext context, {
    bool fromRight = false,
  }) {
    if (ResponsiveHelper.isWide(context)) {
      _openWideSidePanel(
        context: context,
        barrierLabel: 'Close orders',
        alignment: fromRight ? Alignment.centerRight : Alignment.centerLeft,
        slideBegin: fromRight ? const Offset(1, 0) : const Offset(-1, 0),
        panelChild: const MyOrdersScreen(asSidePanel: true),
      );
      return;
    }

    context.push('/orders');
  }

  static void openExploreMenu(
    BuildContext context, {
    bool showBackButton = true,
  }) {
    context.push('/explore', extra: showBackButton);
  }

  static void openSearch(BuildContext context) {
    context.push('/search');
  }

  static void openPrivacyPolicy(BuildContext context) {
    context.push('/privacy-policy');
  }

  static void openFaqs(BuildContext context) {
    context.push('/faqs');
  }

  static void openTermsConditions(BuildContext context) {
    context.push('/terms-conditions');
  }
}
