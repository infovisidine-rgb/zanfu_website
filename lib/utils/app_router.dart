import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/menu_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/faqs_screen.dart';
import '../screens/my_orders_screen.dart';
import '../screens/privacy_policy_screen.dart';
import '../screens/terms_conditions_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/search_screen.dart';
import '../screens/view_all_screen.dart';
import '../screens/checkout_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const MenuScreen(),
    ),
    GoRoute(
      path: '/cart',
      builder: (context, state) => const CartScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/orders',
      builder: (context, state) => const MyOrdersScreen(),
    ),
    GoRoute(
      path: '/explore',
      builder: (context, state) {
        final showBackButton = (state.extra as bool?) ?? true;
        return ViewAllScreen(showBackButton: showBackButton);
      },
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: '/privacy-policy',
      builder: (context, state) => const PrivacyPolicyScreen(),
    ),
    GoRoute(
      path: '/faqs',
      builder: (context, state) => const FaqsScreen(),
    ),
    GoRoute(
      path: '/terms-conditions',
      builder: (context, state) => const TermsConditionsScreen(),
    ),
    GoRoute(
      path: '/checkout',
      builder: (context, state) => const CheckoutScreen(),
    ),
    GoRoute(
      path: '/product',
      builder: (context, state) => state.extra as Widget,
    ),
  ],
);
