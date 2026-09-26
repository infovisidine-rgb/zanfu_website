import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/cart_controller.dart';
import '../models/food_model.dart';
import '../utils/app_colors.dart';
import '../utils/device_ar_capability.dart';
import '../utils/responsive_helper.dart';
import 'detail_screen.dart';
import '../widgets/custom_header.dart';
import '../widgets/explore_menu_card.dart';
import '../controllers/home_scroll_to_menu.dart';
import '../widgets/discount_badge.dart';
import '../widgets/tap_hand_click_hint.dart';
import '../widgets/visidine_brand_text.dart';
import 'checkout_screen.dart';
import '../utils/visidine_ar_open.dart';
import '../services/firestore_service.dart';
import '../models/menu_item_model.dart';
import '../widgets/app_bottom_action_button.dart';
import '../widgets/app_cart_icon.dart';
import '../widgets/brand_image.dart';
import '../widgets/app_delete_icon.dart';

/// Hand coach on View by VisiDine — first N cart opens after install.
const String _kCartVisidineHintCountKey = 'cart_visidine_tap_hint_count';
const int _kCartVisidineHintMaxShows = 3;

class CartScreen extends StatefulWidget {
  /// When true, shown as a right-side overlay panel (desktop/laptop).
  final bool asSidePanel;

