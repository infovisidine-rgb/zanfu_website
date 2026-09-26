import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_model.dart';

class FavoritesController extends ChangeNotifier {
  static final FavoritesController _instance = FavoritesController._internal();
  factory FavoritesController() => _instance;
  FavoritesController._internal();

  static const String _prefsKey = 'favorite_items_v1';

  final List<FoodModel> _favorites = [];
  bool _loaded = false;
  Future<void>? _loadFuture;

  List<FoodModel> get favorites => List.unmodifiable(_favorites);

  bool get isLoaded => _loaded;

  Future<void> load() {
    _loadFuture ??= _loadFromPrefs();
    return _loadFuture!;
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey) ?? [];
      _favorites
        ..clear()
        ..addAll(raw.map((e) {
          final map = jsonDecode(e) as Map<String, dynamic>;
          return FoodModel.fromJson(map);
        }));
    } catch (e) {
      debugPrint('FavoritesController load error: $e');
      _favorites.clear();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded =
        _favorites.map((m) => jsonEncode(m.toJson())).toList(growable: false);
    await prefs.setStringList(_prefsKey, encoded);
  }

  bool isFavorite(FoodModel model) {
    return _favorites.any((item) => item.name == model.name);
  }

  Future<void> toggleFavorite(FoodModel model) async {
    await load();
    if (isFavorite(model)) {
      _favorites.removeWhere((item) => item.name == model.name);
    } else {
      _favorites.add(model);
    }
    await _persist();
    notifyListeners();
  }
}
