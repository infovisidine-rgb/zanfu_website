import 'package:flutter/material.dart';
import '../models/food_model.dart';

class SizeSettingsController extends ChangeNotifier {
  final List<FoodModel> selectedModels = [];

  bool isSelected(FoodModel model) {
    return selectedModels.any((m) => m.name == model.name);
  }

  void toggleSelection(FoodModel model) {
    final index = selectedModels.indexWhere((m) => m.name == model.name);
    if (index >= 0) {
      selectedModels.removeAt(index);
    } else {
      selectedModels.add(model);
    }
    notifyListeners();
  }

  void updateModelSize(FoodModel model, double newSize) {
    model.currentInches = newSize;
    notifyListeners();
  }
}
