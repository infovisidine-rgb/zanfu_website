import 'package:flutter/material.dart';
import '../models/food_model.dart';

/// Global notifier — whenever availableModels changes, increment this value.
final ValueNotifier<int> foodDataVersion = ValueNotifier<int>(0);

/// Runtime AR model catalog — filled from `zanfumenu/3dmodelsurl`
/// (and menu product URLs). GLBs download once, then load from local cache.
final List<FoodModel> availableModels = [];

/// Raw key → URL from Firestore doc `zanfumenu/3dmodelsurl`.
final Map<String, String> modelUrlCatalogByKey = {};

/// Normalized name/filename → URL for product matching.
final Map<String, String> modelUrlCatalogByNormName = {};

/// URL → display name from Firestore `name` (or catalog key).
final Map<String, String> modelUrlCatalogDisplayNames = {};

String normalizeModelKey(String value) {
  return value
      .split('/')
      .last
      .split('?')
      .first
      .replaceAll('.glb', '')
      .replaceAll('.usdz', '')
      .replaceAll('-optimized', '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .toLowerCase();
}

/// Replace in-memory catalog maps used to resolve product → model URL.
void updateModelUrlCatalog(
  Map<String, String> keyToUrl, {
  Map<String, String> nameByUrl = const {},
}) {
  modelUrlCatalogByKey
    ..clear()
    ..addAll(keyToUrl);
  modelUrlCatalogByNormName.clear();
  modelUrlCatalogDisplayNames
    ..clear()
    ..addAll(nameByUrl);
  for (final entry in keyToUrl.entries) {
    final url = entry.value.trim();
    if (url.isEmpty) continue;
    modelUrlCatalogByNormName[normalizeModelKey(entry.key)] = url;
    modelUrlCatalogByNormName[normalizeModelKey(url)] = url;
    // If no explicit name, use non-URL catalog keys as display names.
    if (!modelUrlCatalogDisplayNames.containsKey(url)) {
      final key = entry.key.trim();
      if (key.isNotEmpty &&
          !key.startsWith('http') &&
          !key.contains('.glb') &&
          !key.contains('.usdz')) {
        modelUrlCatalogDisplayNames[url] = key;
      }
    }
  }
}

/// Find a catalog URL for a product/display name (or filename).
String? findCatalogModelUrl(String name) {
  if (name.trim().isEmpty) return null;
  return modelUrlCatalogByNormName[normalizeModelKey(name)];
}

String prettyNameFromModelUrl(String url, {String fallbackKey = ''}) {
  final mapped = modelUrlCatalogDisplayNames[url.trim()]?.trim();
  if (mapped != null && mapped.isNotEmpty) return mapped;

  final filename = url.split('/').last.split('?').first;
  var base = filename
      .replaceAll('.glb', '')
      .replaceAll('.usdz', '')
      .replaceAll('-optimized', '');
  if (base.isEmpty) base = fallbackKey;
  if (base == 'BBqRollParatha') return 'BBQ Roll Paratha';
  final pattern = RegExp(r'(?<=[a-z])(?=[A-Z])');
  var nice = base.split(pattern).join(' ');
  nice = nice.replaceAll('BBq', 'BBQ').replaceAll('bbq', 'BBQ');
  return nice.trim().isEmpty ? '3D Model' : nice.trim();
}
