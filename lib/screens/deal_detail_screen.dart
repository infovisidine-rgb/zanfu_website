import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/menu_item_model.dart';
import '../utils/app_colors.dart';
import '../utils/app_haptics.dart';
import '../controllers/cart_controller.dart';
import '../widgets/flame_text.dart';
import '../widgets/product_image_container.dart';
import 'cart_screen.dart';
import '../widgets/app_cart_icon.dart';

class DealDetailScreen extends StatefulWidget {
  final FoodMenuItem dealItem;
  final bool isEditing;
  final List<String>? initialDealOptions;
  final int initialQuantity;

  const DealDetailScreen({
    super.key,
    required this.dealItem,
    this.isEditing = false,
    this.initialDealOptions,
    this.initialQuantity = 1,
  });

  @override
  State<DealDetailScreen> createState() => _DealDetailScreenState();
}

class _DealDetailScreenState extends State<DealDetailScreen> {
  int _quantity = 1;
  final CartController _cart = CartController();
  final Map<int, String> _selectedGroupOptions = {}; // GroupIndex -> SelectedUrl
  /// Tracks which deal-choice groups the user actually tapped.
  /// We use this for AR/cartoon names so only user-chosen groups show up.
  final Set<int> _touchedDealGroupIndices = {};

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialQuantity;
    // Pre-select options, matching with saved ones if editing
    for (int i = 0; i < widget.dealItem.dealGroups.length; i++) {
      final group = widget.dealItem.dealGroups[i];
      if (widget.initialDealOptions != null && widget.initialDealOptions!.length > i) {
        final savedName = widget.initialDealOptions![i];
        final matchingUrl = group.itemUrls.firstWhere(
          (url) =>
              group.nameForUrl(url) == savedName ||
              _cleanModelNameFromUrl(url) == savedName,
          orElse: () => group.itemUrls.isNotEmpty ? group.itemUrls.first : "",
        );
        if (matchingUrl.isNotEmpty) {
          _selectedGroupOptions[i] = matchingUrl;
        }
      } else if (group.itemUrls.isNotEmpty) {
        _selectedGroupOptions[i] = group.itemUrls.first;
      }
    }
  }

  String _cleanModelNameFromUrl(String url) {
    return widget.dealItem.displayNameFor(url);
  }

  String _getAssetImageForUrl(String url) {
    // Local food images were removed — use logo; product images come from Firebase.
    return 'assets/zanfu_logo.png';
  }

  double _parsePrice(String priceStr) {
    final match = RegExp(r'(\d+)').firstMatch(priceStr);
    if (match != null) {
      return double.parse(match.group(1)!);
    }
    return 0;
  }

  double get _dealPrice => _parsePrice(widget.dealItem.price);
  double get _totalPrice => _dealPrice * _quantity;

  void _showAddToCartToast(BuildContext context) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayEntry = OverlayEntry(
      builder: (context) {
        final wide = MediaQuery.sizeOf(context).width >= 600;
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 8,
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 16 : 14,
                  vertical: wide ? 10 : 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.onPrimary,
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: AppColors.onPrimary,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isEditing
                          ? "Deal has been updated"
                          : "Deal has been added to cart",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: wide ? 14 : 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasBanner = widget.dealItem.imageUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.matteBlack,
      appBar: AppBar(
        backgroundColor: AppColors.matteBlack,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: AppColors.matteBlack,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        leading: null,
        automaticallyImplyLeading: false,
        title: Text(
          widget.dealItem.name,
          style: const TextStyle(
            color: AppColors.heading,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CartScreen()),
            ).then((_) => setState(() {})),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 42,
              height: 42,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border, width: 1.5),
                      ),
                      child: const AppCartIcon(color: AppColors.textPrimary, size: 22),
                    ),
                  ),
                  if (_cart.totalItemsCount > 0)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          "${_cart.totalItemsCount}",
                          style: const TextStyle(
                            color: AppColors.matteBlack,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Deal Header Image
            if (hasBanner)
              Container(
                width: double.infinity,
                height: 220,
                color: AppColors.matteBlack,
                child: Image.network(
                  widget.dealItem.imageUrl,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.fastfood_outlined, color: AppColors.textSecondary, size: 64),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.dealItem.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.dealItem.description.isNotEmpty
                        ? widget.dealItem.description
                        : "Special deal with multiple choices and extra delicious items.",
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Rs ${_dealPrice.toInt()}",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const Divider(height: 32, thickness: 1),

                  // Multi-choice Groups first
                  ...List.generate(widget.dealItem.dealGroups.length, (gIndex) {
                    final group = widget.dealItem.dealGroups[gIndex];
                    final groupTitle = group.title;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              groupTitle,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: AppColors.flameGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                "REQUIRED",
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.matteBlack,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Column(
                          children: group.options.map((option) {
                            final optionUrl = option.url;
                            final optionName = option.name.trim().isNotEmpty
                                ? option.name.trim()
                                : _cleanModelNameFromUrl(optionUrl);
                            final isSelected = _selectedGroupOptions[gIndex] == optionUrl;

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                AppHaptics.selection();
                                setState(() {
                                  _selectedGroupOptions[gIndex] = optionUrl;
                                  _touchedDealGroupIndices.add(gIndex);
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primary.withValues(alpha: 0.08).withOpacity(0.3) : AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : AppColors.border,
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: isSelected
                                          ? Center(
                                              child: Container(
                                                width: 10,
                                                height: 10,
                                                decoration: const BoxDecoration(
                                                  color: AppColors.primary,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    ProductImageContainer(
                                      imagePath: _getAssetImageForUrl(optionUrl),
                                      width: 40,
                                      height: 40,
                                      imageSize: 30,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        optionName,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected ? AppColors.primary : const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  }),

                  // Included / static items below choice groups
                  if (widget.dealItem.dealFixedItems.isNotEmpty) ...[
                    if (widget.dealItem.dealGroups.isNotEmpty)
                      const Divider(height: 32, thickness: 1),
                    const Text(
                      "Included in this Deal",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: widget.dealItem.dealFixedItems.length,
                      itemBuilder: (context, index) {
                        final itemUrl = widget.dealItem.dealFixedItems[index];
                        final itemName = _cleanModelNameFromUrl(itemUrl);
                        final itemQty = widget.dealItem.dealModelQuantities[itemUrl] ?? 1;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border, width: 0.8),
                          ),
                          child: Row(
                            children: [
                              ProductImageContainer(
                                imagePath: _getAssetImageForUrl(itemUrl),
                                width: 45,
                                height: 45,
                                imageSize: 35,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  itemQty > 1 ? "$itemQty $itemName" : itemName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.heading,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.matteBlack,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Container(
                height: 46,
                width: 110,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, color: AppColors.textPrimary, size: 20),
                      onPressed: () {
                        if (_quantity > 1) {
                          setState(() => _quantity--);
                        }
                      },
                    ),
                    Text(
                      "$_quantity",
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: AppColors.textPrimary, size: 20),
                      onPressed: () => setState(() => _quantity++),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () {
                    // Persist every group selection — partial edit must not
                    // drop untouched groups from the cart/AR deal.
                    final List<String> selections = [];
                    final groupIndices =
                        _selectedGroupOptions.keys.toList()..sort();
                    for (final gIndex in groupIndices) {
                      final url = _selectedGroupOptions[gIndex];
                      if (url == null || url.isEmpty) continue;
                      selections.add(_cleanModelNameFromUrl(url));
                    }

                    if (widget.isEditing) {
                      _cart.updateItem(
                        widget.dealItem.toFoodModel(),
                        null,
                        const {},
                        null,
                        const {},
                        _quantity,
                        oldDealOptions: widget.initialDealOptions,
                        newDealOptions: selections,
                      );
                    } else {
                      // Add dynamic deal item to cart
                      _cart.addToCart(
                        widget.dealItem.toFoodModel(),
                        dealOptions: selections,
                        quantity: _quantity,
                      );
                    }

                    _showAddToCartToast(context);
                    // Stay on deal screen when adding; only pop after cart edit.
                    if (widget.isEditing) {
                      Future.delayed(const Duration(milliseconds: 800), () {
                        if (mounted) {
                          Navigator.pop(context);
                        }
                      });
                    }
                  },
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: AppColors.flameGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.isEditing ? 'UPDATE DEAL ' : 'ADD DEAL ',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.onPrimary,
                            ),
                          ),
                          Text(
                            'Rs ${_totalPrice.toInt()}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.onPrimary,
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
    );
  }
}
