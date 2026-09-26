import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_navigation.dart';
import '../utils/responsive_helper.dart';
import '../widgets/zanfu_app_header.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Title('Privacy Policy'),
                        _Body(
                          'At Zanfu, we are committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you visit our website or use our services.',
                        ),
                        _Title('Information We Collect'),
                        _Body(
                          'We collect information you provide directly to us, such as when you:',
                        ),
                        _Bullet('Create an account or place an order'),
                        _Bullet('Make a reservation'),
                        _Bullet('Subscribe to our newsletter'),
                        _Bullet('Contact us with inquiries or feedback'),
                        _Bullet('Participate in surveys or promotions'),
                        _Body(
                          'This information may include your name, email address, phone number, delivery address, payment information, and order history.',
                        ),
                        _Title('How We Use Your Information'),
                        _Body('We use the information we collect to:'),
                        _Bullet('Process and fulfill your orders'),
                        _Bullet('Send order confirmations and updates'),
                        _Bullet(
                          'Communicate with you about products, services, and promotions',
                        ),
                        _Bullet('Improve our website and services'),
                        _Bullet('Respond to your comments and questions'),
                        _Bullet(
                          'Prevent fraudulent transactions and monitor against theft',
                        ),
                        _Title('Information Sharing'),
                        _Body(
                          'We do not sell, trade, or otherwise transfer your personal information to outside parties except:',
                        ),
                        _Bullet(
                          'To trusted third parties who assist us in operating our website and conducting our business',
                        ),
                        _Bullet(
                          'When we believe release is appropriate to comply with the law',
                        ),
                        _Bullet('To protect our rights, property, or safety'),
                        _Title('Data Security'),
                        _Body(
                          'We implement appropriate technical and organizational security measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction. However, no method of transmission over the Internet is 100% secure.',
                        ),
                        _Title('Cookies'),
                        _Body(
                          'We use cookies to enhance your experience on our website. Cookies are small files that a site transfers to your computer\'s hard drive through your web browser. They enable the site to recognize your browser and remember certain information.',
                        ),
                        _Title('Your Rights'),
                        _Body('You have the right to:'),
                        _Bullet(
                          'Access the personal information we hold about you',
                        ),
                        _Bullet('Request correction of inaccurate information'),
                        _Bullet('Request deletion of your personal information'),
                        _Bullet('Opt-out of marketing communications'),
                        _Title('Changes to This Policy'),
                        _Body(
                          'We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page and updating the "Last Updated" date.',
                        ),
                        _Title('Contact Us'),
                        _Body(
                          'If you have any questions about this Privacy Policy, please contact us through our Contact page or reach out to our customer support team.',
                        ),
                        SizedBox(height: 18),
                        Text(
                          'Last Updated: August 2026',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
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

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final wide = ResponsiveHelper.isWide(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•  ',
            style: TextStyle(
              fontSize: wide ? 16.5 : 13.5,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: wide ? 16.5 : 13.5,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.86),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
