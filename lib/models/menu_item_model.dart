import 'food_model.dart';
import '../data/food_data.dart';

/// A menu item fetched from Firebase Firestore.
/// Structure mirrors the admin app's product schema:
///   Collection: {category}/{productName}
///   Fields: name, description, category, price, image, banner_image,
///           enabled, deal_multi_choice_groups, deal_model_types, etc.
class FoodMenuItem {
  final String id;
  final String name;
  final String description;
  final String category;
  final String price;
  final String imageUrl;
  final String bannerImageUrl;
  /// Firestore website-only banner (falls back to [bannerImageUrl] when empty).
  final String websiteBannerUrl;
  final bool enabled;
  final String status;
  final bool isDeal;
  final String discount;
  /// Firestore `discount_type` — percent / rs / fixed, etc.
  final String discountType;
  /// Firestore `disc_price` — percent number or flat Rs amount.
  final String discPrice;
  final String modelUrl;
  /// Firestore `order` — menu card sort within a category (lower first).
  final int order;
  final Map<String, String> sizeModelUrls;
  /// Size key → Firestore display name from `size_model_urls` (e.g. Small → "Fajita Pizza Small").
  final Map<String, String> sizeModelDisplayNames;
  /// Firestore `size_selection_label` (e.g. "Choose") for detail size section title.
  final String sizeSelectionLabel;
  /// Ordered keys from Firestore `deal_model_types` (canonical size/item order).
  final List<String> dealModelTypesOrder;

  // Deal-specific fields
  final List<DealGroup> dealGroups;       // multi-choice groups (choose 1 from N)
  final List<String> dealFixedItems;      // static items always included in deal
  final Map<String, int> dealModelQuantities; // quantities of each item in deal
  /// Firestore `3d_models_urls` — canonical display order for deal items.
  final List<String> modelUrlsOrder;
  /// Display names keyed by model URL (from Firestore `name` fields).
  final Map<String, String> modelDisplayNames;

