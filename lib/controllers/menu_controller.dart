import 'package:flutter/foundation.dart';
import '../models/menu_item_model.dart';
import '../services/firestore_service.dart';

class MenuController extends ChangeNotifier {
  MenuController({int initialIndex = 0}) : _selectedIndex = initialIndex;

  bool _isLoading = true;
  List<String> _categories = [];
  List<FoodMenuItem> _bannerItems = [];
  Map<String, List<FoodMenuItem>> _categoryItems = {};
  int _selectedIndex = 0;
  final ValueNotifier<int> bannerCurrentPage = ValueNotifier(0);

  bool get isLoading => _isLoading;
  List<String> get categories => _categories;
  List<FoodMenuItem> get bannerItems => _bannerItems;
  Map<String, List<FoodMenuItem>> get categoryItems => _categoryItems;
  int get selectedIndex => _selectedIndex;
  bool get hasDynamicBanners => _bannerItems.isNotEmpty;
  int get bannerCount => _bannerItems.length;

  void onCacheUpdated() => loadMenuDataFromCache();

  void loadMenuDataFromCache() {
    try {
      final cats = FirestoreService.getCachedCategories();
      final List<String> nonEmptyCats = [];
      final List<FoodMenuItem> tempBannerItems = [];
      final Map<String, List<FoodMenuItem>> tempCategoryItems = {};

      for (var cat in cats) {
        final products = FirestoreService.getCachedProductsByCategory(cat);
        // Skip categories with zero products — don't show on home Explore Menu
        if (products.isEmpty) continue;

        nonEmptyCats.add(cat);
        tempCategoryItems[cat] = products;
        for (var p in products) {
          if (p.hasWebsiteBanner) {
            tempBannerItems.add(p);
          }
        }
      }

      final hasData = nonEmptyCats.isNotEmpty;

      _categories = nonEmptyCats;
      _bannerItems = tempBannerItems;
      _categoryItems = tempCategoryItems;
      _isLoading = !hasData;
      for (var i = 0; i < tempBannerItems.length; i++) {
        final p = tempBannerItems[i];
        debugPrint(
          '  PRODUCT_WEBSITE_BANNER[$i] name=${p.name} id=${p.id} '
          'url=${p.effectiveWebsiteBannerUrl}',
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint("MenuController: Error loading cached menu data: $e");
    }
  }

  void stopLoadingIfStillLoading() {
    if (_isLoading) {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSelectedIndex(int index) {
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    notifyListeners();
  }

  int advanceBannerPage() {
    final count = bannerCount;
    if (count == 0) return 0;
    final current = bannerCurrentPage.value;
    final next = current < count - 1 ? current + 1 : 0;
    bannerCurrentPage.value = next;
    return next;
  }

  @override
  void dispose() {
    bannerCurrentPage.dispose();
    super.dispose();
  }
}
