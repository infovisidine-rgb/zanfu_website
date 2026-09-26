import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'menu_screen.dart';
import '../services/firestore_service.dart';
import '../controllers/promotional_banner_controller.dart';
import '../utils/app_colors.dart';
import '../utils/network_helper.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'google_login_screen.dart';
import '../utils/google_auth_helper.dart';
import '../services/location_service.dart';
import '../controllers/favorites_controller.dart';
import '../controllers/cart_controller.dart';
import '../controllers/user_profile_controller.dart';
import '../widgets/brand_image.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late AnimationController _brandCtrl;


  bool _isRunning = false;
  bool _showBrand = false;
  StreamSubscription<List<ConnectivityResult>>? _waitingForNetSub;

  static const _brandLetters = <(String, Color)>[
    ('V', Colors.white),
    ('I', Colors.white),
    ('S', Colors.white),
    ('I', Colors.white),
    ('D', Color(0xFFF97316)),
    ('I', Color(0xFFF97316)),
    ('N', Color(0xFFF97316)),
    ('E', Color(0xFFF97316)),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.elasticOut),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _brandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _controller.forward();
    // Visidine brand: wait 1s, then cascade letters from the left.
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _showBrand = true);
      _brandCtrl.forward(from: 0);
    });
    _initializeApp();
  }

  void _setProgress(double value, String label) {
    // Kept as a dummy method so we don't have to remove all calls
  }

  void _stopWaitingForInternet() {
    _waitingForNetSub?.cancel();
    _waitingForNetSub = null;
  }

  /// Load Google login assets into image cache during splash.
  Future<void> _precacheLoginAssets() async {
    // Wait until first frame so [context] is ready for [precacheImage].
    final ready = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ready.isCompleted) ready.complete();
    });
    await ready.future;
    if (!mounted) return;
    try {
      await Future.wait([
        precacheImage(const NetworkImage('/brand/google_g_logo.png'), context),
        precacheImage(const NetworkImage('/brand/zanfu_logo.png'), context),
        precacheImage(const NetworkImage('/brand/zanfuwhitelogo.png'), context),
      ]);
    } catch (e) {
      debugPrint('SplashScreen: login asset precache failed: $e');
    }
  }

  /// Stalls until real internet data works (not just Wi‑Fi/mobile linked).
  /// Limited connectivity (connected but no data) must not pass this gate.
  Future<void> _waitUntilOnline({
    String label = 'Waiting for internet...',
  }) async {
    if (await NetworkHelper.hasInternetAccess()) return;

    _setProgress(0.05, label);
    debugPrint(
      'SplashScreen: waiting for real internet (limited/offline blocked)',
    );

    final completer = Completer<void>();
    _stopWaitingForInternet();
    // Connectivity change is only a hint — always re-check real data access.
    _waitingForNetSub =
        Connectivity().onConnectivityChanged.listen((_) async {
      if (await NetworkHelper.hasInternetAccess()) {
        _stopWaitingForInternet();
        if (!completer.isCompleted) completer.complete();
      }
    });

    while (mounted && !completer.isCompleted) {
      if (await NetworkHelper.hasInternetAccess()) {
        _stopWaitingForInternet();
        if (!completer.isCompleted) completer.complete();
        break;
      }
      if (mounted) {
        final linked = await NetworkHelper.hasConnectivity();
        _setProgress(
          0.05,
          linked
              ? 'Limited connection — waiting for data...'
              : label,
        );
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    if (!mounted) {
      _stopWaitingForInternet();
      return;
    }
    await completer.future;
    if (mounted) {
      _setProgress(0.12, 'Internet connected...');
    }
  }

  Future<void> _initializeApp() async {
    if (_isRunning) return;
    _isRunning = true;
    _stopWaitingForInternet();

    final startTime = DateTime.now();
    // Start location service in background, do not block splash
    LocationService().initLocation();

    try {
      // Warm login-screen images so Google icon is ready before navigation
      await _precacheLoginAssets();

      // Fast local storage loads
      await FavoritesController().load();
      await CartController().load();
      
      // Load whatever is in the local cache instantly
      await FirestoreService.preloadMenuCache();
      await FirestoreService.preloadBranchesCache();
      await FirestoreService.preloadModelUrlCatalog();
      await FirestoreService.preloadModelsCache();

      if (mounted) {
        setState(() {
          _setProgress(0.8, 'Loading...');
        });
      }

      // -------------------------------------------------------------
      // WEB-OPTIMIZED ARCHITECTURE: LAZY BACKGROUND FETCHING
      // -------------------------------------------------------------
      // Instead of freezing the Splash Screen waiting for all data, 
      // we fire off the network calls in the background and move on.
      // The MenuScreen will show Shimmer loaders if data is missing.
      FirestoreService.fetchRemoteCatalogVersion().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      ).then((remoteVersion) {
        if (remoteVersion != null) {
          // Trigger silent background updates
          FirestoreService.refreshMenuCacheInBackground();
          FirestoreService.fetchModelUrlCatalog();
          PromotionalBannerController().loadBanners(force: true);
          FirestoreService.refreshBranchesCacheInBackground();
          FirestoreService.refreshModelsCacheInBackground();
          FirestoreService.saveLocalCatalogVersion(remoteVersion);
        } else {
          // Fallback triggers if version fetch fails
          FirestoreService.refreshMenuCacheInBackground();
          PromotionalBannerController().loadBanners();
        }
      });

      if (mounted) {
        _setProgress(1.0, 'Ready');
      }

      // Minimum splash duration for visual stability (3.5s)
      final elapsed = DateTime.now().difference(startTime);
      const minSplashDuration = Duration(milliseconds: 3500);
      if (elapsed < minSplashDuration) {
        await Future.delayed(minSplashDuration - elapsed);
      }

      if (!mounted) return;
      await _navigateNext();
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _navigateNext() async {
    var user = FirebaseAuth.instance.currentUser;

    // Web: After signInWithRedirect, the browser returns to this page.
    // getRedirectResult() picks up the Google credential from that redirect.
    if (user == null && kIsWeb) {
      try {
        user = await GoogleAuthHelper.getRedirectResult();
      } catch (e) {
        debugPrint('Splash getRedirectResult error: $e');
      }
    }

    if (user != null) {
      try {
        await UserProfileController().ensureLoaded();
      } catch (e) {
        debugPrint('Splash profile load error: $e');
      }
    }
    
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MenuScreen(showLoginOnStart: user == null),
      ),
    );
  }

  @override
  void dispose() {
    _stopWaitingForInternet();
    _brandCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildVisidineBrand() {
    if (!_showBrand) return const SizedBox.shrink();
    final n = _brandLetters.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(n, (i) {
        final start = (i / n) * 0.72;
        final end = (start + 0.28).clamp(0.0, 1.0);
        final anim = CurvedAnimation(
          parent: _brandCtrl,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        );
        final (letter, color) = _brandLetters[i];
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            // Each letter emerges from the previous one (from the left).
            position: Tween<Offset>(
              begin: const Offset(-0.85, 0),
              end: Offset.zero,
            ).animate(anim),
            child: Text(
              letter,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.matteBlack,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: const BrandImage(
                      assetPath: 'assets/zanfu_logo.png',
                      width: 260,
                    ),
                  ),
                ),
              ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 14,
                child: Center(child: _buildVisidineBrand()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
