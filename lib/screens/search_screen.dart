import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/explore_menu_card.dart';
import '../widgets/suggested_product_card.dart';
import '../widgets/discount_badge.dart';
import '../services/firestore_service.dart';
import '../models/menu_item_model.dart';
import '../models/food_model.dart';
import 'detail_screen.dart';
import '../widgets/shimmer.dart';
import '../widgets/brand_image.dart';

class SearchScreen extends StatefulWidget {
  final bool isTab;
  const SearchScreen({super.key, this.isTab = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<FoodMenuItem> _popularItems = [];
  List<FoodMenuItem> _allProducts = [];
  List<FoodMenuItem> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    FirestoreService.menuDataVersion.addListener(_onCacheUpdated);
    _loadPopularItems();
    _loadAllProducts();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    FirestoreService.menuDataVersion.removeListener(_onCacheUpdated);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCacheUpdated() {
    if (mounted) {
      _loadPopularItems();
      _loadAllProducts();
    }
  }

  void _loadAllProducts() {
    final cats = FirestoreService.getCachedCategories();
    final List<FoodMenuItem> temp = [];
    for (var cat in cats) {
      temp.addAll(FirestoreService.getCachedProductsByCategory(cat));
    }
    setState(() {
      _allProducts = temp;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    } else {
      setState(() {
        _searchResults = _allProducts.where((item) {
          return item.name.toLowerCase().contains(query) ||
                 item.description.toLowerCase().contains(query) ||
                 item.category.toLowerCase().contains(query);
        }).toList();
        _isSearching = true;
      });
    }
  }

  void _loadPopularItems() {
    setState(() {
      _popularItems = FirestoreService.getRandomCachedMenuItems(count: 15);
    });
  }

  void _navigateToDetail(FoodMenuItem item) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: widget.isTab
          ? null
          : CustomHeader(
              title: "Find Food of Zanfu",
              subtitle: "",
              showBackButton: Navigator.canPop(context),
              showSearchIcon: false,
              showCartIcon: true,
            ),
      body: GestureDetector(
        onTap: () => _focusNode.unfocus(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: "Search your favorite items",
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Colors.white,
                      size: 20,
                    ),
                    suffixIcon: _isSearching
                        ? IconButton(
                            icon: Icon(
                              Icons.close,
                              color: AppColors.textSecondary,
                              size: 18,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _focusNode.unfocus();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),

            // Body: search results OR default content
            Expanded(
              child: _isSearching
                  ? _buildSearchResults()
                  : _buildDefaultContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandImage(assetPath: 'assets/zanfu_logo.png', height: 120),
            const SizedBox(height: 20),
            const Text(
              "No results found",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.heading,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Try a different search term",
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 0.8,
        color: AppColors.divider,
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        final model = item.toFoodModel();
        final original = model.displayOriginalPrice;
        final hasDisc = model.hasDiscount && original > 0;
        final priceLabel = original > 0
            ? (hasDisc
                ? 'Rs ${model.discountedFrom(original).toInt()}'
                : 'Rs ${original.toInt()}')
            : _cleanPrice(model.price);

        return InkWell(
          onTap: () => _navigateToDetail(item),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                Stack(
                  children: [
                    ProductImageWithDiscount(
                      imagePath: model.imagePath,
                      width: 72,
                      height: 72,
                      imageSize: 58,
                      borderRadius: 10,
                      backgroundColor: AppColors.surfaceElevated,
                      discountLabel:
                          hasDisc ? model.discountBadgeLabel : null,
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.heading,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        model.category,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            priceLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          if (hasDisc) ...[
                            const SizedBox(width: 6),
                            Text(
                              'Rs ${original.toInt()}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _cleanPrice(String price) {
    final variations = FoodModel.parsePriceVariations(price);
    if (variations.isNotEmpty) {
      return 'From Rs ${variations.first.price.toInt()}';
    }
    return price.replaceAll('PKR ', 'Rs ').replaceAll('PKR', 'Rs');
  }

  Widget _buildDefaultContent() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              "Popular Searches",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),

          // Horizontal popular tiles — height matches SuggestedProductCard (96).
          SizedBox(
            height: 96,
            child: _popularItems.isEmpty
                ? ListView.builder(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.only(left: 16, right: 16),
                    itemCount: 4,
                    itemBuilder: (context, index) => Container(
                      width: 165,
                      height: 96,
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border, width: 0.8),
                      ),
                      child: Row(
                        children: const [
                          Shimmer.rectangular(width: 80, height: 80),
                          SizedBox(width: 8),
                          Expanded(
                            child: Shimmer.rectangular(width: 40, height: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.only(left: 16, right: 16),
                    itemCount: _popularItems.length,
                    itemBuilder: (context, index) {
                      final item = _popularItems[index];
                      return SuggestedProductCard(
                        item: item.toFoodModel(),
                        onTap: () => _navigateToDetail(item),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 25),

          // Explore More Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ExploreMenuCard(),
          ),

          const SizedBox(height: 30),

          // Logo
          Center(
            child: Column(
              children: [
                const BrandImage(
                  assetPath: 'assets/zanfu_logo.png',
                  height: 140,
                ),
                const SizedBox(height: 20),
                Text(
                  "Search for your favourite food!",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
