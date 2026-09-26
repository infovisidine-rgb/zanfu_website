import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_navigation.dart';
import '../utils/app_haptics.dart';
import '../utils/responsive_helper.dart';
import 'view_all_screen.dart';
import '../controllers/cart_controller.dart';
import '../controllers/menu_controller.dart';
import '../controllers/user_profile_controller.dart';
import '../controllers/bottom_nav_controller.dart';
import '../controllers/home_banner_controller.dart';
import '../controllers/app_config_controller.dart';
import '../controllers/promotional_banner_controller.dart';
import '../controllers/home_scroll_to_menu.dart';
import '../models/promotional_banner_model.dart';
import '../models/menu_item_model.dart';
import '../models/food_model.dart';
import '../services/firestore_service.dart';
import '../widgets/shimmer.dart';
import '../widgets/local_cached_image.dart';
import '../widgets/zanfu_app_header.dart';
import '../widgets/flame_gradient_button.dart';
import '../widgets/app_cart_icon.dart';
import '../widgets/brand_image.dart';
import '../widgets/product_grid_card.dart';
import '../widgets/home_typewriter_search_field.dart';
import '../widgets/view_cart_bottom_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/google_auth_helper.dart';
import 'google_login_screen.dart';
import 'detail_screen.dart';

class _HomeSearchSnapshot {
  final bool isSearching;
  final List<FoodMenuItem> results;

  const _HomeSearchSnapshot({
    this.isSearching = false,
    this.results = const [],
  });

  static const empty = _HomeSearchSnapshot();
}

class MenuScreen extends StatefulWidget {
  final int initialIndex;
  final bool showLoginOnStart;

  const MenuScreen({
    super.key,
    this.initialIndex = 0,
    this.showLoginOnStart = false,
  });

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final PageController _pageController = PageController();
  final ScrollController _homeCategoryTabScroll = ScrollController();
  final ScrollController _homeScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _timer;
  bool _isUserHoldingBanner = false;
  DateTime? _lastManualScrollTime;

