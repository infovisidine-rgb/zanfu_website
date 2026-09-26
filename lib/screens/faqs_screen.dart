import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../controllers/app_config_controller.dart';
import '../utils/app_colors.dart';
import '../utils/app_navigation.dart';
import '../utils/responsive_helper.dart';
import '../widgets/zanfu_app_header.dart';

class FaqsScreen extends StatefulWidget {
  const FaqsScreen({super.key});

  @override
  State<FaqsScreen> createState() => _FaqsScreenState();
}

class _FaqItem {
  const _FaqItem(this.question, this.answer);
  final String question;
  final String answer;
}

class _FaqSection {
  const _FaqSection(this.id, this.title, this.items);
  final String id;
  final String title;
  final List<_FaqItem> items;
}

const _sections = <_FaqSection>[
  _FaqSection('ordering', 'Ordering', [
    _FaqItem(
      'How do I place an order?',
      'Simply browse our menu, add items to your cart, and proceed to checkout. You can order online through our website or mobile app.',
    ),
    _FaqItem(
      'What payment methods do you accept?',
      'We accept Cash on Delivery (COD), Credit/Debit Cards, and various digital payment methods including mobile wallets.',
    ),
    _FaqItem(
      'Can I modify my order after placing it?',
      'You can modify your order within a few minutes of placing it by contacting our customer support. Once the order is being prepared, modifications may not be possible.',
    ),
    _FaqItem(
      'Is there a minimum order amount?',
      'Minimum order amounts may vary by location. Please check the checkout page for any applicable minimums in your area.',
    ),
  ]),
  _FaqSection('delivery', 'Delivery', [
    _FaqItem(
      'What are your delivery hours?',
      'Delivery hours vary by branch. Please check with your nearest branch or contact customer support for current hours.',
    ),
    _FaqItem(
      'How long does delivery take?',
      'Delivery typically takes 30-45 minutes depending on your location and order volume. You\'ll receive an estimated delivery time when you place your order.',
    ),
    _FaqItem(
      'Do you deliver to my area?',
      'Enter your address on our website or app to check if we deliver to your location. Our delivery zones are constantly expanding.',
    ),
    _FaqItem(
      'How can I track my order?',
      'Once your order is confirmed, you\'ll receive real-time updates via SMS and email. You can also track your order status in your account.',
    ),
  ]),
  _FaqSection('menu', 'Menu & Dietary', [
    _FaqItem(
      'Do you have vegetarian options?',
      'Yes, we offer a variety of vegetarian dishes. Look for the vegetarian label on our menu items.',
    ),
    _FaqItem(
      'Can I customize my order?',
      'Yes! You can add special instructions or customize ingredients for most menu items during checkout.',
    ),
    _FaqItem(
      'Do you provide allergen information?',
      'Yes, allergen information is available for all menu items. Please check the item details or contact us if you have specific concerns.',
    ),
  ]),
  _FaqSection('account', 'Account & Support', [
    _FaqItem(
      'How do I create an account?',
      'Click on \'Sign Up\' and enter your details. You can also sign up using your phone number for quick access.',
    ),
    _FaqItem(
      'How can I contact customer support?',
      'You can reach us through our Contact page, call our hotline, or use the live chat feature on our website.',
    ),
    _FaqItem(
      'How do I cancel my order?',
      'You can cancel your order through your account or by contacting customer support within a few minutes of placing it.',
    ),
    _FaqItem(
      'What is your refund policy?',
      'Refunds are processed for cancelled orders and quality issues. Please contact our support team for assistance with refunds.',
    ),
  ]),
];

class _FaqsScreenState extends State<FaqsScreen> {
  String _filter = 'all';
  final AppConfigController _appConfig = AppConfigController();

  @override
  void initState() {
    super.initState();
    _appConfig.loadConfig();
  }

  List<_FaqSection> get _visible {
    if (_filter == 'all') return _sections;
    return _sections.where((s) => s.id == _filter).toList();
  }

