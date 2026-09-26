import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../utils/responsive_helper.dart';
import '../utils/app_navigation.dart';
import '../models/food_model.dart';
import '../models/menu_item_model.dart';
import '../services/firestore_service.dart';
import '../widgets/custom_header.dart';
import '../widgets/product_grid_card.dart';
import '../widgets/product_image_container.dart';
import '../widgets/shimmer.dart';
import 'detail_screen.dart';
import '../controllers/cart_controller.dart';
import '../controllers/bottom_nav_controller.dart';

class ViewAllScreen extends StatefulWidget {
  final bool showBackButton;
  final String? initialCategory;
  final bool isTab;

  const ViewAllScreen({
    super.key,
    this.showBackButton = true,
    this.initialCategory,
    this.isTab = false,
  });

  @override
  State<ViewAllScreen> createState() => _ViewAllScreenState();
}

class _ViewAllScreenState extends State<ViewAllScreen> {
  String selectedCategory = 'All';
  List<String> categories = [];
  final ScrollController _scrollController = ScrollController();
  final ScrollController _tabScrollController = ScrollController();
  final CartController _cart = CartController();

  Map<String, List<FoodModel>> _categoryMap = {};
  List<String> _orderedCategories = [];
  List<FoodMenuItem> _allItems = [];
  bool _isAutoScrolling = false;
  bool _isLoading = true;
  BottomNavController? _bottomNav;

