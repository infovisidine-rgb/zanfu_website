import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/app_colors.dart';
import '../utils/google_auth_helper.dart';
import '../utils/network_helper.dart';
import '../widgets/touch_scale_effect.dart';
import '../widgets/brand_image.dart';
import 'menu_screen.dart';

class GoogleLoginScreen extends StatefulWidget {
  const GoogleLoginScreen({super.key});

  @override
  State<GoogleLoginScreen> createState() => _GoogleLoginScreenState();
}

class _GoogleLoginScreenState extends State<GoogleLoginScreen> {
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  /// Button loaders only — avoid full-screen rebuilds / Provider notify.
  final ValueNotifier<bool> _googleLoading = ValueNotifier(false);

  bool get _isBusy => _googleLoading.value;

  @override
  void dispose() {
    _netSub?.cancel();
    _googleLoading.dispose();
    super.dispose();
  }

  bool _isUserCancelled(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('sign_in_canceled') ||
        s.contains('canceled') ||
        s.contains('cancelled') ||
        s.contains('popup-closed-by-user') ||
        s.contains('web-context-cancelled');
  }

  bool _isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('network') ||
        s.contains('socket') ||
        s.contains('timeout') ||
        s.contains('timed out') ||
        s.contains('unreachable') ||
        s.contains('connection') ||
        s.contains('failed host lookup') ||
        s.contains('software caused connection abort') ||
        s.contains('connection reset') ||
        s.contains('offline') ||
        s.contains('unavailable');
  }

  /// Wait until real internet data works — limited Wi‑Fi/mobile must not pass.
  Future<void> _waitUntilOnline() async {
    if (await NetworkHelper.hasInternetAccess()) return;

    debugPrint(
      'GoogleLogin: waiting for real internet (limited/offline blocked)',
    );

    final completer = Completer<void>();
    _netSub?.cancel();
    _netSub = Connectivity().onConnectivityChanged.listen((_) async {
      if (await NetworkHelper.hasInternetAccess()) {
        _netSub?.cancel();
        _netSub = null;
        if (!completer.isCompleted) completer.complete();
      }
    });

    while (mounted && !completer.isCompleted) {
      if (await NetworkHelper.hasInternetAccess()) {
        _netSub?.cancel();
        _netSub = null;
        if (!completer.isCompleted) completer.complete();
        break;
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    if (!mounted) {
      _netSub?.cancel();
      _netSub = null;
      return;
    }
    await completer.future;
  }

  /// Let the button spinner paint before heavy MenuScreen build.
  Future<void> _awaitLoaderPaint() async {
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    await SchedulerBinding.instance.endOfFrame;
  }

  void _goToMenu() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<User?> _signInWithGoogle() => GoogleAuthHelper.signIn();



  Future<void> _handleGoogleSignIn() async {
    if (_isBusy) return;
    _googleLoading.value = true;

    try {
      // Keep spinner until real internet works, then sign in (retry on net fails).
      while (mounted) {
        if (!await NetworkHelper.hasInternetAccess()) {
          await _waitUntilOnline();
          if (!mounted) return;
        }

        try {
          final user = await _signInWithGoogle();
          if (user == null) {
            // User cancelled Google picker — no error UI
            if (mounted) _googleLoading.value = false;
            return;
          }

          // MenuScreen loads profile — don't block / notify on this screen.
          await _awaitLoaderPaint();
          _goToMenu();
          return;
        } catch (e) {
          debugPrint('Google Sign In Error: $e');
          if (_isUserCancelled(e)) {
            if (mounted) _googleLoading.value = false;
            return;
          }

          // Limited / weak internet: keep spinner, wait, retry.
          if (_isNetworkError(e) ||
              !await NetworkHelper.hasInternetAccess()) {
            await _waitUntilOnline();
            continue;
          }
          // Non-network failure — stop spinner & notify
          if (mounted) {
            _googleLoading.value = false;
            final msg = GoogleAuthHelper.formatAuthError(e);
            if (msg.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  backgroundColor: AppColors.discountRed,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Google Sign In Error: $e');
      if (mounted) {
        _googleLoading.value = false;
        final msg = GoogleAuthHelper.formatAuthError(e);
        if (msg.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: AppColors.discountRed,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }



  Widget _googleIcon() {
    return ListenableBuilder(
      listenable: _googleLoading,
      builder: (context, _) {
        if (_googleLoading.value) {
          return const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          );
        }
        return const BrandImage(
          assetPath: 'assets/google_g_logo.png',
          height: 22,
          width: 22,
          filterQuality: FilterQuality.high,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.matteBlack,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.matteBlack,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.matteBlack,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Chrome / short viewports: shrink logo so buttons stay visible.
              final logoSize =
                  (constraints.maxHeight * 0.35).clamp(110.0, 250.0);
              final topGap = constraints.maxHeight < 560 ? 12.0 : 40.0;

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16.0,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 32,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 28),
                            onPressed: _goToMenu,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                        SizedBox(height: topGap > 12 ? topGap - 28 : 0),
                        Center(
                          child: RepaintBoundary(
                            child: BrandImage(
                              assetPath: 'assets/zanfu_logo.png',
                              width: logoSize,
                              height: logoSize,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Welcome to Zanfu',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: AppColors.heading,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            "Don't just order your food—see it on your table. Welcome to the future of dining.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const Spacer(),

                        TouchScaleEffect(
                          onTap: _handleGoogleSignIn,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.55),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _googleIcon(),
                                const SizedBox(width: 12),
                                const Text(
                                  'Sign in with Google',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.heading,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