  late final MenuController _menuController;
  late final UserProfileController _userProfileController;
  final CartController _cart = CartController();
  final AppConfigController _appConfig = AppConfigController();
  final PromotionalBannerController _promoBanners =
      PromotionalBannerController();
  final ValueNotifier<bool> _isDrawerSigningIn = ValueNotifier(false);
  StreamSubscription<User?>? _authSub;
  String _homeSelectedCategory = '';
  final ValueNotifier<String> _homeSelectedCategoryListenable =
      ValueNotifier<String>('');
  List<FoodMenuItem> _allSearchProducts = [];
  final ValueNotifier<_HomeSearchSnapshot> _homeSearch =
      ValueNotifier(_HomeSearchSnapshot.empty);
  bool _isHomeAutoScrolling = false;
  final Map<String, GlobalKey> _homeCategoryKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BottomNavController>().setSelectedIndex(0);
        if (widget.showLoginOnStart) {
          _showLoginDialog();
        }
      }
    });
    _menuController = MenuController(initialIndex: widget.initialIndex);
    _userProfileController = UserProfileController();
    _userProfileController.startListening();
    _appConfig.loadConfig();
    _promoBanners.loadBanners().whenComplete(() {
      if (mounted) _syncBannerTimer();
    });
    _promoBanners.addListener(_syncBannerTimer);
    FirestoreService.menuDataVersion.addListener(
      _menuController.onCacheUpdated,
    );
    FirestoreService.menuDataVersion.addListener(_reloadSearchCatalog);
    _menuController.addListener(_onMenuDataChanged);
    _menuController.loadMenuDataFromCache();
    _searchController.addListener(_onHomeSearchChanged);
    FirestoreService.preloadBranchesCache();
    _reloadSearchCatalog();
    HomeScrollToMenu.instance.addListener(_onExploreMenuFromCart);
    // Keep drawer / profile in sync when user signs in from checkout, etc.
    // StreamBuilder + UserProfileController listeners rebuild UI (no setState).
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;
      _userProfileController.resetSession();
      await _userProfileController.ensureLoaded();
    });
    // In case banners already available (singleton / cache)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncBannerTimer();
    });

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) _menuController.stopLoadingIfStillLoading();
    });
  }

  void _reloadSearchCatalog() {
    final cats = FirestoreService.getCachedCategories();
    final items = <FoodMenuItem>[];
    for (final cat in cats) {
      items.addAll(FirestoreService.getCachedProductsByCategory(cat));
    }
    _allSearchProducts = items;
    if (_homeSearch.value.isSearching) _onHomeSearchChanged();
  }

  bool _isWideLayout(BuildContext context) => ResponsiveHelper.isWide(context);

  void _showLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 650),
          child: const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(24)),
            child: GoogleLoginScreen(),
          ),
        ),
      ),
    );
  }

  void _openProfileFromHeader() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      AppNavigation.openProfile(context);
    } else {
      _showLoginDialog();
    }
  }

  void _openOrdersFromHeader() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      AppNavigation.openOrders(context);
    } else {
      _showLoginDialog();
    }
  }

  void _onHomeSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      if (!_homeSearch.value.isSearching &&
          _homeSearch.value.results.isEmpty) {
        return;
      }
      _homeSearch.value = _HomeSearchSnapshot.empty;
      return;
    }
    _homeSearch.value = _HomeSearchSnapshot(
      isSearching: true,
      results: _allSearchProducts.where((item) {
        return item.name.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query) ||
            item.category.toLowerCase().contains(query);
      }).toList(),
    );
  }

  void _clearHomeSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    _homeSearch.value = _HomeSearchSnapshot.empty;
  }

  double _homeContentMaxWidth(BuildContext context) =>
      ResponsiveHelper.contentMaxWidth(context);

  double _homeHorizontalPadding(BuildContext context) =>
      ResponsiveHelper.horizontalPadding(context);

  double _homeSliverSidePadding(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final maxW = _homeContentMaxWidth(context);
    final hPad = _homeHorizontalPadding(context);
    if (screenW <= maxW) return hPad;
    return (screenW - maxW) / 2 + hPad;
  }

  double _homeGridWidth(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final maxW = _homeContentMaxWidth(context);
    final hPad = _homeHorizontalPadding(context);
    final contentW = screenW > maxW ? maxW : screenW;
    return contentW - (2 * hPad);
  }

  Widget _homeWidthLimited(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.contentMaxWidth(context),
        ),
        child: child,
      ),
    );
  }

  void _onMenuDataChanged() {
    if (_menuController.isLoading) return;
    final cats = _menuController.categories;
    if (cats.isNotEmpty &&
        (_homeSelectedCategory.isEmpty ||
            !cats.contains(_homeSelectedCategory))) {
      _homeSelectedCategory = cats.first;
      _homeSelectedCategoryListenable.value = cats.first;
    }
    _syncBannerTimer();
  }

  void _onExploreMenuFromCart() {
    if (!mounted) return;
    final cats = _menuController.categories;
    if (cats.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollHomeToCategory(cats.first);
    });
  }

  int get _topScrollBannerCount =>
      _promoBanners.scrollableBanners.length + _menuController.bannerCount;

  bool get _hasTopScrollBanners => _topScrollBannerCount > 0;

  /// Top carousel: Firestore website scrollable + item website banners.
  List<Object> get _mergedScrollBannerSlides => [
        ..._promoBanners.scrollableBanners,
        ..._menuController.bannerItems,
      ];

  /// Start / restart / stop auto-scroll based on current banner count.
  void _syncBannerTimer() {
    final itemCount = _topScrollBannerCount;
    if (itemCount < 2) {
      // 0–1 banners: nothing to scroll, stop timer
      _timer?.cancel();
      _timer = null;
      return;
    }

    _startBannerTimer();
  }

  void _startBannerTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (!mounted) return;
      if (_isUserHoldingBanner) return;
      if (_lastManualScrollTime != null &&
          DateTime.now().difference(_lastManualScrollTime!).inSeconds < 20) {
        return;
      }

      // Always use live count (promo vs menu can change after timer started)
      final itemCount = _topScrollBannerCount;
      if (itemCount < 2) {
        timer.cancel();
        _timer = null;
        return;
      }

      var current = _menuController.bannerCurrentPage.value;
      if (current >= itemCount) {
        current = 0;
        _menuController.bannerCurrentPage.value = 0;
      }

      final nextPage = (current + 1) % itemCount;
      _menuController.bannerCurrentPage.value = nextPage;
      context.read<HomeBannerController>().setCurrentPage(nextPage);

      void animate() {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeIn,
        );
      }

      if (_pageController.hasClients) {
        animate();
      } else {
        // PageView may not be attached yet (tab / first build) — retry next frame
        WidgetsBinding.instance.addPostFrameCallback((_) => animate());
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _promoBanners.removeListener(_syncBannerTimer);
    FirestoreService.menuDataVersion.removeListener(
      _menuController.onCacheUpdated,
    );
    FirestoreService.menuDataVersion.removeListener(_reloadSearchCatalog);
    _menuController.removeListener(_onMenuDataChanged);
    _searchController.removeListener(_onHomeSearchChanged);
    HomeScrollToMenu.instance.removeListener(_onExploreMenuFromCart);
    _menuController.dispose();
    _pageController.dispose();
    _homeCategoryTabScroll.dispose();
    _homeScrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _homeSelectedCategoryListenable.dispose();
    _homeSearch.dispose();
    _isDrawerSigningIn.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildHomeShimmer(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header Shimmer
            SafeArea(
              bottom: false,
              child: Container(
                color: AppColors.matteBlack,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.menu, color: Colors.white, size: 28),
                    const BrandImage(
                      assetPath: 'assets/zanfuwhitelogo.png',
                      height: 30,
                    ),
                    const Icon(
                      AppCartIcons.outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),

            // Location Bar Shimmer
            Container(
              color: AppColors.matteBlack,
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Shimmer.rectangular(width: 150, height: 14),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Banner Shimmer (2:1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: ResponsiveHelper.bannerAspectRatio(context),
                  child: const Shimmer.rectangular(
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Category tabs shimmer
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 5,
                itemBuilder: (_, __) => const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: Shimmer.rectangular(width: 72, height: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Menu grid shimmer
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.horizontalPadding(context),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final extent = ResponsiveHelper.homeGridMainAxisExtent(
                    context,
                    constraints.maxWidth,
                  );
                  return GridView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: ResponsiveHelper.homeGridColumns(context),
                      mainAxisExtent: extent,
                      mainAxisSpacing:
                          ResponsiveHelper.homeGridMainSpacing(context),
                      crossAxisSpacing:
                          ResponsiveHelper.homeGridCrossSpacing(context),
                    ),
                    itemCount: 8,
                    itemBuilder: (context, index) {
                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Shimmer.rectangular(
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                            SizedBox(height: 8),
                            Shimmer.rectangular(width: 50, height: 10),
                            SizedBox(height: 6),
                            Shimmer.rectangular(width: 36, height: 10),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildZanfuHeader() {
    final topPad = ResponsiveHelper.isMobile(context) ? 12.0 : 0.0;
    return Padding(
      padding: EdgeInsets.only(top: topPad),
      child: ZanfuAppHeader(
        onProfileTap: _openProfileFromHeader,
        onOrdersTap: _openOrdersFromHeader,
        onCartTap: () => AppNavigation.openCart(context),
        onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_menuController, _promoBanners]),
      builder: (context, _) {
        if (_menuController.isLoading) {
          return CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildZanfuHeader()),
              SliverToBoxAdapter(child: _buildHomeShimmer(context)),
            ],
          );
        }

        final displayCats = _menuController.categories;
        if (_homeSelectedCategory.isEmpty && displayCats.isNotEmpty) {
          _homeSelectedCategory = displayCats.first;
          _homeSelectedCategoryListenable.value = displayCats.first;
        }
        for (final cat in displayCats) {
          _homeCategoryKeys.putIfAbsent(cat, GlobalKey.new);
        }

        final isDynamicBanners = _hasTopScrollBanners;
        final bannerCount = _topScrollBannerCount;
        final scrollSlides = _mergedScrollBannerSlides;
        final hintNames = _allSearchProducts
            .map((e) => e.name.trim())
            .where((n) => n.isNotEmpty)
            .toList(growable: false);

        return Container(
          color: AppColors.background,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onHomeScrollNotification,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: true,
                physics: const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
              ),
              child: CustomScrollView(
                controller: _homeScrollController,
                cacheExtent: 600,
                slivers: [
                SliverToBoxAdapter(child: _buildZanfuHeader()),
                if (isDynamicBanners)
                  SliverToBoxAdapter(
                    child: _buildHomeBannerCarousel(
                      bannerCount: bannerCount,
                      scrollSlides: scrollSlides,
                    ),
                  )
                else
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                if (displayCats.isNotEmpty)
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                if (displayCats.isNotEmpty)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _HomeStickyCategoryTabsDelegate(
                      height:
                          ResponsiveHelper.stickyCategoryTabsHeight(context),
                      categories: displayCats,
                      selectedListenable: _homeSelectedCategoryListenable,
                      tabScrollController: _homeCategoryTabScroll,
                      onSelect: (category) {
                        AppHaptics.selection();
                        _scrollHomeToCategory(category);
                      },
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _homeWidthLimited(
                    ValueListenableBuilder<_HomeSearchSnapshot>(
                      valueListenable: _homeSearch,
                      builder: (context, search, _) {
                        return HomeTypewriterSearchField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          showClear: search.isSearching,
                          onClear: _clearHomeSearch,
                          hintNames: hintNames,
                        );
                      },
                    ),
                  ),
                ),
                ValueListenableBuilder<_HomeSearchSnapshot>(
                  valueListenable: _homeSearch,
                  builder: (context, search, _) {
                    if (search.isSearching) {
                      return SliverMainAxisGroup(
                        slivers: _homeSearchResultSlivers(search.results),
                      );
                    }
                    if (displayCats.isEmpty) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }
                    return SliverMainAxisGroup(
                      slivers: [
                        ..._homeCategorySlivers(displayCats),
                        SliverToBoxAdapter(
                          child: ValueListenableBuilder<int>(
                            valueListenable: FirestoreService.branchesDataVersion,
                            builder: (context, _, __) => _buildHomeFooter(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  bool _onHomeScrollNotification(ScrollNotification notification) {
    if (_isHomeAutoScrolling || _homeSearch.value.isSearching) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _updateHomeCategoryFromScroll();
    }
    return false;
  }

  Widget _buildHomeBannerCarousel({
    required int bannerCount,
    required List<Object> scrollSlides,
  }) {
    return Consumer<HomeBannerController>(
      builder: (context, bannerController, child) {
        // Near full-bleed banner — minimal side inset.
        final bannerPad = 4.0;
        final bannerHeight =
            (MediaQuery.sizeOf(context).width - (bannerPad * 2)) /
                ResponsiveHelper.bannerAspectRatio(context);
        final page = bannerController.currentPage.clamp(0, bannerCount - 1);
        // Arrows only on desktop/laptop — not mobile or tablet.
        final showArrows =
            ResponsiveHelper.isDesktop(context) && bannerCount > 1;
        final showLeft = showArrows && page > 0;
        final showRight = showArrows && page < bannerCount - 1;

        final isMobile = MediaQuery.sizeOf(context).width < 600;
        final dotSize = isMobile ? 5.0 : 8.0;
        final activeWidth = isMobile ? 14.0 : 20.0;
        final padH = isMobile ? 8.0 : 10.0;
        final padV = isMobile ? 4.0 : 6.0;

        void goTo(int target) {
          if (!_pageController.hasClients) return;
          _lastManualScrollTime = DateTime.now();
          final clamped = target.clamp(0, bannerCount - 1);
          _pageController.animateToPage(
            clamped,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        }

        Widget arrow({required bool left}) {
          final small = ResponsiveHelper.isSmallMobile(context);
          final size = small ? 30.0 : 36.0;
          return Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 3,
            shadowColor: Colors.black45,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => goTo(left ? page - 1 : page + 1),
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  left
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  color: AppColors.matteBlack,
                  size: small ? 20 : 24,
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: bannerPad),
              child: SizedBox(
                height: bannerHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification notification) {
                        if (notification is ScrollStartNotification && notification.dragDetails != null) {
                          _isUserHoldingBanner = true;
                        } else if (notification is ScrollEndNotification) {
                          if (_isUserHoldingBanner) {
                            _isUserHoldingBanner = false;
                            _lastManualScrollTime = DateTime.now();
                          }
                        }
                        return false;
                      },
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: bannerCount,
                        onPageChanged: (int next) {
                          bannerController.setCurrentPage(next);
                          _menuController.bannerCurrentPage.value = next;
                        },
                        itemBuilder: (context, index) {
                          final slide = scrollSlides[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Material(
                              elevation: 4,
                              shadowColor: Colors.black54,
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: slide is PromotionalBanner
                                  ? _buildPromoBannerTile(
                                      slide,
                                      height: bannerHeight,
                                    )
                                  : _buildProductBannerTile(
                                      slide as FoodMenuItem,
                                      height: bannerHeight,
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (showLeft)
                      Positioned(
                        left: 8,
                        child: arrow(left: true),
                      ),
                    if (showRight)
                      Positioned(
                        right: 8,
                        child: arrow(left: false),
                      ),
                    if (bannerCount > 1)
                      Positioned(
                        bottom: isMobile ? 4 : 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                              color: Colors.black.withValues(alpha: 0.25),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(bannerCount, (i) {
                                  final isActive = i == page;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    margin: EdgeInsets.symmetric(horizontal: isMobile ? 3 : 4),
                                    width: isActive ? activeWidth : dotSize,
                                    height: dotSize,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AppColors.primary
                                          : Colors.white.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(dotSize / 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.3),
                                          blurRadius: 2,
                                          offset: const Offset(0, 1),
                                        )
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  List<Widget> _homeSearchResultSlivers(List<FoodMenuItem> searchResults) {
    if (searchResults.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _homeWidthLimited(
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 40, 16, 60),
              child: Column(
                children: [
                  Text(
                    'No Item Found',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Try a different search term',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final cats = _menuController.categories;
    final grouped = <String, List<FoodMenuItem>>{};
    for (final item in searchResults) {
      final cat = item.category.trim().isEmpty ? 'Other' : item.category;
      grouped.putIfAbsent(cat, () => []).add(item);
    }
    final orderedCats = [
      ...cats.where(grouped.containsKey),
      ...grouped.keys.where((c) => !cats.contains(c)),
    ];

    final slivers = <Widget>[];
    for (int i = 0; i < orderedCats.length; i++) {
      final cat = orderedCats[i];
      slivers.addAll(
        _homeProductGridSlivers(
          category: cat,
          items: grouped[cat] ?? const [],
          topPadding: i == 0
              ? 16
              : ResponsiveHelper.homeCategorySpacing(context),
        ),
      );
    }
    slivers.add(
      SliverToBoxAdapter(
        child: SizedBox(height: _homeHorizontalPadding(context)),
      ),
    );
    return slivers;
  }

  Widget _buildHomeCategoryTitle({
    required String category,
    required double topPadding,
    Key? key,
  }) {
    final sidePad = _homeSliverSidePadding(context);
    return Padding(
      key: key,
      padding: EdgeInsets.fromLTRB(sidePad, topPadding, sidePad, 20),
      child: Text(
        category,
        textAlign: TextAlign.start,
        style: TextStyle(
          fontSize: ResponsiveHelper.categoryTitleFontSize(context),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }

  List<Widget> _homeProductGridSlivers({
    required String category,
    required List<FoodMenuItem> items,
    required double topPadding,
    GlobalKey? categoryKey,
  }) {
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: _buildHomeCategoryTitle(
          category: category,
          topPadding: topPadding,
          key: categoryKey,
        ),
      ),
    ];

    if (items.isEmpty) {
      final hPad = _homeHorizontalPadding(context);
      final maxW = _homeContentMaxWidth(context);
      slivers.add(
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
                child: const Text(
                  'No items in this category yet.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
        ),
      );
      return slivers;
    }

    final cols = ResponsiveHelper.homeGridColumns(context);
    final gridWidth = _homeGridWidth(context);
    final extent = ResponsiveHelper.homeGridMainAxisExtent(context, gridWidth);
    final mainSpacing = ResponsiveHelper.homeGridMainSpacing(context);
    final crossSpacing = ResponsiveHelper.homeGridCrossSpacing(context);
    final sidePad = _homeSliverSidePadding(context);
    final itemWidth = (gridWidth - crossSpacing * (cols - 1)) / cols;
    final imageHeight =
        itemWidth * ResponsiveHelper.homeGridImageHeightRatio(context);

    slivers.add(
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: sidePad),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: extent,
            mainAxisSpacing: mainSpacing,
            crossAxisSpacing: crossSpacing,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final menuItem = items[i];
              final model = menuItem.toFoodModel();
              return ProductGridCard(
                model: model,
                imageHeight: imageHeight,
                onTap: () => _openHomeProduct(menuItem, model),
              );
            },
            childCount: items.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
          ),
        ),
      ),
    );
    return slivers;
  }



  void _updateHomeCategoryFromScroll() {
    if (_isHomeAutoScrolling || _homeSearch.value.isSearching) return;
    final cats = _menuController.categories;
    if (cats.isEmpty) return;

    String current = cats.first;
    final pinLine = MediaQuery.paddingOf(context).top +
        ResponsiveHelper.stickyCategoryTabsHeight(context) +
        4;
    for (final cat in cats) {
      final key = _homeCategoryKeys[cat];
      final ctx = key?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y <= pinLine) {
        current = cat;
      }
    }

    if (current != _homeSelectedCategory) {
      _homeSelectedCategory = current;
      _homeSelectedCategoryListenable.value = current;
    }
  }

  Future<void> _scrollHomeToCategory(String category) async {
    _isHomeAutoScrolling = true;
    try {
      final cats = _menuController.categories;
      _homeSelectedCategory = category;
      _homeSelectedCategoryListenable.value = category;

      final key = _homeCategoryKeys[category];
      final ctx = key?.currentContext;
      if (ctx == null || !_homeScrollController.hasClients) return;

      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;

      final dy = box.localToGlobal(Offset.zero).dy;
      final pinLine = MediaQuery.paddingOf(context).top +
          ResponsiveHelper.stickyCategoryTabsHeight(context);
      final delta = dy - pinLine;
      final target = (_homeScrollController.offset + delta).clamp(
        0.0,
        _homeScrollController.position.maxScrollExtent,
      );
      await _homeScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _isHomeAutoScrolling = false;
    }
  }

  List<Widget> _homeCategorySlivers(List<String> categories) {
    final catSpacing = ResponsiveHelper.homeCategorySpacing(context);
    final slivers = <Widget>[];
    for (int catIndex = 0; catIndex < categories.length; catIndex++) {
      final category = categories[catIndex];
      final items = _menuController.categoryItems[category] ?? const [];
      slivers.addAll(
        _homeProductGridSlivers(
          category: category,
          items: items,
          topPadding: catIndex == 0 ? 16 : catSpacing,
          categoryKey: _homeCategoryKeys[category],
        ),
      );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 20)));
    return slivers;
  }

  Widget _buildHomeFooter() {
    final wide = _isWideLayout(context);
    final screenW = MediaQuery.sizeOf(context).width;
    // Narrow laptop windows: stack like mobile so phone + links don't overlap.
    final compactWide = wide && screenW < 980;
    final hPad = wide
        ? (screenW < 900 ? 28.0 : (screenW < 1200 ? 36.0 : 40.0))
        : 16.0;
    final textSidePad = wide
        ? (screenW < 900 ? 24.0 : (screenW < 1200 ? 48.0 : 88.0))
        : 12.0;
    final branches = FirestoreService.getCachedBranches();
    final headingSize = wide ? (compactWide ? 24.0 : 28.0) : 20.0;
    final bodySize = wide ? (compactWide ? 14.0 : 14.5) : 13.0;

    Widget footerLinks({bool center = false}) {
      return Column(
        crossAxisAlignment:
            center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          _FooterLink(
            label: 'FAQs',
            onTap: () => AppNavigation.openFaqs(context),
          ),
          const SizedBox(height: 8),
          _FooterLink(
            label: 'Privacy Policy',
            onTap: () => AppNavigation.openPrivacyPolicy(context),
          ),
          const SizedBox(height: 8),
          _FooterLink(
            label: 'Terms & Conditions',
            onTap: () => AppNavigation.openTermsConditions(context),
          ),
        ],
      );
    }

    Widget contactBlock() {
      return ListenableBuilder(
        listenable: _appConfig,
        builder: (context, _) {
          final livePhone = _appConfig.customerSupportNumber.trim();
          return Column(
            crossAxisAlignment:
                wide && !compactWide
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
            children: [
              if (livePhone.isNotEmpty || (wide && !compactWide)) ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stackPhoneLinks =
                        compactWide || constraints.maxWidth < 460;
                    final phoneRow = livePhone.isEmpty
                        ? const SizedBox.shrink()
                        : Row(
                            mainAxisAlignment: stackPhoneLinks
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.start,
                            children: [
                              const Text(
                                'Phone',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  livePhone,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.88),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          );

                    if (stackPhoneLinks) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (livePhone.isNotEmpty) phoneRow,
                          if (wide) ...[
                            if (livePhone.isNotEmpty)
                              const SizedBox(height: 16),
                            footerLinks(center: true),
                          ],
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (livePhone.isNotEmpty)
                          Expanded(child: phoneRow)
                        else
                          const Spacer(),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: screenW >= 1200 ? 48 : 12,
                              ),
                              child: footerLinks(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'Branches Address',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (branches.isEmpty)
                Text(
                  'Addresses coming soon',
                  textAlign:
                      wide && !compactWide ? TextAlign.start : TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13.5,
                  ),
                )
              else
                for (final b in branches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: wide && !compactWide
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        if ((b['name'] ?? '').toString().trim().isNotEmpty)
                          Text(
                            b['name'].toString().trim(),
                            textAlign: wide && !compactWide
                                ? TextAlign.start
                                : TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if ((b['address'] ??
                                b['address_line'] ??
                                b['location'] ??
                                '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          Text(
                            (b['address'] ??
                                    b['address_line'] ??
                                    b['location'])
                                .toString()
                                .trim(),
                            textAlign: wide && !compactWide
                                ? TextAlign.start
                                : TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                      ],
                    ),
                  ),
              const SizedBox(height: 18),
              if (!wide) footerLinks(center: true),
            ],
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Divider(color: AppColors.divider, thickness: 1, height: 1),
          const SizedBox(height: 28),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: textSidePad),
            child: Text(
              'Pizza, Burgers, Pasta, Crispy Fried Chicken & Fast Food Delivered Hot & Fresh!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: headingSize,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
          SizedBox(height: wide ? 28 : 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: textSidePad),
            child: Text(
              'Zanfu is a vibrant eatery where you can relish an extensive menu of fast food delights. From mouthwatering chicken specialties to a variety of other delectable options, our restaurant is dedicated to serving up flavorful meals that satisfy your cravings',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: bodySize,
                height: 1.5,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          SizedBox(height: wide ? (compactWide ? 28 : 44) : 28),
          if (wide && !compactWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 20),
                  child: BrandImage(
                    assetPath: 'assets/zanfu_logo.png',
                    height: 188,
                  ),
                ),
                const SizedBox(width: 56),
                Expanded(child: contactBlock()),
              ],
            )
          else ...[
            Center(
              child: BrandImage(
                assetPath: 'assets/zanfu_logo.png',
                height: compactWide ? 140 : 120,
              ),
            ),
            const SizedBox(height: 24),
            contactBlock(),
          ],
          const SizedBox(height: 56),
          const Divider(color: AppColors.divider, thickness: 1, height: 1),
          const SizedBox(height: 48),
          const Text(
            '@2026 Zanfu. All Rights Reserved',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Powered by KPDevs',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _openHomeProduct(FoodMenuItem menuItem, FoodModel model) {
    if (menuItem.isDeal) {
      DetailScreen.open(
        context,
        (asDialog) => DetailScreen(
          model: model,
          asDialog: asDialog,
          isDeal: true,
          dealGroups: menuItem.dealGroups,
          dealFixedItems: menuItem.dealFixedItems,
          dealModelQuantities: menuItem.dealModelQuantities,
          modelDisplayNames: menuItem.modelDisplayNames,
        ),
      );
    } else {
      DetailScreen.open(
        context,
        (asDialog) => DetailScreen(
          model: model,
          asDialog: asDialog,
          sizeModelUrls: menuItem.sizeModelUrls,
          sizeModelDisplayNames: menuItem.sizeModelDisplayNames,
          sizeSelectionLabel: menuItem.sizeSelectionLabel,
          dealModelTypesOrder: menuItem.dealModelTypesOrder,
          modelDisplayNames: menuItem.modelDisplayNames,
        ),
      );
    }
  }

  Widget _buildProductBannerTile(FoodMenuItem item, {double? height}) {
    final imageUrl = item.effectiveWebsiteBannerUrl;
    return GestureDetector(
      onTap: () {
        if (item.isDeal) {
          DetailScreen.open(
            context,
            (asDialog) => DetailScreen(
              model: item.toFoodModel(),
              asDialog: asDialog,
              isDeal: true,
              dealGroups: item.dealGroups,
              dealFixedItems: item.dealFixedItems,
              dealModelQuantities: item.dealModelQuantities,
              modelDisplayNames: item.modelDisplayNames,
            ),
          );
        } else {
          DetailScreen.open(
            context,
            (asDialog) => DetailScreen(
              model: item.toFoodModel(),
              asDialog: asDialog,
              sizeModelUrls: item.sizeModelUrls,
              sizeModelDisplayNames: item.sizeModelDisplayNames,
              sizeSelectionLabel: item.sizeSelectionLabel,
              dealModelTypesOrder: item.dealModelTypesOrder,
              modelDisplayNames: item.modelDisplayNames,
            ),
          );
        }
      },
      child: LocalCachedImage(
        imageUrl: imageUrl,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        placeholder: Shimmer.rectangular(
          width: double.infinity,
          height: height ?? double.infinity,
        ),
        errorWidget: Container(
          height: height,
          color: AppColors.primary.withValues(alpha: 0.08),
          child: const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: AppColors.textSecondary,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromoBannerTile(PromotionalBanner banner, {double? height}) {
    final image = LocalCachedImage(
      imageUrl: banner.imageUrl,
      width: double.infinity,
      height: height,
      fit: BoxFit.cover,
      placeholder: Shimmer.rectangular(
        width: double.infinity,
        height: height ?? double.infinity,
      ),
      errorWidget: Container(
        height: height,
        color: AppColors.primary.withValues(alpha: 0.08),
        child: const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: AppColors.textSecondary,
            size: 32,
          ),
        ),
      ),
    );

    if (banner.link == null || banner.link!.isEmpty) {
      return image;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ViewAllScreen(showBackButton: true),
          ),
        );
      },
      child: image,
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.68,
      backgroundColor: AppColors.matteBlack,
      child: SafeArea(
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          initialData: FirebaseAuth.instance.currentUser,
          builder: (context, authSnap) {
            final isLoggedIn = authSnap.data != null ||
                FirebaseAuth.instance.currentUser != null;
            return LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // Drawer Header
                      Container(
                        width: double.infinity,
                        color: AppColors.matteBlack,
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const BrandImage(
                              assetPath: 'assets/zanfu_logo.png',
                              height: 100,
                            ),
                            if (isLoggedIn) ...[
                              const SizedBox(height: 8),
                              ListenableBuilder(
                                listenable: _userProfileController,
                                builder: (context, _) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        _userProfileController.userName,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _userProfileController.userPhone,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              FlameGradientButton(
                                label: 'VIEW PROFILE',
                                onTap: () {
                                  Navigator.pop(context);
                                  AppNavigation.openProfile(context);
                                },
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Guest',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'To experience more features, please sign in with Google.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showLoginDialog();
                                  },
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.cardBackground,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.45),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const BrandImage(
                                          assetPath: 'assets/google_g_logo.png',
                                          width: 18,
                                          height: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Sign in with Google',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (isLoggedIn) ...[
                        _drawerItem(
                          Icons.inventory_2_outlined,
                          "Order History",
                          onTap: () {
                            Navigator.pop(context);
                            AppNavigation.openOrders(context);
                          },
                        ),
                        const Divider(
                          height: 1,
                          color: AppColors.divider,
                          indent: 16,
                          endIndent: 16,
                        ),
                      ],
                      if (isLoggedIn) ...[
                        const Divider(
                          height: 1,
                          color: AppColors.divider,
                          indent: 16,
                          endIndent: 16,
                        ),
                        _drawerItem(
                          Icons.logout_rounded,
                          "Logout",
                          showArrow: false,
                          onTap: () {
                            Navigator.pop(context);
                            _showLogoutDialog();
                          },
                        ),
                      ],
                      const Spacer(),
                      // Bottom contact us + footer
                      Column(
                        children: [
                          FlameGradientButton(
                            label: 'CONTACT US',
                            height: 50,
                            borderRadius: 10,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            onTap: () async {
                              Navigator.pop(context);
                              final ok =
                                  await _appConfig.dialCustomerSupport();
                              if (!ok && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Customer support number not available',
                                    ),
                                  ),
                                );
                              }
                            },
                            trailing: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: AppColors.matteBlack,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.phone_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                    AppNavigation.openTermsConditions(context);
                                  },
                                  child: Text(
                                    "Terms & Conditions",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  "V-3.0.6-U",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
          },
        ),
      ),
    );
  }

  /// Drawer closes first; sign-in runs in a dialog so the progress spinner
  /// stays visible on the faded barrier. Cancel/fail keeps the dialog open.
  Future<void> _showDrawerGoogleSignInDialog() async {
    _showLoginDialog();
    return;

    final signingIn = ValueNotifier(false);

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          Future<void> doSignIn() async {
            if (signingIn.value) return;
            signingIn.value = true;
            _isDrawerSigningIn.value = true;
            try {
              final user = await GoogleAuthHelper.signIn();
              if (user == null) {
                signingIn.value = false;
                return;
              }

              _userProfileController.resetSession();
              await _userProfileController.ensureLoaded();
              if (!mounted) return;

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            } catch (e) {
              debugPrint('MenuScreen drawer Google sign-in error: $e');
              signingIn.value = false;
              if (mounted) {
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
            } finally {
              _isDrawerSigningIn.value = false;
            }
          }

          return ValueListenableBuilder<bool>(
            valueListenable: signingIn,
            builder: (context, isSigningIn, _) {
              return AlertDialog(
                backgroundColor: AppColors.matteBlack,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 24,
                ),
                contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  'Sign in',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                content: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.88,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'To experience more features, please sign in with Google.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isSigningIn
                              ? null
                              : () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: isSigningIn ? null : doSignIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.matteBlack,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isSigningIn)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                )
                              else
                                const BrandImage(
                                  assetPath: 'assets/google_g_logo.png',
                                  width: 18,
                                  height: 18,
                                ),
                              const SizedBox(width: 8),
                              Text(
                                isSigningIn
                                    ? 'Signing in...'
                                    : 'Sign in with Google',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      signingIn.dispose();
    }
  }

  Future<void> _showLogoutDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.matteBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Logout',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Logout',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await GoogleAuthHelper.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MenuScreen(showLoginOnStart: true)),
        (route) => false,
      );
    }
  }

  Widget _drawerItem(
    IconData icon,
    String title, {
    VoidCallback? onTap,
    bool showArrow = true,
  }) {
    return InkWell(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
            if (showArrow)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 14,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = _isWideLayout(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.matteBlack,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.matteBlack,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: AppColors.matteBlack,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.matteBlack,
        drawer: wide ? null : _buildDrawer(),
        body: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          child: Stack(
            children: [
              Column(
                children: [
                  ColoredBox(
                    color: AppColors.matteBlack,
                    child: SizedBox(height: MediaQuery.paddingOf(context).top),
                  ),
                  Expanded(child: _buildHomeContent(context)),
                ],
              ),
              /* Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ListenableBuilder(
                  listenable: _cart,
                  builder: (context, _) {
                    if (_cart.items.isEmpty) return const SizedBox.shrink();
                    final screenW = MediaQuery.sizeOf(context).width;
                    final barMax = ResponsiveHelper.isTablet(context)
                        ? (screenW - 140).clamp(220.0, 320.0)
                        : (wide
                            ? (screenW * 0.34).clamp(260.0, 340.0)
                            : screenW - 56);
                    return SafeArea(
                      top: false,
                      child: ViewCartBottomBar(
                        cart: _cart,
                        maxWidth: barMax,
                        bottomInset: ResponsiveHelper.isTablet(context) ? 16 : (wide ? 22 : 16),
                        horizontalInset: 16,
                        height: 60,
                        imageBoxSize: 58,
                        imageSize: 52,
                        countFontSize: 14.5,
                        itemsLabelFontSize: 13,
                      ),
                    );
                  },
                ),
              ), */
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCategoryTabsBar extends StatefulWidget {
  final List<String> categories;
  final String selected;
  final ScrollController scrollController;
  final double height;
  final double fontSize;
  final ValueChanged<String> onSelect;

  const _HomeCategoryTabsBar({
    required this.categories,
    required this.selected,
    required this.scrollController,
    required this.height,
    required this.fontSize,
    required this.onSelect,
  });

  @override
  State<_HomeCategoryTabsBar> createState() => _HomeCategoryTabsBarState();
}

class _HomeCategoryTabsBarState extends State<_HomeCategoryTabsBar> {
  final GlobalKey _contentKey = GlobalKey();
  late List<GlobalKey> _tabKeys;
  final ValueNotifier<({double left, double width})> _pill =
      ValueNotifier((left: 0.0, width: 0.0));
  final ValueNotifier<({bool left, bool right})> _overflow =
      ValueNotifier((left: false, right: false));

  double get _gap => ResponsiveHelper.categoryTabGap(context);
  double get _pillHeight => ResponsiveHelper.categoryTabPillHeight(context);

  @override
  void initState() {
    super.initState();
    _tabKeys = List.generate(widget.categories.length, (_) => GlobalKey());
    widget.scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateOverflow();
      _updatePill();
      _scrollToActiveTab();
    });
  }

  @override
  void didUpdateWidget(covariant _HomeCategoryTabsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories.length != widget.categories.length) {
      _tabKeys = List.generate(widget.categories.length, (_) => GlobalKey());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateOverflow();
      _updatePill();
      _scrollToActiveTab();
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _pill.dispose();
    _overflow.dispose();
    super.dispose();
  }

  void _onScroll() => _updateOverflow();

  void _updateOverflow() {
    if (!widget.scrollController.hasClients) return;
    final pos = widget.scrollController.position;
    final left = pos.maxScrollExtent > 0 && pos.pixels > 8;
    final right =
        pos.maxScrollExtent > 0 && pos.pixels < pos.maxScrollExtent - 8;
    final cur = _overflow.value;
    if (left != cur.left || right != cur.right) {
      _overflow.value = (left: left, right: right);
    }
  }

  void _scrollToActiveTab() {
    if (!widget.scrollController.hasClients) return;
    final idx = widget.categories.indexOf(widget.selected);
    if (idx < 0 || idx >= _tabKeys.length) return;
    final tabCtx = _tabKeys[idx].currentContext;
    if (tabCtx == null) return;
    final tabBox = tabCtx.findRenderObject() as RenderBox?;
    if (tabBox == null || !tabBox.hasSize) return;

    final tabGlobalX = tabBox.localToGlobal(Offset.zero).dx;
    final tabWidth = tabBox.size.width;
    final screenWidth = MediaQuery.of(context).size.width;

    final currentOffset = widget.scrollController.offset;
    final tabCenter = tabGlobalX + (tabWidth / 2.0);
    final screenCenter = screenWidth / 2.0;
    final delta = tabCenter - screenCenter;

    final targetOffset = (currentOffset + delta).clamp(
      0.0,
      widget.scrollController.position.maxScrollExtent,
    );

    if ((targetOffset - currentOffset).abs() > 2.0) {
      widget.scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _updatePill() {
    final idx = widget.categories.indexOf(widget.selected);
    if (idx < 0 || idx >= _tabKeys.length) return;
    final tabCtx = _tabKeys[idx].currentContext;
    final contentCtx = _contentKey.currentContext;
    if (tabCtx == null || contentCtx == null) return;
    final tabBox = tabCtx.findRenderObject() as RenderBox?;
    final contentBox = contentCtx.findRenderObject() as RenderBox?;
    if (tabBox == null || contentBox == null || !tabBox.hasSize) return;
    final offset = tabBox.localToGlobal(Offset.zero, ancestor: contentBox);
    final nextLeft = offset.dx;
    final nextWidth = tabBox.size.width;
    final cur = _pill.value;
    if (nextLeft == cur.left && nextWidth == cur.width) return;
    _pill.value = (left: nextLeft, width: nextWidth);
  }

  void _scrollBy(double delta) {
    if (!widget.scrollController.hasClients) return;
    final target = (widget.scrollController.offset + delta).clamp(
      0.0,
      widget.scrollController.position.maxScrollExtent,
    );
    widget.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _arrow({required bool left}) {
    final small = ResponsiveHelper.isSmallMobile(context);
    final size = small ? 24.0 : 30.0;
    return Positioned(
      left: left ? 6 : null,
      right: left ? null : 6,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => _scrollBy(left ? -360 : 360),
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              color: AppColors.matteBlack,
              size: small ? 18 : 22,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ValueListenableBuilder<({bool left, bool right})>(
          valueListenable: _overflow,
          builder: (context, overflow, _) {
            return Stack(
              children: [
                ListView(
                  controller: widget.scrollController,
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: overflow.left || overflow.right
                        ? 36
                        : ResponsiveHelper.categoryTabBarPadding(context),
                  ),
                  children: [
                    SizedBox(
                      height: widget.height,
                      child: Stack(
                        key: _contentKey,
                        alignment: Alignment.centerLeft,
                        children: [
                          ValueListenableBuilder<({double left, double width})>(
                            valueListenable: _pill,
                            builder: (context, pill, _) {
                              if (pill.width <= 0) {
                                return const SizedBox.shrink();
                              }
                              return Positioned(
                                left: pill.left,
                                top: (widget.height - _pillHeight) / 2,
                                width: pill.width,
                                height: _pillHeight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              );
                            },
                          ),
                          Row(
                            children: [
                              for (int index = 0;
                                  index < widget.categories.length;
                                  index++) ...[
                                if (index > 0) SizedBox(width: _gap),
                                Builder(
                                  builder: (context) {
                                    final category = widget.categories[index];
                                    final selected =
                                        category == widget.selected;
                                    return _CategoryTabChip(
                                      measureKey: _tabKeys[index],
                                      label: category,
                                      selected: selected,
                                      height: widget.height,
                                      pillHeight: _pillHeight,
                                      fontSize: widget.fontSize,
                                      onTap: () => widget.onSelect(category),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (overflow.left) _arrow(left: true),
                if (overflow.right) _arrow(left: false),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeStickyCategoryTabsDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final List<String> categories;
  final ValueNotifier<String> selectedListenable;
  final ScrollController tabScrollController;
  final ValueChanged<String> onSelect;

  _HomeStickyCategoryTabsDelegate({
    required this.height,
    required this.categories,
    required this.selectedListenable,
    required this.tabScrollController,
    required this.onSelect,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ValueListenableBuilder<String>(
      valueListenable: selectedListenable,
      builder: (context, selected, _) {
        return _HomeCategoryTabsBar(
          categories: categories,
          selected: selected,
          scrollController: tabScrollController,
          height: height,
          fontSize: ResponsiveHelper.categoryTabFontSize(context),
          onSelect: onSelect,
        );
      },
    );
  }

  @override
  bool shouldRebuild(covariant _HomeStickyCategoryTabsDelegate oldDelegate) {
    return height != oldDelegate.height ||
        !listEquals(categories, oldDelegate.categories);
  }
}

class _CategoryTabChip extends StatelessWidget {
  final GlobalKey measureKey;
  final String label;
  final bool selected;
  final double height;
  final double pillHeight;
  final double fontSize;
  final VoidCallback onTap;

  const _CategoryTabChip({
    required this.measureKey,
    required this.label,
    required this.selected,
    required this.height,
    required this.pillHeight,
    required this.fontSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Center(
            child: Container(
              key: measureKey,
              height: pillHeight,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.isMobile(context) ? 10 : 14,
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: AppColors.matteBlack,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterLink({required this.label, required this.onTap});

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  final ValueNotifier<bool> _hovered = ValueNotifier(false);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _hovered.value = true,
      onExit: (_) => _hovered.value = false,
      child: GestureDetector(
        onTap: widget.onTap,
        child: ValueListenableBuilder<bool>(
          valueListenable: _hovered,
          builder: (context, hovered, _) {
            return Text(
              widget.label,
              style: TextStyle(
                color: hovered ? AppColors.primary : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            );
          },
        ),
      ),
    );
  }
}