  static const double categoryHeaderHeight = 36.0; // title (~20) + gap (16)
  static const double categorySpacing = 28.0;
  static const double categoryBottomSpacing = 0.0;
  static const double gridMainSpacing = 48.0;
  static const double gridCrossSpacing = 28.0;
  static const double gridHorizontalPadding = 32.0; // 16 * 2
  // Higher = shorter card. Tuned so text (name/desc/price) fits with little
  // empty space under Rs, including discounted strike-through line.
  // Room for name + 2-line description + price without overflow.
  static const double gridChildAspectRatio = 0.72;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    FirestoreService.menuDataVersion.addListener(_onCacheUpdated);
    _loadMenuFromCache();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bottomNav = context.read<BottomNavController>();
      _bottomNav?.addListener(_onBottomNavChanged);
      _applyPendingCategoryFromNav();
    });

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _onBottomNavChanged() {
    _applyPendingCategoryFromNav();
  }

  void _applyPendingCategoryFromNav() {
    if (!mounted) return;
    final nav = context.read<BottomNavController>();
    final pending = nav.pendingMenuCategory;
    if (pending == null || pending.isEmpty) return;
    if (categories.isEmpty || !categories.contains(pending)) return;

    nav.clearPendingMenuCategory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToCategory(pending);
    });
  }

  void _onCacheUpdated() {
    if (mounted) {
      _loadMenuFromCache();
    }
  }

  void _loadMenuFromCache() {
    try {
      final cats = FirestoreService.getCachedCategories();
      final List<FoodMenuItem> tempAllItems = [];
      final Map<String, List<FoodModel>> tempCategoryMap = {};
      final List<String> tempOrderedCategories = [];

      for (var cat in cats) {
        final products = FirestoreService.getCachedProductsByCategory(cat);
        if (products.isNotEmpty) {
          tempOrderedCategories.add(cat);
          tempCategoryMap[cat] =
              products.map((item) => item.toFoodModel()).toList();
          tempAllItems.addAll(products);
        }
      }

      final hasData = tempOrderedCategories.isNotEmpty;

      setState(() {
        _orderedCategories = tempOrderedCategories;
        _categoryMap = tempCategoryMap;
        _allItems = tempAllItems;
        categories = tempOrderedCategories;
        if (selectedCategory == 'All' && tempOrderedCategories.isNotEmpty) {
          selectedCategory =
              widget.initialCategory ?? tempOrderedCategories.first;
        }
        _isLoading = !hasData;
      });

      if (hasData) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _applyPendingCategoryFromNav();
          if (widget.initialCategory != null &&
              categories.contains(widget.initialCategory)) {
            _scrollToCategory(widget.initialCategory!);
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading cached menu in ViewAllScreen: $e");
    }
  }

  double _gridItemHeight(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final gridWidth = screenWidth - gridHorizontalPadding;
    return ResponsiveHelper.homeGridMainAxisExtent(context, gridWidth);
  }

  double _categoryBlockHeight(BuildContext context, List<FoodModel> items) {
    if (items.isEmpty) {
      return categoryHeaderHeight + categoryBottomSpacing;
    }
    final cols = ResponsiveHelper.homeGridColumns(context);
    final rows = (items.length / cols).ceil();
    final itemsHeight =
        rows * _gridItemHeight(context) + (rows - 1) * gridMainSpacing;
    return categoryHeaderHeight + itemsHeight + categoryBottomSpacing;
  }

  double _offsetForCategory(String category) {
    double offset = 0.0;
    for (int i = 0; i < _orderedCategories.length; i++) {
      final cat = _orderedCategories[i];
      if (cat == category) break;
      final items = _categoryMap[cat] ?? [];
      final double spacing = (i == 0) ? 0.0 : categorySpacing;
      offset += spacing + _categoryBlockHeight(context, items);
    }
    return offset;
  }

  @override
  void dispose() {
    _bottomNav?.removeListener(_onBottomNavChanged);
    FirestoreService.menuDataVersion.removeListener(_onCacheUpdated);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _tabScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isAutoScrolling) return;
    if (!mounted || _orderedCategories.isEmpty) return;

    final double offset = _scrollController.offset;
    String current = _orderedCategories.first;

    for (var cat in _orderedCategories) {
      double catOffset = _offsetForCategory(cat);
      if (offset >= catOffset - 15) {
        current = cat;
      }
    }

    if (selectedCategory != current) {
      setState(() {
        selectedCategory = current;
      });
      _scrollToActiveTab(current);
    }
  }

  void _scrollToActiveTab(String category) {
    if (!_tabScrollController.hasClients) return;
    final int index = categories.indexOf(category);
    if (index == -1) return;

    final double screenWidth = MediaQuery.of(context).size.width;
    final double targetOffset = (index * 95.0) - (screenWidth / 2.0) + 47.5;
    final double clampedOffset = targetOffset.clamp(
      0.0,
      _tabScrollController.position.maxScrollExtent,
    );

    _tabScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  /// Category types strip. Kept OUT of the vertical [CustomScrollView] and,
  /// on the menu tab, mounted as [Scaffold.appBar] so iOS does not route
  /// touches to the body scroller.
  Widget _buildCategoryTypesBar() {
    return Material(
      color: AppColors.matteBlack,
      child: SizedBox(
        height: 60,
        width: double.infinity,
        child: ListView.builder(
          controller: _tabScrollController,
          scrollDirection: Axis.horizontal,
          primary: false,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final isSelected = category == selectedCategory;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _scrollToCategory(category),
              child: Container(
                height: 60,
                margin: const EdgeInsets.only(right: 20),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      category,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isSelected)
                      Container(
                        height: 3,
                        width: 28,
                        decoration: BoxDecoration(
                          gradient: AppColors.flameGradient,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    else
                      const SizedBox(height: 3),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _scrollToCategory(String category) {
    setState(() => selectedCategory = category);
    _scrollToActiveTab(category);

    _isAutoScrolling = true;
    _scrollController
        .animateTo(
          _offsetForCategory(category),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        )
        .then((_) => _isAutoScrolling = false);
  }

  Widget _buildViewAllShimmer() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 60,
            color: AppColors.matteBlack,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: const Shimmer.rectangular(width: 90, height: 36),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: gridChildAspectRatio,
                mainAxisSpacing: gridMainSpacing,
                crossAxisSpacing: gridCrossSpacing,
              ),
              itemBuilder: (_, __) => Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(10),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Shimmer.rectangular(
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                    SizedBox(height: 10),
                    Shimmer.rectangular(width: 90, height: 12),
                    SizedBox(height: 8),
                    Shimmer.rectangular(width: 60, height: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CartController>(
      builder: (context, cart, child) {
        final bool hasCartItems = cart.items.isNotEmpty;
        final CartItem? lastAddedItem = hasCartItems ? cart.items.last : null;

        final menuScroll = CustomScrollView(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          cacheExtent: 1000,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(top: 0, bottom: 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, catIndex) {
                    final cat = _orderedCategories[catIndex];
                    final items = _categoryMap[cat] ?? [];

                    return Padding(
                      padding: EdgeInsets.only(
                        top: catIndex == 0 ? 12 : categorySpacing,
                      ),
                      child: Container(
                        width: double.infinity,
                        color: AppColors.matteBlack,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(
                                cat,
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.fontSize(
                                    context,
                                    20,
                                  ),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                  color: Colors.white,
                                  height: 1.0,
                                ),
                                textHeightBehavior: const TextHeightBehavior(
                                  applyHeightToFirstAscent: false,
                                  applyHeightToLastDescent: false,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                              child: GridView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: items.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount:
                                      ResponsiveHelper.homeGridColumns(context),
                                  mainAxisExtent:
                                      ResponsiveHelper.homeGridMainAxisExtent(
                                    context,
                                    MediaQuery.sizeOf(context).width -
                                        gridHorizontalPadding,
                                  ),
                                  mainAxisSpacing: gridMainSpacing,
                                  crossAxisSpacing: gridCrossSpacing,
                                ),
                                itemBuilder: (context, i) {
                                  return _buildGridItem(context, items[i]);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _orderedCategories.length,
                ),
              ),
            ),
          ],
        );

        final bodyStack = Stack(
          children: [
            Positioned.fill(child: menuScroll),
            if (hasCartItems && lastAddedItem != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => AppNavigation.openCart(context),
                  child: Container(
                    height: 64,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      border: const Border(
                        top: BorderSide(color: AppColors.border),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 15,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        ProductImageContainer(
                          imagePath: lastAddedItem.foodModel.imagePath,
                          width: 48,
                          height: 48,
                          imageSize: 40,
                          borderRadius: 8,
                          backgroundColor: AppColors.surfaceElevated,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "${cart.totalItemsCount}",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1.1,
                                ),
                              ),
                              const Text(
                                "Items",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: AppColors.flameGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Rs ${_calcCartTotal()}",
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 20),
                              const Text(
                                "VIEW CART",
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.onPrimary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.keyboard_double_arrow_right_rounded,
                                size: 18,
                                color: AppColors.onPrimary,
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
        );

        return Scaffold(
          backgroundColor: AppColors.scaffoldBackground,
          // Types bar as AppBar on menu tab = separate hit-test layer from body
          // vertical scroller (fixes iOS touch on the horizontal types strip).
          appBar: (widget.isTab
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: _buildCategoryTypesBar(),
                )
              : CustomHeader(
                  title: "Explore Menu",
                  subtitle: "",
                  showBackButton: widget.showBackButton,
                  showSearchIcon: true,
                  showCartIcon: true,
                  onSearchTap: () => AppNavigation.openSearch(context),
                )) as PreferredSizeWidget,
          body: _isLoading
              ? _buildViewAllShimmer()
              : widget.isTab
                  ? bodyStack
                  : Column(
                      children: [
                        _buildCategoryTypesBar(),
                        Expanded(child: bodyStack),
                      ],
                    ),
        );
      },
    );
  }

  int _calcCartTotal() {
    int total = 0;
    for (var item in _cart.items) {
      double original = 0;
      final priceStr = item.foodModel.price;
      final variation = item.selectedVariation?.trim().toLowerCase() ?? '';
      if (priceStr.contains('|')) {
        if (variation.isNotEmpty) {
          for (final part in priceStr.split('|')) {
            final clean = part.trim();
            final match =
                RegExp(r'^(.+?)\s+(\d+(?:\.\d+)?)\s*$').firstMatch(clean);
            if (match == null) continue;
            var name = match.group(1)!.trim().toLowerCase();
            name = name.replaceAll(RegExp(r'\b(rs|pkr)\b'), '').trim();
            if (name == 's') name = 'small';
            if (name == 'm') name = 'medium';
            if (name == 'l') name = 'large';
            if (name == variation ||
                name.startsWith(variation) ||
                variation.startsWith(name)) {
              original = double.tryParse(match.group(2)!) ?? 0;
              break;
            }
          }
        }
        if (original <= 0) {
          original = item.foodModel.displayOriginalPrice;
        }
      } else {
        original = item.foodModel.displayOriginalPrice;
      }
      total +=
          item.foodModel.discountedFrom(original).round() * item.quantity;
    }
    return total;
  }

  Widget _buildGridItem(BuildContext context, FoodModel model) {
    return ProductGridCard(
      model: model,
      onTap: () {
        final matches = _allItems.where((item) => item.name == model.name);
        if (matches.isNotEmpty) {
          final FoodMenuItem menuItem = matches.first;
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
        } else {
          DetailScreen.open(
            context,
            (asDialog) => DetailScreen(model: model, asDialog: asDialog),
          );
        }
      },
    );
  }
}