  void _openProfile() {
    if (FirebaseAuth.instance.currentUser != null) {
      AppNavigation.openProfile(context);
    }
  }

  void _openOrders() {
    if (FirebaseAuth.instance.currentUser != null) {
      AppNavigation.openOrders(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = ResponsiveHelper.isWide(context);
    final hPad = wide ? 240.0 : 20.0;
    final topPad = ResponsiveHelper.isMobile(context) ? 12.0 : 0.0;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          ColoredBox(
            color: AppColors.matteBlack,
            child: SizedBox(height: MediaQuery.paddingOf(context).top),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: topPad),
                    child: ZanfuAppHeader(
                      showOrderHistoryOnMobile: false,
                      onProfileTap: _openProfile,
                      onOrdersTap: _openOrders,
                      onCartTap: () => AppNavigation.openCart(context),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: ResponsiveHelper.contentMaxWidth(context),
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 28),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                horizontal: wide ? 36 : 12,
                                vertical: wide ? 24 : 14,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Frequently Asked Questions',
                                    style: TextStyle(
                                      fontSize: wide ? 24 : 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Find answers to common questions about our services.',
                                    style: TextStyle(
                                      fontSize: wide ? 15 : 13.0,
                                      height: 1.4,
                                      color: Colors.white.withValues(alpha: 0.78),
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _chip('all', 'All', wide),
                                      _chip('ordering', 'Ordering', wide),
                                      _chip('delivery', 'Delivery', wide),
                                      _chip('menu', 'Menu & Dietary', wide),
                                      _chip('account', 'Account & Support', wide),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  for (final section in _visible) ...[
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: wide ? 18 : 12,
                                        bottom: 6,
                                      ),
                                      child: Text(
                                        section.title,
                                        style: TextStyle(
                                          fontSize: wide ? 18 : 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    for (final item in section.items)
                                      _FaqQuestionTile(item: item),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                horizontal: wide ? 36 : 14,
                                vertical: wide ? 20 : 14,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Still have questions?',
                                    style: TextStyle(
                                      fontSize: wide ? 20 : 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Can\'t find the answer you\'re looking for? Please contact our customer support team.',
                                    style: TextStyle(
                                      fontSize: wide ? 15 : 13.0,
                                      height: 1.4,
                                      color: Colors.white.withValues(alpha: 0.78),
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ListenableBuilder(
                                    listenable: _appConfig,
                                    builder: (context, _) {
                                      final phone =
                                          _appConfig.customerSupportNumber.trim();
                                      if (phone.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      return InkWell(
                                        onTap: () => _appConfig.dialCustomerSupport(),
                                        child: Row(
                                          children: [
                                            Text(
                                              'Customer Support',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: wide ? 15 : 13.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                phone,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.88),
                                                  fontSize: wide ? 14 : 12.5,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String id, String label, bool wide) {
    final selected = _filter == id;
    return GestureDetector(
      onTap: () => setState(() => _filter = id),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: wide ? 14 : 10,
          vertical: wide ? 7 : 5,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: wide ? 13.5 : 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.matteBlack : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _FaqQuestionTile extends StatefulWidget {
  final _FaqItem item;
  const _FaqQuestionTile({required this.item});

  @override
  State<_FaqQuestionTile> createState() => _FaqQuestionTileState();
}

class _FaqQuestionTileState extends State<_FaqQuestionTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final wide = ResponsiveHelper.isWide(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.item.question,
                    style: TextStyle(
                      fontSize: wide ? 15.5 : 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _open
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: _open ? AppColors.primary : AppColors.textSecondary,
                  size: wide ? 22 : 19,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: 10, right: 8),
            child: Text(
              widget.item.answer,
              style: TextStyle(
                fontSize: wide ? 14.5 : 13.0,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        const Divider(color: AppColors.divider, height: 1),
      ],
    );
  }
}