  const FoodMenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.imageUrl,
    this.bannerImageUrl = '',
    this.websiteBannerUrl = '',
    this.enabled = true,
    this.status = 'active',
    this.isDeal = false,
    this.discount = '',
    this.discountType = '',
    this.discPrice = '',
    this.modelUrl = '',
    this.order = 0,
    this.sizeModelUrls = const {},
    this.sizeModelDisplayNames = const {},
    this.sizeSelectionLabel = '',
    this.dealModelTypesOrder = const [],
    this.dealGroups = const [],
    this.dealFixedItems = const [],
    this.dealModelQuantities = const {},
    this.modelUrlsOrder = const [],
    this.modelDisplayNames = const {},
  });

  /// Image used on the website home scrollable carousel.
  String get effectiveWebsiteBannerUrl {
    final web = websiteBannerUrl.trim();
    if (web.isNotEmpty) return web;
    return bannerImageUrl.trim();
  }

  bool get hasWebsiteBanner => effectiveWebsiteBannerUrl.isNotEmpty;

  /// Prefer Firestore `name` next to the URL; legacy fallback = filename.
  String displayNameFor(String urlOrKey) {
    final key = urlOrKey.trim();
    if (key.isEmpty) return '';

    final direct = modelDisplayNames[key]?.trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final norm = _normalizeModelKey(key);
    if (norm.isNotEmpty) {
      final byNormKey = modelDisplayNames['norm:$norm']?.trim();
      if (byNormKey != null && byNormKey.isNotEmpty) return byNormKey;

      for (final e in modelDisplayNames.entries) {
        if (e.key.startsWith('norm:')) continue;
        if (_normalizeModelKey(e.key) == norm) {
          final n = e.value.trim();
          if (n.isNotEmpty) return n;
        }
        if (_modelsMatch(e.key, key)) {
          final n = e.value.trim();
          if (n.isNotEmpty) return n;
        }
      }
      for (final g in dealGroups) {
        for (final opt in g.options) {
          if (_normalizeModelKey(opt.url) == norm && opt.name.trim().isNotEmpty) {
            // Skip legacy filename-looking names if we have a map entry.
            return opt.name.trim();
          }
        }
      }
    }
    return _legacyNameFromUrl(key);
  }

  static String _legacyNameFromUrl(String url) {
    final filename = url.split('/').last.split('?').first
        .replaceAll('.glb', '')
        .replaceAll('.usdz', '')
        .replaceAll('-optimized', '')
        .replaceAll('.', ' ');
    final pattern = RegExp(r'(?<=[a-z])(?=[A-Z])');
    var name = filename.split(pattern).join(' ');
    name = name.replaceAll('BBq', 'BBQ').replaceAll('bbq', 'BBQ');
    name = name.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
    return name.trim();
  }

  /// Items marked inactive / disabled must not show in the app.
  bool get isActive {
    if (!enabled) return false;
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return true;
    return s != 'inactive' &&
        s != 'disabled' &&
        s != 'off' &&
        s != 'false' &&
        s != '0';
  }

  factory FoodMenuItem.fromFirestore(Map<String, dynamic> data) {
    final modelDisplayNames = <String, String>{};

    void rememberName(String url, String name) {
      final u = url.trim();
      final n = name.trim();
      if (u.isEmpty || n.isEmpty) return;
      modelDisplayNames[u] = n;
      final norm = _normalizeModelKey(u);
      if (norm.isNotEmpty) {
        modelDisplayNames['norm:$norm'] = n;
      }
    }

    String lookupKnownName(String url) {
      final u = url.trim();
      if (u.isEmpty) return '';
      final direct = modelDisplayNames[u]?.trim();
      if (direct != null && direct.isNotEmpty) return direct;
      final norm = _normalizeModelKey(u);
      if (norm.isNotEmpty) {
        final byNorm = modelDisplayNames['norm:$norm']?.trim();
        if (byNorm != null && byNorm.isNotEmpty) return byNorm;
      }
      for (final e in modelDisplayNames.entries) {
        if (e.key.startsWith('norm:')) continue;
        if (_modelsMatch(e.key, u) && e.value.trim().isNotEmpty) {
          return e.value.trim();
        }
      }
      return '';
    }

    // Canonical display order from Firestore 3D model URL lists (first → last).
    // Admin may use several key spellings — include `3dmodelurls`.
    final parsedModels = _parseOrderedModelEntries(
      data['3d_models_urls'] ??
          data['3d_model_urls'] ??
          data['3dmodels_urls'] ??
          data['3dmodelurls'] ??
          data['3dModelUrls'] ??
          data['3dModelsUrls'] ??
          data['3d_models_url'] ??
          data['models_urls'] ??
          data['3dmodelsurl'],
    );
    final List<String> modelUrlOrder =
        parsedModels.map((e) => e.url).toList();
    for (final e in parsedModels) {
      // Only store real Firestore names (not legacy filename fillers).
      if (e.hasFirestoreName) {
        rememberName(e.url, e.name);
      }
    }

    /// Reorder [urls] to match `3d_models_urls` (first→last). Unmatched keep
    /// their original relative order — never reverse/scramble.
    List<String> orderByModelUrls(List<String> urls) {
      if (modelUrlOrder.isEmpty || urls.length < 2) {
        return List<String>.from(urls);
      }
      final remaining = List<String>.from(urls);
      final ordered = <String>[];
      for (final master in modelUrlOrder) {
        final idx = remaining.indexWhere((u) => _modelsMatch(u, master));
        if (idx >= 0) {
          ordered.add(remaining.removeAt(idx));
        }
      }
      ordered.addAll(remaining);
      return ordered;
    }

    // Parse deal_model_types — map/list of url → static|variable
    final rawTypes = data['deal_model_types'];
    final List<String> modelTypesOrder = [];
    final Map<String, String> typeByExact = {};
    final Map<String, String> typeByNorm = {};

    void registerType(String key, String type) {
      final k = key.trim();
      if (k.isEmpty) return;
      modelTypesOrder.add(k);
      typeByExact[k] = type;
      final n = _normalizeModelKey(k);
      if (n.isNotEmpty) typeByNorm[n] = type;
    }

    if (rawTypes is List) {
      for (final e in rawTypes) {
        if (e == null) continue;
        if (e is Map) {
          final typeVal = (e['type'] ?? e['value'] ?? '').toString();
          final urlVal = (e['url'] ??
                  e['model_url'] ??
                  e['3dmodelurl'] ??
                  e['value_url'] ??
                  '')
              .toString()
              .trim();
          final nameVal =
              (e['name'] ?? e['label'] ?? e['title'] ?? '').toString().trim();
          final key = urlVal.isNotEmpty
              ? urlVal
              : (nameVal.isNotEmpty
                  ? nameVal
                  : (e['key'] ?? '').toString().trim());
          if (key.isNotEmpty) {
            registerType(key, typeVal);
            if (urlVal.isNotEmpty && nameVal.isNotEmpty) {
              rememberName(urlVal, nameVal);
            } else if (urlVal.isEmpty && nameVal.isNotEmpty && key != nameVal) {
              rememberName(key, nameVal);
            }
          } else {
            e.forEach((k, v) {
              // Skip known metadata keys when flattening.
              final ks = k.toString();
              if (ks == 'name' ||
                  ks == 'label' ||
                  ks == 'title' ||
                  ks == 'type' ||
                  ks == 'value') {
                return;
              }
              registerType(ks, v.toString());
            });
          }
        } else {
          registerType(e.toString(), '');
        }
      }
    } else if (rawTypes is Map) {
      rawTypes.forEach((k, v) {
        if (v is Map) {
          final typeVal = (v['type'] ?? v['value'] ?? '').toString();
          final urlVal = (v['url'] ?? v['model_url'] ?? k).toString().trim();
          final nameVal =
              (v['name'] ?? v['label'] ?? '').toString().trim();
          registerType(urlVal.isNotEmpty ? urlVal : k.toString(), typeVal);
          if (urlVal.isNotEmpty && nameVal.isNotEmpty) {
            rememberName(urlVal, nameVal);
          }
        } else {
          registerType(k.toString(), v.toString());
        }
      });
    }

    String? typeOf(String url) {
      final direct = typeByExact[url];
      if (direct != null) return direct;
      final norm = _normalizeModelKey(url);
      final byNorm = typeByNorm[norm];
      if (byNorm != null) return byNorm;
      for (final e in typeByExact.entries) {
        if (_modelsMatch(url, e.key)) return e.value;
      }
      return null;
    }

    // Static items: walk `3d_models_urls` first→last only (source of truth).
    final List<String> fixedItems = [];
    final seenFixed = <String>{};
    void addFixed(String url) {
      final u = url.trim();
      if (u.isEmpty) return;
      final norm = _normalizeModelKey(u);
      final dedupe = norm.isNotEmpty ? norm : u.toLowerCase();
      if (!seenFixed.add(dedupe)) return;
      fixedItems.add(u);
    }

    if (modelUrlOrder.isNotEmpty) {
      for (final url in modelUrlOrder) {
        if (typeOf(url)?.toLowerCase() == 'static') {
          addFixed(url);
        }
      }
      final missingStatic = <String>[];
      for (final e in typeByExact.entries) {
        if (e.value.toLowerCase() != 'static') continue;
        final norm = _normalizeModelKey(e.key);
        final dedupe = norm.isNotEmpty ? norm : e.key.toLowerCase();
        if (!seenFixed.contains(dedupe)) missingStatic.add(e.key);
      }
      for (final url in orderByModelUrls(missingStatic)) {
        addFixed(url);
      }
    } else {
      for (final e in typeByExact.entries) {
        if (e.value.toLowerCase() == 'static') addFixed(e.key);
      }
    }

    // Parse deal_multi_choice_groups — options ordered by `3d_models_urls`.
    final rawGroups = data['deal_multi_choice_groups'];
    final List<DealGroup> groups = [];
    if (rawGroups is List) {
      for (var g in rawGroups) {
        if (g is Map) {
          final name = g['name']?.toString() ?? '';
          final rawUrls = g['urls'] as List? ?? const [];
          final options = <DealOption>[];
          for (final entry in rawUrls) {
            if (entry is Map) {
              final url = (entry['url'] ??
                      entry['model_url'] ??
                      entry['3dmodelurl'] ??
                      entry['value'] ??
                      entry['src'] ??
                      '')
                  .toString()
                  .trim();
              final optName = (entry['name'] ??
                      entry['label'] ??
                      entry['title'] ??
                      '')
                  .toString()
                  .trim();
              if (url.isEmpty) continue;
              rememberName(url, optName);
              options.add(DealOption(
                url: url,
                name: optName.isNotEmpty ? optName : _legacyNameFromUrl(url),
                hasFirestoreName: optName.isNotEmpty,
              ));
            } else {
              final url = entry.toString().trim();
              if (url.isEmpty) continue;
              final known = lookupKnownName(url);
              options.add(DealOption(
                url: url,
                name: known.isNotEmpty ? known : _legacyNameFromUrl(url),
                hasFirestoreName: known.isNotEmpty,
              ));
            }
          }
          if (name.isNotEmpty && options.isNotEmpty) {
            final orderedUrls =
                orderByModelUrls(options.map((o) => o.url).toList());
            final byUrl = {for (final o in options) o.url: o};
            final orderedOptions = <DealOption>[];
            for (final u in orderedUrls) {
              final o = byUrl[u];
              if (o != null) orderedOptions.add(o);
            }
            groups.add(DealGroup(title: name, options: orderedOptions));
          }
        }
      }
    }

    // Re-bind choice option labels from `3dmodelurls` name map (URL filename
    // must never win when Firestore provides e.g. "Bigbangg" for Bigbang.glb).
    if (modelDisplayNames.isNotEmpty && groups.isNotEmpty) {
      for (var i = 0; i < groups.length; i++) {
        final g = groups[i];
        groups[i] = DealGroup(
          title: g.title,
          options: g.options.map((o) {
            final known = lookupKnownName(o.url);
            if (known.isNotEmpty) {
              return DealOption(
                url: o.url,
                name: known,
                hasFirestoreName: true,
              );
            }
            return o;
          }).toList(),
        );
      }
    }

    // Parse deal_model_quantities
    final rawQuantities = data['deal_model_quantities'];
    final Map<String, int> quantities = {};
    if (rawQuantities is Map) {
      rawQuantities.forEach((k, v) {
        quantities[k.toString()] = int.tryParse(v.toString()) ?? 1;
      });
    }

    final category = data['category']?.toString() ?? '';
    final isDeal = category.trim().toLowerCase() == 'deals';

    final sizeModelUrlsMap = <String, String>{};
    final sizeModelDisplayNamesMap = <String, String>{};
    final rawSizeModelUrls = data['size_model_urls'];
    if (rawSizeModelUrls is Map) {
      rawSizeModelUrls.forEach((k, v) {
        final sizeKey = k.toString().trim();
        if (sizeKey.isEmpty) return;
        if (v is Map) {
          final url = (v['url'] ??
                  v['model_url'] ??
                  v['3dmodelurl'] ??
                  v['value'] ??
                  '')
              .toString()
              .trim();
          final displayName =
              (v['name'] ?? v['label'] ?? '').toString().trim();
          if (url.isNotEmpty) {
            // Keep size key as Small/Medium/Large for price variation matching.
            sizeModelUrlsMap[sizeKey] = url;
            if (displayName.isNotEmpty) {
              sizeModelDisplayNamesMap[sizeKey] = displayName;
              rememberName(url, displayName);
            }
          }
        } else {
          final url = v.toString().trim();
          if (url.isNotEmpty) sizeModelUrlsMap[sizeKey] = url;
        }
      });
    }

    final sizeSelectionLabel = (data['size_selection_label'] ??
            data['sizeSelectionLabel'] ??
            data['size_label'] ??
            '')
        .toString()
        .trim();

    // Size display order must follow Firebase-controlled lists — never hardcode
    // Small → Medium → Large. Prefer:
    // 1) deal_model_types order
    // 2) 3dmodelurls array order (matched to size keys via URL)
    // 3) size_model_urls map insertion/key order
    final sizeOrderFromModelUrls = <String>[];
    for (final url in modelUrlOrder) {
      for (final e in sizeModelUrlsMap.entries) {
        if (_modelsMatch(e.value, url) || e.value.trim() == url.trim()) {
          if (!sizeOrderFromModelUrls.contains(e.key)) {
            sizeOrderFromModelUrls.add(e.key);
          }
          break;
        }
      }
    }

    final List<String> effectiveTypesOrder = modelTypesOrder.isNotEmpty
        ? modelTypesOrder
        : (sizeOrderFromModelUrls.isNotEmpty
            ? sizeOrderFromModelUrls
            : (sizeModelUrlsMap.keys.isNotEmpty
                ? sizeModelUrlsMap.keys.toList()
                : modelUrlOrder));

    final discountType = (data['discount_type'] ??
            data['discountType'] ??
            data['Discount Type'] ??
            '')
        .toString();
    // Prefer disc_price; fall back to legacy `discount` value field.
    final discPrice = (data['disc_price'] ??
            data['discPrice'] ??
            data['discount_price'] ??
            data['discountPrice'] ??
            data['discount'] ??
            '')
        .toString();

    return FoodMenuItem(
      id: data['id']?.toString() ?? data['name']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      category: category,
      price: data['price']?.toString() ?? '',
      imageUrl: data['image']?.toString() ?? '',
      bannerImageUrl: data['banner_image']?.toString() ?? '',
      websiteBannerUrl: (data['website_banner'] ??
              data['website_banner_image'] ??
              data['websiteBanner'] ??
              data['banner_image_website'] ??
              '')
          .toString(),
      enabled: data['enabled'] != false,
      status: (data['status'] ?? data['item_status'] ?? 'active').toString(),
      isDeal: isDeal,
      discount: data['discount']?.toString() ?? '',
      discountType: discountType,
      discPrice: discPrice,
      modelUrl: data['3dmodelurl']?.toString() ?? '',
      order: _parseOrder(data['order']),
      sizeModelUrls: sizeModelUrlsMap,
      sizeModelDisplayNames: sizeModelDisplayNamesMap,
      sizeSelectionLabel: sizeSelectionLabel,
      dealModelTypesOrder: effectiveTypesOrder,
      dealGroups: groups,
      dealFixedItems: fixedItems,
      dealModelQuantities: quantities,
      modelUrlsOrder: modelUrlOrder,
      modelDisplayNames: modelDisplayNames,
    );
  }

  /// Parses Firestore `order` (int / num / string).
  static int _parseOrder(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().trim()) ?? 0;
  }

  /// True when two model refs point to the same asset (URL / filename / name).
  static bool _modelsMatch(String a, String b) {
    final aa = a.trim();
    final bb = b.trim();
    if (aa.isEmpty || bb.isEmpty) return false;
    if (aa == bb) return true;
    final na = _normalizeModelKey(aa);
    final nb = _normalizeModelKey(bb);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    if (na.length >= 4 && nb.length >= 4) {
      if (na.contains(nb) || nb.contains(na)) return true;
    }
    return false;
  }

  /// Parse Firestore `3d_models_urls` whether stored as List or Map.
  /// Supports `{ "name": "...", "url": "..." }` entries.
  static List<DealOption> _parseOrderedModelEntries(dynamic raw) {
    final out = <DealOption>[];
    if (raw == null) return out;

    void addEntry(String url, String name) {
      final u = url.trim();
      if (u.isEmpty) return;
      final n = name.trim();
      out.add(DealOption(
        url: u,
        name: n.isNotEmpty ? n : _legacyNameFromUrl(u),
        hasFirestoreName: n.isNotEmpty,
      ));
    }

    if (raw is List) {
      for (final u in raw) {
        if (u == null) continue;
        if (u is Map) {
          final url = (u['url'] ??
                  u['model_url'] ??
                  u['3dmodelurl'] ??
                  u['value'] ??
                  u['src'] ??
                  '')
              .toString()
              .trim();
          final name =
              (u['name'] ?? u['label'] ?? u['title'] ?? '').toString();
          addEntry(url, name);
        } else {
          addEntry(u.toString(), '');
        }
      }
      return out;
    }

    if (raw is Map) {
      final entries = raw.entries.toList();
      final keysNumeric =
          entries.every((e) => int.tryParse(e.key.toString()) != null);
      if (keysNumeric) {
        entries.sort((a, b) => int.parse(a.key.toString())
            .compareTo(int.parse(b.key.toString())));
        for (final e in entries) {
          final v = e.value;
          if (v is Map) {
            final url = (v['url'] ?? v['model_url'] ?? v['value'] ?? '')
                .toString();
            final name = (v['name'] ?? v['label'] ?? '').toString();
            addEntry(url, name);
          } else {
            addEntry(v.toString(), '');
          }
        }
        return out;
      }

      final valuesNumeric = entries.every(
          (e) => e.value is int || int.tryParse(e.value.toString()) != null);
      if (valuesNumeric) {
        entries.sort((a, b) => (int.tryParse(a.value.toString()) ?? 0)
            .compareTo(int.tryParse(b.value.toString()) ?? 0));
        for (final e in entries) {
          addEntry(e.key.toString(), '');
        }
        return out;
      }

      // Preserve map iteration order (admin write order when LinkedHashMap).
      for (final e in entries) {
        final v = e.value;
        if (v is Map) {
          final url = (v['url'] ??
                  v['model_url'] ??
                  v['3dmodelurl'] ??
                  v['value'] ??
                  v['src'] ??
                  '')
              .toString();
          final name = (v['name'] ?? v['label'] ?? e.key).toString();
          addEntry(url.isNotEmpty ? url : e.key.toString(), name);
        } else if (v is String &&
            (v.startsWith('http') ||
                v.contains('.glb') ||
                v.contains('.usdz'))) {
          // Key may be the human name when value is the URL.
          final key = e.key.toString().trim();
          final looksLikeUrl = key.startsWith('http') ||
              key.contains('.glb') ||
              key.contains('.usdz');
          addEntry(v.trim(), looksLikeUrl ? '' : key);
        } else {
          final k = e.key.toString().trim();
          if (k.isNotEmpty) addEntry(k, '');
        }
      }
    }
    return out;
  }

  /// Normalize model URL / name for fuzzy order matching.
  static String _normalizeModelKey(String url) {
    var s = url.trim();
    if (s.isEmpty) return '';
    try {
      s = Uri.decodeFull(s);
    } catch (_) {}
    s = s.split('?').first.split('#').first;
    s = s.split('/').last.toLowerCase();
    s = s
        .replaceAll('-optimized', '')
        .replaceAll('_optimized', '')
        .replaceAll('.glb', '')
        .replaceAll('.usdz', '');
    return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Public alias for fuzzy URL matching (qty / order helpers).
  static String normalizeModelKeyPublic(String url) => _normalizeModelKey(url);


  /// Prefer main model URL; fall back to first size-specific URL.
  String get effectiveModelUrl {
    final main = modelUrl.trim();
    if (main.isNotEmpty) return main;
    for (final u in sizeModelUrls.values) {
      final v = u.trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  FoodModel toFoodModel() {
    // Prefer product's own Firebase URL; else match zanfumenu/3dmodelsurl catalog.
    final url = effectiveModelUrl.isNotEmpty
        ? effectiveModelUrl
        : (findCatalogModelUrl(name) ?? '');
    final variations = parsedVariations;
    final firstPrice = variations.isNotEmpty
        ? (variations.first['price'] as num?)?.toDouble()
        : null;
    return FoodModel(
      name: name,
      imagePath: imageUrl.isNotEmpty ? imageUrl : 'assets/zanfu_logo.png',
      price: price,
      category: category,
      description: description,
      path: url,
      isLocalFile: false,
      discountType: discountType,
      discPrice: discPrice,
      listPrice: (firstPrice != null && firstPrice > 0) ? firstPrice : null,
    );
  }

  /// Parses price string like "S 590 | M 890 | L 1299" or "Rs 790"
  /// Returns list of {name, price} maps, ordered by [dealModelTypesOrder]
  /// (then [sizeModelUrls] keys) when available.
  List<Map<String, dynamic>> get parsedVariations {
    final priceStr = price;
    final List<Map<String, dynamic>> result = [];
    if (priceStr.contains('|')) {
      final parts = priceStr.split('|');
      for (var part in parts) {
        final cleanPart = part.trim();
        // name can contain digits/spaces; last number = price.
        final match =
            RegExp(r'^(.+?)\s+(\d+(?:\.\d+)?)\s*$').firstMatch(cleanPart);
        if (match != null) {
          var rawName = match.group(1)!.trim();
          rawName = rawName
              .replaceAll(RegExp(r'\b(Rs|PKR)\b', caseSensitive: false), '')
              .trim();
          final expandedName = _expandSizeName(rawName);
          final p = double.tryParse(match.group(2)!) ?? 0;
          result.add({'name': expandedName, 'price': p});
        }
      }
    } else {
      final match = RegExp(r'(\d+)').firstMatch(priceStr);
      if (match != null) {
        result.add({'name': 'Regular', 'price': double.parse(match.group(1)!)});
      }
    }
    sortVariationsByModelTypesOrder(
      result,
      dealModelTypesOrder: dealModelTypesOrder,
      sizeModelUrls: sizeModelUrls,
    );
    return result;
  }

  static String _expandSizeName(String name) {
    switch (name.trim().toUpperCase()) {
      case 'M': return 'Medium';
      case 'L': return 'Large';
      case 'S': return 'Small';
      default: return name;
    }
  }

  /// Size order from Firestore only (`deal_model_types` / `3dmodelurls` /
  /// `size_model_urls` key order). Never force Small→Medium→Large.
  static void sortVariationsByModelTypesOrder(
    List<Map<String, dynamic>> variations, {
    List<String> dealModelTypesOrder = const [],
    Map<String, String> sizeModelUrls = const {},
  }) {
    if (variations.length < 2) return;
    // Prefer explicit ordered list; only then fall back to size_model_urls keys.
    final order = dealModelTypesOrder.isNotEmpty
        ? List<String>.from(dealModelTypesOrder)
        : sizeModelUrls.keys.toList();
    if (order.isEmpty) return;

    int indexOf(String name) {
      final n = name.trim().toLowerCase();
      final nUpper = name.trim().toUpperCase();
      for (var i = 0; i < order.length; i++) {
        final k = order[i].trim();
        if (k.isEmpty) continue;
        final kLower = k.toLowerCase();
        if (kLower == n) return i;
        // S / M / L ↔ Small / Medium / Large (same index, not a fixed global order)
        if ((nUpper == 'S' || n == 'small') &&
            (kUpperMatch(k, 'S') || kLower == 'small')) {
          return i;
        }
        if ((nUpper == 'M' || n == 'medium') &&
            (kUpperMatch(k, 'M') || kLower == 'medium')) {
          return i;
        }
        if ((nUpper == 'L' || n == 'large') &&
            (kUpperMatch(k, 'L') || kLower == 'large')) {
          return i;
        }
        // URL / display-name style keys from 3dmodelurls
        final file = k.split('/').last.split('?').first.toLowerCase();
        if (file.isNotEmpty &&
            (file.contains(n) || n.contains(kLower) || kLower.contains(n))) {
          return i;
        }
      }
      return 9999;
    }

    variations.sort((a, b) {
      final ai = indexOf(a['name']?.toString() ?? '');
      final bi = indexOf(b['name']?.toString() ?? '');
      if (ai != bi) return ai.compareTo(bi);
      return 0; // keep relative order when both unknown
    });
  }

  static bool kUpperMatch(String key, String letter) =>
      key.trim().toUpperCase() == letter;
}


/// Represents a single choice group inside a Deal.
/// Example: "Choose 1 Small Pizza" with 3 options.
class DealGroup {
  final String title;
  final List<DealOption> options;

  const DealGroup({
    required this.title,
    required this.options,
  });

  /// URLs only — kept for existing call sites.
  List<String> get itemUrls =>
      options.map((o) => o.url).toList(growable: false);

  String nameForUrl(String url) {
    for (final o in options) {
      if (o.url == url) return o.name;
      if (FoodMenuItem.normalizeModelKeyPublic(o.url) ==
          FoodMenuItem.normalizeModelKeyPublic(url)) {
        return o.name;
      }
    }
    return FoodMenuItem._legacyNameFromUrl(url);
  }
}

/// One selectable / included model with Firestore display [name] + [url].
class DealOption {
  final String url;
  final String name;
  /// True when [name] came from Firestore `name` (not URL filename).
  final bool hasFirestoreName;

  const DealOption({
    required this.url,
    required this.name,
    this.hasFirestoreName = false,
  });
}