  const CartScreen({super.key, this.asSidePanel = false});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen>
    with SingleTickerProviderStateMixin {
  final CartController _cart = CartController();
  late final TextEditingController _specialInstructionsController;
  late final FocusNode _specialInstructionsFocus;
  late final AnimationController _visidineDropCtrl;
  late final Animation<Offset> _visidineSlide;
  bool _showVisidineHandHint = false;
  /// False on laptops / desktops — Visidine hidden (no camera AR).
  bool _deviceSupportsAr = false;

  String _cleanModelNameFromUrl(String url) {
    // Prefer Firestore display names from the matched deal product.
    for (final cat in FirestoreService.getCachedCategories()) {
      for (final p in FirestoreService.getCachedProductsByCategory(cat)) {
        if (p.modelDisplayNames.isEmpty && p.dealGroups.isEmpty) continue;
        final n = p.displayNameFor(url).trim();
        if (n.isNotEmpty && n != url) {
          // displayNameFor always returns something; prefer map hits.
          final mapped = p.modelDisplayNames[url]?.trim();
          if (mapped != null && mapped.isNotEmpty) return mapped;
          for (final g in p.dealGroups) {
            for (final o in g.options) {
              if (o.url == url && o.name.trim().isNotEmpty) return o.name.trim();
            }
          }
        }
      }
    }
    final s = url.trim();
    if (s.isEmpty) return '';
    final filename = s.split('/').last.split('?').first
        .replaceAll('.glb', '')
        .replaceAll('.usdz', '')
        .replaceAll('-optimized', '')
        .replaceAll('.', ' ');
    final pattern = RegExp(r'(?<=[a-z])(?=[A-Z])');
    var name = filename.split(pattern).join(' ');
    name = name.replaceAll('BBq', 'BBQ').replaceAll('bbq', 'BBQ');
    name = name.replaceAll('-', ' ');
    name = name
        .split(' ')
        .where((w) => w.trim().isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
    return name.trim();
  }

  FoodMenuItem? _menuItemForCart(CartItem cartItem) {
    final target = cartItem.foodModel.name.trim().toLowerCase();
    if (target.isEmpty) return null;
    for (final cat in FirestoreService.getCachedCategories()) {
      for (final p in FirestoreService.getCachedProductsByCategory(cat)) {
        if (p.name.trim().toLowerCase() == target) return p;
      }
    }
    return null;
  }

  int _dealQtyFor(FoodMenuItem menu, String itemUrl) {
    final direct = menu.dealModelQuantities[itemUrl];
    if (direct != null && direct > 0) return direct;
    final norm = FoodMenuItem.normalizeModelKeyPublic(itemUrl);
    if (norm.isEmpty) return 1;
    for (final e in menu.dealModelQuantities.entries) {
      if (FoodMenuItem.normalizeModelKeyPublic(e.key) == norm && e.value > 0) {
        return e.value;
      }
    }
    return 1;
  }

  /// Selected choices + fixed deal items for the bucket tile.
  List<String> _dealTileLines(CartItem cartItem) {
    final lines = <String>[];
    final seen = <String>{};

    void addLine(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return;
      final lower = t.toLowerCase();
      if (lower == 'regular' || lower == 'standard') return;
      if (!seen.add(lower)) return;
      lines.add(t);
    }

    for (final opt in cartItem.selectedDealOptions) {
      addLine(opt);
    }

    final menu = _menuItemForCart(cartItem);
    if (menu != null) {
      for (final url in menu.dealFixedItems) {
        final name = menu.displayNameFor(url).trim();
        if (name.isEmpty) continue;
        final qty = _dealQtyFor(menu, url);
        addLine(qty > 1 ? '$qty $name' : name);
      }
    }
    return lines;
  }

  @override
  void initState() {
    super.initState();
    _specialInstructionsController = TextEditingController(
      text: _cart.specialInstructions,
    );
    _specialInstructionsFocus = FocusNode();
    _visidineDropCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // Drop from above; bounceOut gives a soft settle bounce on landing.
    _visidineSlide = Tween<Offset>(
      begin: const Offset(0, -2.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _visidineDropCtrl,
        curve: Curves.bounceOut,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await deviceSupportsVisidineAr();
      if (!mounted) return;
      if (_deviceSupportsAr != ok) {
        setState(() => _deviceSupportsAr = ok);
      }
      if (!ok) return;
      // Let the cart settle briefly so the drop-in is easy to notice.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted || !_deviceSupportsAr) return;
      await _visidineDropCtrl.forward();
      if (!mounted) return;
      await _maybeShowVisidineHandHint();
    });
  }

  Future<void> _maybeShowVisidineHandHint() async {
    if (!mounted || _showVisidineHandHint) return;
    // Only coach when the VisiDine button can actually appear.
    if (!_deviceSupportsAr || _cart.items.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final shownCount = prefs.getInt(_kCartVisidineHintCountKey) ?? 0;
    if (shownCount >= _kCartVisidineHintMaxShows) return;
    await prefs.setInt(_kCartVisidineHintCountKey, shownCount + 1);

    // Small beat after the button lands, then show the tap hand.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (mounted) setState(() => _showVisidineHandHint = true);
  }

  void _dismissVisidineHandHint() {
    if (!_showVisidineHandHint) return;
    setState(() => _showVisidineHandHint = false);
  }

  @override
  void dispose() {
    _visidineDropCtrl.dispose();
    _specialInstructionsFocus.dispose();
    _specialInstructionsController.dispose();
    super.dispose();
  }

  int _getPrice(FoodModel model, {String? variation}) {
    double original = 0;
    final priceStr = model.price;
    if (priceStr.contains('|')) {
      if (variation != null && variation.trim().isNotEmpty) {
        final v = variation.trim().toLowerCase();
        for (final part in priceStr.split('|')) {
          final clean = part.trim();
          final match =
              RegExp(r'^(.+?)\s+(\d+(?:\.\d+)?)\s*$').firstMatch(clean);
          if (match == null) continue;
          var name = match.group(1)!.trim().toLowerCase();
          name = name
              .replaceAll(RegExp(r'\b(rs|pkr)\b'), '')
              .trim();
          if (name == 's') name = 'small';
          if (name == 'm') name = 'medium';
          if (name == 'l') name = 'large';
          if (name == v || name.startsWith(v) || v.startsWith(name)) {
            original = double.tryParse(match.group(2)!) ?? 0;
            break;
          }
        }
      }
      if (original <= 0) {
        original = model.displayOriginalPrice;
      }
    } else {
      original = model.displayOriginalPrice;
    }
    return model.discountedFrom(original).round();
  }

  int get _totalPrice {
    int total = 0;
    for (var item in _cart.items) {
      total +=
          _getPrice(item.foodModel, variation: item.selectedVariation) *
              item.quantity;
    }
    return total;
  }

  void _dismissSpecialInstructionsFocus() {
    if (_specialInstructionsFocus.hasFocus) {
      _specialInstructionsFocus.unfocus();
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CartController>(
      builder: (context, cart, child) {
        final bool isEmpty = cart.items.isEmpty;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBackground,
          appBar: CustomHeader(
            title: "Your Bucket",
            subtitle: "",
            showBackButton: true,
            showCartIcon: false,
            onBackTap: widget.asSidePanel
                ? () => Navigator.of(context).maybePop()
                : null,
          ),
          body: GestureDetector(
            onTap: _dismissSpecialInstructionsFocus,
            behavior: HitTestBehavior.translucent,
            child: isEmpty
                ? _buildEmptyCart(context)
                : _buildCartWithItems(context),
          ),
          bottomNavigationBar: isEmpty ? null : _buildBottomBar(context),
        );
      },
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                BrandImage(
                  assetPath: 'assets/zanfu_logo.png',
                  height: ResponsiveHelper.isTablet(context) ? 160 : 140,
                ),
                const SizedBox(height: 14),
                Text(
                  "No Cart Items Found",
                  style: TextStyle(
                    fontSize: ResponsiveHelper.isTablet(context) ? 18 : 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.heading,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ExploreMenuCard(
            onTap: () {
              Navigator.of(context).maybePop();
              HomeScrollToMenu.instance.request();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCartWithItems(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),

          ...List.generate(_cart.items.length, (index) {
            final cartItem = _cart.items[index];
            final price = _getPrice(
              cartItem.foodModel,
              variation: cartItem.selectedVariation,
            );
            final small = ResponsiveHelper.isSmallMobile(context);
            final tablet = ResponsiveHelper.isTablet(context);
            final img = small ? 72.0 : (tablet ? 112.0 : 96.0);
             return Container(
               margin: EdgeInsets.symmetric(
                 horizontal: small ? 10 : (tablet ? 22 : 16),
                 vertical: tablet ? 8 : 6,
               ),
               padding: EdgeInsets.symmetric(
                 horizontal: small ? 8 : (tablet ? 12 : 10),
                 vertical: small ? 8 : (tablet ? 12 : 10),
               ),
               decoration: BoxDecoration(
                 color: AppColors.cardBackground,
                 borderRadius: BorderRadius.circular(12),
                 boxShadow: [
                   BoxShadow(
                     color: Colors.black.withOpacity(0.04),
                     blurRadius: 8,
                     offset: const Offset(0, 2),
                   ),
                 ],
                 border: Border.all(color: AppColors.border, width: 0.8),
               ),
               child: Row(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    ProductImageWithDiscount(
                      imagePath: cartItem.foodModel.imagePath,
                      width: img,
                      height: img,
                      imageSize: img,
                      backgroundColor: AppColors.surfaceElevated,
                      fit: BoxFit.cover,
                      discountLabel: cartItem.foodModel.hasDiscount
                          ? cartItem.foodModel.discountBadgeLabel
                          : null,
                    ),
                  SizedBox(width: small ? 8 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cartItem.foodModel.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: small ? 13.5 : (tablet ? 17 : 15.5),
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.heading,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () async {
                                _dismissSpecialInstructionsFocus();
                                final isDeal = cartItem.foodModel.category == 'Deals';
                                final menuItem = _menuItemForCart(cartItem);

                                await DetailScreen.open(
                                  context,
                                  (asDialog) => DetailScreen(
                                    model: cartItem.foodModel,
                                    asDialog: asDialog,
                                    initialVariation: cartItem.selectedVariation,
                                    initialToppings: cartItem.selectedToppings,
                                    initialQuantity: cartItem.quantity,
                                    isEditing: true,
                                    isDeal: isDeal,
                                    sizeModelUrls: menuItem?.sizeModelUrls,
                                    sizeModelDisplayNames:
                                        menuItem?.sizeModelDisplayNames ??
                                            const {},
                                    sizeSelectionLabel:
                                        menuItem?.sizeSelectionLabel ?? '',
                                    dealModelTypesOrder:
                                        menuItem?.dealModelTypesOrder ?? const [],
                                    dealGroups: menuItem?.dealGroups ?? const [],
                                    dealFixedItems: menuItem?.dealFixedItems ?? const [],
                                    dealModelQuantities: menuItem?.dealModelQuantities ?? const {},
                                    modelDisplayNames:
                                        menuItem?.modelDisplayNames ?? const {},
                                    initialDealOptions: cartItem.selectedDealOptions,
                                  ),
                                );
                                if (!mounted) return;
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) _dismissSpecialInstructionsFocus();
                                });
                              },
                              child: Text(
                                "EDIT",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: tablet ? 14.5 : 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Builder(
                          builder: (_) {
                            final dealLines = _dealTileLines(cartItem);
                            if (dealLines.isNotEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final line in dealLines)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: Text(
                                        '•  $line',
                                        style: TextStyle(
                                          fontSize: tablet ? 14 : 13,
                                          color: AppColors.textSecondary,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            }
                            return Text(
                              cartItem.selectedVariation ?? "Standard",
                              style: TextStyle(
                                fontSize: tablet ? 14 : 13,
                                color: AppColors.textSecondary,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Rs $price",
                              style: TextStyle(
                                fontSize: small ? 14 : (tablet ? 18 : 16.5),
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            Container(
                              height: tablet ? 36 : 32,
                              width: small ? 84 : (tablet ? 108 : 96),
                              margin: EdgeInsets.only(left: small ? 6 : 20),
                              transform: Matrix4.translationValues(
                                small ? 0 : 6,
                                0,
                                0,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      _cart.decrementItem(cartItem);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: cartItem.quantity == 1
                                          ? const AppDeleteIcon(size: 20)
                                          : const Icon(
                                              Icons.remove,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                    ),
                                  ),
                                  Text(
                                    "${cartItem.quantity}",
                                    style: TextStyle(
                                      fontSize: tablet ? 16.5 : 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      _cart.incrementItem(cartItem);
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 4),
                                      child: Icon(Icons.add, size: 20, color: Colors.white),
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
                ],
              ),
            );
         }),
 
         const SizedBox(height: 16),
         // Special Instructions Section
         Padding(
           padding: const EdgeInsets.symmetric(horizontal: 16),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Text(
                 "Special Instructions",
                 style: TextStyle(
                   fontSize: ResponsiveHelper.isTablet(context) ? 16.5 : 15,
                   fontWeight: FontWeight.bold,
                   color: AppColors.primary,
                 ),
               ),
               const SizedBox(height: 4),
               Text(
                 "Are there any specific instructions for your order?",
                 style: TextStyle(
                   fontSize: ResponsiveHelper.isTablet(context) ? 13.5 : 12,
                   color: AppColors.textSecondary,
                 ),
               ),
               const SizedBox(height: 10),
               Container(
                 width: double.infinity,
                 padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                 decoration: BoxDecoration(
                   color: AppColors.cardBackground,
                   borderRadius: BorderRadius.circular(12),
                   border: Border.all(color: AppColors.border),
                 ),
                 child: TextField(
                   controller: _specialInstructionsController,
                   focusNode: _specialInstructionsFocus,
                   onChanged: _cart.setSpecialInstructions,
                   onTapOutside: (_) => _dismissSpecialInstructionsFocus(),
                   textInputAction: TextInputAction.done,
                   onEditingComplete: _dismissSpecialInstructionsFocus,
                   decoration: const InputDecoration(
                     hintText: "e.g Make it extra spicy, no onions...",
                     hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 15),
                     border: InputBorder.none,
                   ),
                   maxLines: 2,
                   style: TextStyle(
                     fontSize: ResponsiveHelper.isTablet(context) ? 16 : 14.5,
                     color: Colors.white,
                   ),
                 ),
               ),
             ],
           ),
         ),

         const SizedBox(height: 24),
          // Breathing room above bottom "View by VisiDine" / Review bar
          // (especially when content fits without scrolling).
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final List<FoodModel> placeModels = [];
    final List<FoodModel> displayModels = [];

    for (var item in _cart.items) {
      if (item.foodModel.category == 'Deals' || item.selectedDealOptions.isNotEmpty) {
        final String dealName = item.foodModel.name;
        FoodMenuItem? dealItem;
        final allCats = FirestoreService.getCachedCategories();
        for (var cat in allCats) {
          final products = FirestoreService.getCachedProductsByCategory(cat);
          for (var p in products) {
            if (p.name.trim().toLowerCase() == dealName.trim().toLowerCase()) {
              dealItem = p;
              break;
            }
          }
          if (dealItem != null) break;
        }

        final quantities = dealItem?.dealModelQuantities ?? const <String, int>{};

        int itemQtyFor(String url) {
          final q = quantities[url];
          if (q != null && q > 0) return q.clamp(1, 50);
          final key = url.split('/').last.split('?').first.toLowerCase();
          for (final e in quantities.entries) {
            final ek = e.key.split('/').last.split('?').first.toLowerCase();
            if (ek == key && e.value > 0) return e.value.clamp(1, 50);
          }
          return 1;
        }

        final List<FoodModel> dealParts = [];
        void addDealUrl(String url) {
          // Image-only choice options (jpg/png) are never placed in AR.
          if (!FoodModel.isGlbOrUsdzUrl(url)) return;
          final resolved = FirestoreService.resolveFoodModel(
            url,
            dealGroupName: dealName,
          );
          if (resolved == null) return;
          if (!FoodModel.isGlbOrUsdzUrl(resolved.path)) return;
          final copies = itemQtyFor(url);
          for (int i = 0; i < copies; i++) {
            dealParts.add(resolved.copyWith(arQuantity: 1));
          }
        }

        // Resolve each saved option to a concrete URL when possible.
        // If an older partial edit saved fewer options than deal groups,
        // fill remaining groups from their current defaults so AR still
        // shows the full deal.
        final savedOpts = item.selectedDealOptions;
        final groups = dealItem?.dealGroups ?? const <DealGroup>[];
        if (groups.isNotEmpty) {
          for (int i = 0; i < groups.length; i++) {
            final group = groups[i];
            String? url;
            if (i < savedOpts.length) {
              final saved = savedOpts[i].trim();
              if (saved.isNotEmpty) {
                url = group.itemUrls.firstWhere(
                  (u) =>
                      group.nameForUrl(u).trim().toLowerCase() ==
                          saved.toLowerCase() ||
                      _cleanModelNameFromUrl(u).trim().toLowerCase() ==
                          saved.toLowerCase() ||
                      u == saved,
                  orElse: () => '',
                );
                if (url.isEmpty) {
                  // Fall back to catalog resolve by saved name/url.
                  final resolved = FirestoreService.resolveFoodModel(
                    saved,
                    dealGroupName: dealName,
                  );
                  url = resolved?.path;
                }
              }
            }
            if (url == null || url.isEmpty) {
              url = group.itemUrls.isNotEmpty ? group.itemUrls.first : null;
            }
            if (url != null && url.isNotEmpty) addDealUrl(url);
          }
        } else {
          for (final opt in savedOpts) {
            addDealUrl(opt);
          }
        }
        if (dealItem != null && dealItem.dealFixedItems.isNotEmpty) {
          for (var fixedUrl in dealItem.dealFixedItems) {
            addDealUrl(fixedUrl);
          }
        }

        final orderQty = item.quantity.clamp(1, 50);
        final counts = <String, int>{};
        final samples = <String, FoodModel>{};
        for (final part in dealParts) {
          final String key = (part.path.trim().isNotEmpty
                  ? _cleanModelNameFromUrl(part.path)
                  : part.name)
              .trim();
          if (key.isEmpty) continue;

          counts[key] = (counts[key] ?? 0) + 1;
          samples[key] = part.copyWith(name: key);
          for (int i = 0; i < orderQty; i++) {
            placeModels.add(part.copyWith(arQuantity: 1));
          }
        }
        for (final entry in samples.entries) {
          displayModels.add(
            entry.value.copyWith(
              arQuantity: (counts[entry.key]! * orderQty).clamp(1, 50),
            ),
          );
        }
      } else if (item.foodModel.is3DAvailable) {
        // Resolve selected variation's size-specific GLB when available
        String path = item.foodModel.path;
        FoodMenuItem? menuItem;
        for (final cat in FirestoreService.getCachedCategories()) {
          for (final p in FirestoreService.getCachedProductsByCategory(cat)) {
            if (p.name.trim().toLowerCase() ==
                item.foodModel.name.trim().toLowerCase()) {
              menuItem = p;
              break;
            }
          }
          if (menuItem != null) break;
        }
        final sizeUrl = FirestoreService.resolveSizeModelUrl(
          menuItem?.sizeModelUrls,
          item.selectedVariation,
        );
        if (sizeUrl != null && sizeUrl.isNotEmpty) path = sizeUrl;

        final qty = item.quantity.clamp(1, 50);
        final sized = item.foodModel.copyWith(
          path: path,
          sizeLabel: item.selectedVariation,
          arQuantity: qty,
        );
        displayModels.add(sized);
        for (int i = 0; i < qty; i++) {
          placeModels.add(sized.copyWith(arQuantity: 1));
        }
      }
    }

    final bool hasAny = _deviceSupportsAr && placeModels.isNotEmpty;

    final tablet = ResponsiveHelper.isTablet(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAny) ...[
            // Clip so the button appears to drop out from behind content above
            // (Explore Menu / cart body), then bounce into place.
            ClipRect(
              child: SlideTransition(
                position: _visidineSlide,
                child: Container(
                  height: 52,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: tablet ? 300 : double.infinity,
                      ),
                      child: InkWell(
                        onTap: () {
                          _dismissVisidineHandHint();
                          openVisidineAr(
                            context,
                            dealModels: placeModels,
                            displayModels: displayModels,
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: AppColors.primary.withOpacity(0.8),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/visidine_logo.png',
                                      height: 32,
                                      width: 32,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(width: 16),
                                    const VisidineBrandText(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_showVisidineHandHint)
                              const Positioned(
                                right: 22,
                                top: 8,
                                child: IgnorePointer(
                                  child: TapHandClickHint(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _buildReviewPaymentBar(),
        ],
      ),
    );
  }

  Widget _buildReviewPaymentBar() {
    final small = ResponsiveHelper.isSmallMobile(context);
    final tablet = ResponsiveHelper.isTablet(context);
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxWidth: tablet ? 300 : double.infinity,
        ),
        height: small ? 52 : (tablet ? 64 : 58),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: InkWell(
            onTap: () {
              _cart.setSpecialInstructions(_specialInstructionsController.text);
              final nav = Navigator.of(context, rootNavigator: true);
              if (widget.asSidePanel) {
                nav.pop();
              }
              nav.push(
                MaterialPageRoute(builder: (_) => const CheckoutScreen()),
              );
            },
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: small ? 10 : (tablet ? 16 : 10),
              ),
              decoration: BoxDecoration(
                gradient: AppColors.flameGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: small ? 30 : (tablet ? 40 : 34),
                    height: small ? 30 : (tablet ? 40 : 34),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.cardBackground,
                      shape: BoxShape.circle,
                    ),
                    child: AppCartIcon(
                      filled: true,
                      color: Colors.white,
                      size: small ? 16 : (tablet ? 22 : 18),
                    ),
                  ),
                  SizedBox(width: small ? 6 : 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Rs $_totalPrice",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: small ? 14 : (tablet ? 17.5 : 15),
                          fontWeight: FontWeight.w900,
                          color: AppColors.onPrimary,
                        ),
                      ),
                      Text(
                        "Exclusive of tax",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: small ? 8 : (tablet ? 10 : 9),
                          color: AppColors.onPrimary.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'REVIEW PAYMENT',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: small ? 11 : (tablet ? 14.5 : 13),
                            fontWeight: FontWeight.w900,
                            color: AppColors.onPrimary,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_double_arrow_right_rounded,
                          size: small ? 16 : (tablet ? 22 : 20),
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
    );
  }
}
