import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../controllers/favorites_controller.dart';
import '../models/food_model.dart';
import '../models/menu_item_model.dart';
import '../services/firestore_service.dart';
import '../widgets/custom_header.dart';
import '../widgets/product_row_card.dart';
import 'detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FavoritesController _favs = FavoritesController();

  @override
  void initState() {
    super.initState();
    _favs.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Same DetailScreen wiring as menu / search item cards.
  void _openItemDetail(FoodModel model) {
    final FoodMenuItem? menuItem =
        FirestoreService.findCachedProductByName(model.name);

    final Future<void>? nav;
    if (menuItem != null && menuItem.isDeal) {
      nav = DetailScreen.open(
        context,
        (asDialog) => DetailScreen(
          model: menuItem.toFoodModel(),
          asDialog: asDialog,
          isDeal: true,
          dealGroups: menuItem.dealGroups,
          dealFixedItems: menuItem.dealFixedItems,
          dealModelQuantities: menuItem.dealModelQuantities,
          modelDisplayNames: menuItem.modelDisplayNames,
        ),
      );
    } else if (menuItem != null) {
      nav = DetailScreen.open(
        context,
        (asDialog) => DetailScreen(
          model: menuItem.toFoodModel(),
          asDialog: asDialog,
          sizeModelUrls: menuItem.sizeModelUrls,
          sizeModelDisplayNames: menuItem.sizeModelDisplayNames,
          sizeSelectionLabel: menuItem.sizeSelectionLabel,
          dealModelTypesOrder: menuItem.dealModelTypesOrder,
          modelDisplayNames: menuItem.modelDisplayNames,
        ),
      );
    } else {
      nav = DetailScreen.open(
        context,
        (asDialog) => DetailScreen(model: model, asDialog: asDialog),
      );
    }

    nav.then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final favorites = _favs.favorites;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: const CustomHeader(
        title: "My Favorites",
        showBackButton: true,
        subtitle: "",
      ),
      body: favorites.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 20),
              itemCount: favorites.length,
              separatorBuilder: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.divider,
                ),
              ),
              itemBuilder: (context, index) {
                return _buildFavoriteCard(favorites[index]);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 80, color: AppColors.primary.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          Text(
            "No Favorites Yet",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.heading),
          ),
          const SizedBox(height: 8),
          Text(
            "Items you favorite will appear here",
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteCard(FoodModel model) {
    return ProductRowCard(
      model: model,
      imageBackgroundColor: AppColors.surfaceElevated,
      showAddButton: false,
      onTap: () => _openItemDetail(model),
    );
  }
}
