import 'package:flutter/material.dart';

class BottomNavController extends ChangeNotifier {
  int _selectedIndex;
  bool _hideBottomNav = false;
  String? _pendingMenuCategory;

  BottomNavController({int initialIndex = 0}) : _selectedIndex = initialIndex;

  int get selectedIndex => _selectedIndex;
  bool get hideBottomNav => _hideBottomNav;
  String? get pendingMenuCategory => _pendingMenuCategory;

  void setSelectedIndex(int index) {
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    // Leaving branches / any tab switch should restore the nav bar
    if (_hideBottomNav) {
      _hideBottomNav = false;
    }
    notifyListeners();
  }

  /// Opens the full menu screen (formerly Menu tab).
  void openMenuTab({String? category}) {
    _pendingMenuCategory = category;
    _selectedIndex = 0;
    if (_hideBottomNav) {
      _hideBottomNav = false;
    }
    notifyListeners();
  }

  void clearPendingMenuCategory() {
    if (_pendingMenuCategory == null) return;
    _pendingMenuCategory = null;
  }

  void setHideBottomNav(bool hide) {
    if (_hideBottomNav == hide) return;
    _hideBottomNav = hide;
    notifyListeners();
  }
}
