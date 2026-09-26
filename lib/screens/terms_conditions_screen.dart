import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../controllers/app_config_controller.dart';
import '../utils/app_colors.dart';
import '../utils/app_navigation.dart';
import '../utils/responsive_helper.dart';
import '../widgets/zanfu_app_header.dart';

class TermsConditionsScreen extends StatefulWidget {
  const TermsConditionsScreen({super.key});

  @override
  State<TermsConditionsScreen> createState() => _TermsConditionsScreenState();
}

class _TermsConditionsScreenState extends State<TermsConditionsScreen> {
  final AppConfigController _appConfig = AppConfigController();

  @override
  void initState() {
    super.initState();
    _appConfig.loadConfig();
  }

  void _openProfile(BuildContext context) {
    if (FirebaseAuth.instance.currentUser != null) {
      AppNavigation.openProfile(context);
    }
  }

  void _openOrders(BuildContext context) {
    if (FirebaseAuth.instance.currentUser != null) {
      AppNavigation.openOrders(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = ResponsiveHelper.isWide(context);
    final hPad = wide ? 240.0 : 16.0;
    final phone = _appConfig.customerSupportNumber.trim();

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
                      onProfileTap: () => _openProfile(context),
                      onOrdersTap: () => _openOrders(context),
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
                        padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 32),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: wide ? 40 : 14,
                            vertical: wide ? 28 : 18,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _Title('Terms and Conditions'),
                              const _Body(
                                'Welcome to Zanfu! These Terms and Conditions govern your use of our website and services. By accessing or placing an order through our website, you agree to be bound by these terms.',
                              ),
                              const _Title('1. General Information'),
                              const _Body('Business Name: Zanfu'),
                              const _Body(
                                'Services: Fast food online ordering, delivery coordination, and promotional information.',
                              ),
                              const _Body(
                                'Eligibility: By using this site, you confirm that you are at least 18 years old or accessing the site under the supervision of a parent or guardian.',
                              ),
                              const _Title('2. Menu Items & Pricing'),
                              const _Body(
                                'Accuracy: We strive to keep our online menu, item descriptions, and pricing up to date. However, prices and item availability are subject to change without prior notice.',
                              ),
                              const _Body(
                                'Errors: In the event of a pricing error or incorrect menu detail, Zanfu reserves the right to cancel or adjust orders placed for the affected items.',
                              ),
                              const _Body(
                                'Allergens: Our food is prepared in a kitchen that handles common allergens (including gluten, dairy, nuts, and soy). Please contact us directly before placing an order if you have severe dietary restrictions or food allergies.',
                              ),
                              const _Title('3. Ordering & Payment'),
                              const _Body(
                                'Order Acceptance: Receiving an online order confirmation does not signify our final acceptance of your order. We reserve the right to accept, decline, or limit order quantities for any reason.',
                              ),
                              const _Body(
                                'Payment Terms: Full payment must be made at the time of ordering (via supported online payment methods) or upon delivery/pickup (if Cash on Delivery is selected).',
                              ),
                              const _Title('4. Delivery & Pickup'),
                              const _Body(
                                'Delivery Times: Estimated delivery times are approximations only and may vary due to traffic, weather conditions, or kitchen demand.',
                              ),
                              const _Body(
                                'Customer Responsibility: You are responsible for providing an accurate delivery address and contact phone number. If our driver cannot reach you or access the address, the order may be canceled, and you may still be charged.',
                              ),
                              const _Title('5. Cancellations, Refunds & Returns'),
                              const _Body(
                                'Order Cancellation: Because fast food is prepared fresh immediately upon order placement, orders cannot be canceled once kitchen preparation has begun.',
                              ),
                              const _Body(
                                'Refunds/Replacement: If there is a missing item, incorrect order, or quality issue with your food, please notify us within 30 minutes of receiving your order. Refunds or replacements will be handled at management\'s discretion.',
                              ),
                              const _Title('6. Intellectual Property'),
                              const _Body(
                                'All content on this website—including logos, food photos, brand assets, text, and design—is the property of Zanfu and protected by copyright laws. You may not reproduce, distribute, or use any content without prior written permission.',
                              ),
                              const _Title('7. Limitation of Liability'),
                              const _Body(
                                'Zanfu is not liable for any indirect, incidental, or consequential damages resulting from the use of our website, service delays, or technical outages.',
                              ),
                              const _Title('8. Changes to Terms'),
                              const _Body(
                                'We reserve the right to modify these Terms and Conditions at any time. Any changes will take effect immediately upon posting to this page.',
                              ),
                              const _Title('Contact Us'),
                              const _Body(
                                'If you have any questions regarding these Terms and Conditions, please contact us at:',
                              ),
                              const _Body('Email: support@zanfu.com'),
                              _Body(
                                'Phone: ${phone.isEmpty ? 'Customer support number' : phone}',
                              ),
                            ],
                          ),
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
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);

  @override
  Widget build(BuildContext context) {
    final wide = ResponsiveHelper.isWide(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: wide ? 23 : 18,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.25,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String text;
  const _Body(this.text);

  @override
  Widget build(BuildContext context) {
    final wide = ResponsiveHelper.isWide(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: wide ? 16.5 : 13.5,
          height: 1.45,
          color: Colors.white.withValues(alpha: 0.86),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
