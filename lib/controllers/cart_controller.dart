import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_model.dart';

class CartItem {
  final FoodModel foodModel;
  int quantity;
  String? selectedVariation;
  Set<String> selectedToppings;
  List<String> selectedDealOptions; // chosen items for deal groups

  CartItem({
    required this.foodModel,
    this.quantity = 1,
    this.selectedVariation,
    Set<String>? selectedToppings,
    this.selectedDealOptions = const [],
  }) : selectedToppings = selectedToppings ?? {};

  Map<String, dynamic> toJson() => {
        'foodModel': foodModel.toJson(),
        'quantity': quantity,
        'selectedVariation': selectedVariation,
        'selectedToppings': selectedToppings.toList(),
        'selectedDealOptions': selectedDealOptions,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final toppingsRaw = json['selectedToppings'];
    final dealsRaw = json['selectedDealOptions'];
    return CartItem(
      foodModel: FoodModel.fromJson(
        Map<String, dynamic>.from(json['foodModel'] as Map? ?? {}),
      ),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      selectedVariation: json['selectedVariation'] as String?,
      selectedToppings: toppingsRaw is List
          ? toppingsRaw.map((e) => e.toString()).toSet()
          : <String>{},
      selectedDealOptions: dealsRaw is List
          ? dealsRaw.map((e) => e.toString()).toList()
          : const [],
    );
  }
}

class CartController extends ChangeNotifier {
  static final CartController _instance = CartController._internal();
  factory CartController() => _instance;
  CartController._internal();

  static const String _prefsKey = 'cart_items_v1';
  static const String _instructionsPrefsKey = 'cart_special_instructions_v1';

  final List<CartItem> _items = [];
  String _specialInstructions = '';
  bool _loaded = false;
  Future<void>? _loadFuture;

  List<CartItem> get items => _items;
  String get specialInstructions => _specialInstructions;
  bool get isLoaded => _loaded;

  Future<void> load() {
    _loadFuture ??= _loadFromPrefs();
    return _loadFuture!;
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey) ?? [];
      _items
        ..clear()
        ..addAll(raw.map((e) {
          final map = jsonDecode(e) as Map<String, dynamic>;
          return CartItem.fromJson(map);
        }));
      _specialInstructions = prefs.getString(_instructionsPrefsKey) ?? '';
    } catch (e) {
      debugPrint('CartController load error: $e');
      _items.clear();
      _specialInstructions = '';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded =
          _items.map((item) => jsonEncode(item.toJson())).toList(growable: false);
      await prefs.setStringList(_prefsKey, encoded);
      await prefs.setString(_instructionsPrefsKey, _specialInstructions);
    } catch (e) {
      debugPrint('CartController persist error: $e');
    }
  }

  void setSpecialInstructions(String value) {
    _specialInstructions = value.trim();
    _persist();
    // Don't notify on every keystroke unless needed — callers can set from onChanged
  }

  int get totalItemsCount {
    int count = 0;
    for (var item in _items) {
      count += item.quantity;
    }
    return count;
  }

  void addToCart(FoodModel model, {String? variation, Set<String>? toppings, List<String>? dealOptions, int quantity = 1}) {
    // Check for exact match (same variation, toppings and deal options)
    int index = _items.indexWhere((item) =>
      item.foodModel.name == model.name &&
      item.selectedVariation == variation &&
      _isSameToppings(item.selectedToppings, toppings ?? {}) &&
      _isSameDealOptions(item.selectedDealOptions, dealOptions ?? [])
    );

    if (index >= 0) {
      _items[index].quantity += quantity;
    } else {
      _items.add(CartItem(
        foodModel: model,
        quantity: quantity,
        selectedVariation: variation,
        selectedToppings: toppings,
        selectedDealOptions: dealOptions ?? [],
      ));
    }
    notifyListeners();
    _persist();
  }

  bool _isSameToppings(Set<String> s1, Set<String> s2) {
    if (s1.length != s2.length) return false;
    return s1.containsAll(s2);
  }

  bool _isSameDealOptions(List<String> l1, List<String> l2) {
    if (l1.length != l2.length) return false;
    return l1.every((el) => l2.contains(el));
  }

  void updateItem(FoodModel model, String? oldVariation, Set<String> oldToppings,
                  String? newVariation, Set<String> newToppings, int newQuantity, {List<String>? oldDealOptions, List<String>? newDealOptions}) {
    int index = _items.indexWhere((item) =>
      item.foodModel.name == model.name &&
      item.selectedVariation == oldVariation &&
      _isSameToppings(item.selectedToppings, oldToppings) &&
      _isSameDealOptions(item.selectedDealOptions, oldDealOptions ?? [])
    );

    if (index >= 0) {
      _items[index].selectedVariation = newVariation;
      _items[index].selectedToppings = newToppings;
      _items[index].quantity = newQuantity;
      if (newDealOptions != null) {
        _items[index].selectedDealOptions = newDealOptions;
      }
      notifyListeners();
      _persist();
    }
  }

  void decrementQuantity(FoodModel model) {
    int index = _items.indexWhere((item) => item.foodModel.name == model.name);
    if (index >= 0) {
      if (_items[index].quantity > 1) {
        _items[index].quantity -= 1;
      } else {
        _items.removeAt(index);
      }
      notifyListeners();
      _persist();
    }
  }

  // Increment/decrement an exact cart row (handles deals with same name
  // but different selected options).
  void incrementItem(CartItem item) {
    item.quantity += 1;
    notifyListeners();
    _persist();
  }

  void decrementItem(CartItem item) {
    if (item.quantity > 1) {
      item.quantity -= 1;
    } else {
      _items.remove(item);
    }
    notifyListeners();
    _persist();
  }

  void removeFromCart(FoodModel model) {
    _items.removeWhere((item) => item.foodModel.name == model.name);
    notifyListeners();
    _persist();
  }

  void clearCart() {
    _items.clear();
    _specialInstructions = '';
    notifyListeners();
    _persist();
  }
}
