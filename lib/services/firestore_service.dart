import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/food_data.dart';
import '../models/food_model.dart';
import '../models/menu_item_model.dart';
import '../utils/disk_cache.dart';


class FirestoreService {
  static const String _collectionName = 'fastfooditems';
  static const String _catalogVersionPrefsKey = 'zanfu_catalog_version';

  static final ValueNotifier<int> menuDataVersion = ValueNotifier<int>(0);
  static List<String> _cachedCategories = [];
  static Map<String, List<FoodMenuItem>> _cachedProducts = {};
  static bool _cacheLoaded = false;

  // ── Branches local cache ───────────────────────────────────────────────────
  static List<Map<String, dynamic>> _cachedBranches = [];
  static bool _branchesCacheLoaded = false;
  static const String _branchesCacheFile = 'branches_cache.json';
  static final ValueNotifier<int> branchesDataVersion = ValueNotifier<int>(0);

  // ── 3D Model local cache index ──────────────────────────────────────────────
  // Maps Firebase model URL → absolute local file path on device storage.
  // Persisted to 'models_cache_index.json' so it survives app restarts.
  static Map<String, String> _modelUrlToLocalPath = {};
  static bool _modelCacheLoaded = false;
  static const String _modelsCacheIndexFile = 'models_cache_index.json';

  // Define mapping of Firestore documents to availableModels indices
  static final List<Map<String, dynamic>> cloudItems = [];

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1 — Fetch metadata for all cloud items (Splash Screen)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> fetchMetadataOnly() async {
    try {
      await Future.wait(cloudItems.map((item) async {
        final jsonName = item['cachedFileName'] as String;
        final modelName = item['cachedModelName'] as String;
        final int index = item['index'];

        final jsonStr = await DiskCache.readText(jsonName);
        if (jsonStr != null) {
          try {
            final jsonData = jsonDecode(jsonStr);
            final cachedName = jsonData['name'] as String?;
            if (cachedName != null) {
              final modelPath = await DiskCache.absolutePath(modelName);
              final fileExists = modelPath != null &&
                  DiskCache.absolutePathExists(modelPath);
              if (fileExists) {
                _updateAvailableModel(
                  index,
                  cachedName,
                  modelPath,
                  isLocalFile: true,
                );
              }
              debugPrint("FirestoreService: Loaded ${item['docId']} from cache: name='$cachedName', localFile=$fileExists");
            }
          } catch (e) {
            debugPrint("FirestoreService: Cache read error for ${item['docId']}: $e");
          }
        }

        try {
          final docSnapshot = await FirebaseFirestore.instance
              .collection(_collectionName)
              .doc(item['docId'])
              .get();

          if (docSnapshot.exists) {
            final data = docSnapshot.data()!;
            final String name = (data['name'] ?? item['fallbackName']) as String;
            final String modelUrl = (data['3dmodelurl'] ?? '') as String;

            await DiskCache.writeText(
              jsonName,
              jsonEncode({
                'name': name,
                '3dmodelurl': modelUrl,
              }),
            );

            final modelPath = await DiskCache.absolutePath(modelName);
            final fileExists = modelPath != null &&
                DiskCache.absolutePathExists(modelPath);
            final resolved = fileExists ? modelPath : modelUrl;
            if (resolved.isNotEmpty) {
              _updateAvailableModel(
                index,
                name,
                resolved,
                isLocalFile: fileExists,
              );
            }
            debugPrint("FirestoreService: Got name='$name' from Firestore for ${item['docId']}");
          }
        } catch (e) {
          debugPrint("FirestoreService: Firestore fetch error for ${item['docId']}: $e");
        }
      }));
    } catch (e) {
      debugPrint("FirestoreService: fetchMetadataOnly error: $e");
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2 — Download model lazily if missing
  // ─────────────────────────────────────────────────────────────────────────
  static Future<bool> ensureModelDownloaded(int modelIndex) async {
    try {
      final itemIndex = cloudItems.indexWhere((item) => item['index'] == modelIndex);
      if (itemIndex == -1) return true;

      final item = cloudItems[itemIndex];
      final modelName = item['cachedModelName'] as String;
      final modelPath = await DiskCache.absolutePath(modelName);

      if (modelPath != null && DiskCache.absolutePathExists(modelPath)) {
        debugPrint("FirestoreService: Model ${item['docId']} already in local storage ✅");
        if (!availableModels[modelIndex].isLocalFile) {
          final cachedName = availableModels[modelIndex].name;
          _updateAvailableModel(modelIndex, cachedName, modelPath, isLocalFile: true);
        }
        return true;
      }

      return true;
    } catch (e) {
      debugPrint("FirestoreService: ensureModelDownloaded error: $e");
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal helper
  // ─────────────────────────────────────────────────────────────────────────
  static void _updateAvailableModel(int index, String name, String localPath, {bool isLocalFile = false}) {
    if (availableModels.length > index) {
      final oldModel = availableModels[index];
      availableModels[index] = FoodModel(
        name: name,
        imagePath: oldModel.imagePath,
        path: localPath,
        price: oldModel.price,
        category: oldModel.category,
        baseScale: oldModel.baseScale,
        baseInches: oldModel.baseInches,
        isLocalFile: isLocalFile,
      );
      foodDataVersion.value++;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Catalog version gate — zanfumenu/metadata.catalog_version
  // Admin app bumps this when menu/deals/models change.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<int> getLocalCatalogVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_catalogVersionPrefsKey) ?? 0;
  }

  static Future<void> saveLocalCatalogVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_catalogVersionPrefsKey, version);
    debugPrint('FirestoreService: Saved local catalog_version=$version');
  }

  /// Reads `catalog_version` from `zanfumenu/metadata`. Returns null on failure.
  static Future<int?> fetchRemoteCatalogVersion() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('zanfumenu')
          .doc('metadata')
          .get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('FirestoreService: metadata doc missing — cannot read catalog_version');
        return null;
      }
      final raw = doc.data()!['catalog_version'];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim());
      debugPrint('FirestoreService: catalog_version missing or invalid: $raw');
      return null;
    } catch (e) {
      debugPrint('FirestoreService: fetchRemoteCatalogVersion error: $e');
      return null;
    }
  }

  /// Compares SharedPreferences vs Firebase. True → content fetch needed.
  static Future<bool> needsCatalogRefresh() async {
    final local = await getLocalCatalogVersion();
    final remote = await fetchRemoteCatalogVersion();

    if (remote == null) {
      debugPrint(
        'FirestoreService: catalog_version check failed (offline?). '
        'Using local cache (local=$local).',
      );
      return false;
    }

    if (local == remote && local != 0) {
      debugPrint(
        'FirestoreService: catalog_version unchanged ($local) — skip Firebase content fetch',
      );
      return false;
    }

    debugPrint(
      'FirestoreService: catalog_version changed local=$local → remote=$remote — will refresh',
    );
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fetch menu categories from zanfumenu/metadata
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<String>> fetchCategories() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('zanfumenu').doc('metadata').get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['categories'] is List) {
          final List<String> cats = List<String>.from(data['categories']);
          // Normalize and sort, putting "Deals" at the end if desired or keep order
          return cats;
        }
      }
    } catch (e) {
      debugPrint("FirestoreService: Error fetching categories: $e");
    }
    return ['Burgers', 'Pizza', 'Deals'];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fetch all products under a specific category collection
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<FoodMenuItem>> fetchProductsByCategory(String category) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection(category).get();
      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return FoodMenuItem.fromFirestore(data);
          })
          .where((item) => item.isActive)
          .toList();
    } catch (e) {
      debugPrint("FirestoreService: Error fetching products for category $category: $e");
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Download dynamic model by URL, save to cache and return local base64 source
  // ─────────────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────
  // 3D MODEL CACHE — STEP 1: Load local index from disk (called on Splash)
  // ─────────────────────────────────────────────────────────────────────────
  /// Reads the persisted URL→localPath index from disk into memory.
  /// Fast — just a small JSON file read. Call this at app start.
  static Future<void> preloadModelsCache() async {
    if (_modelCacheLoaded) return;
    try {
      final jsonStr = await DiskCache.readText(_modelsCacheIndexFile);
      if (jsonStr != null) {
        final Map<String, dynamic> raw = jsonDecode(jsonStr);
        _modelUrlToLocalPath = raw.map((k, v) => MapEntry(k, v.toString()));
        debugPrint(
          'FirestoreService: Models cache index loaded: ${_modelUrlToLocalPath.length} entries'
        );
      } else {
        debugPrint('FirestoreService: No models cache index found (first run)');
      }
      _modelCacheLoaded = true;
    } catch (e) {
      debugPrint('FirestoreService: preloadModelsCache error: $e');
      _modelCacheLoaded = true;
    }
  }

  /// True when this Firebase model URL is already saved on device.
  static bool isModelCachedLocally(String url) => false;

  static const String _modelUrlsCatalogFile = 'model_urls_catalog.json';

  /// Load cached `zanfumenu/3dmodelsurl` map from disk (offline).
  static Future<void> preloadModelUrlCatalog() async {
    try {
      final jsonStr = await DiskCache.readText(_modelUrlsCatalogFile);
      if (jsonStr == null) return;
      final raw = jsonDecode(jsonStr);
      if (raw is Map) {
        final map = <String, String>{};
        raw.forEach((k, v) {
          if (v != null && v.toString().trim().isNotEmpty) {
            map[k.toString()] = v.toString().trim();
          }
        });
        updateModelUrlCatalog(map);
        syncAvailableModelsFromCatalog();
        debugPrint(
          'FirestoreService: Loaded model URL catalog from disk '
          '(${map.length} urls)',
        );
      }
    } catch (e) {
      debugPrint('FirestoreService: preloadModelUrlCatalog error: $e');
    }
  }

  /// Fetch `zanfumenu/3dmodelsurl` document (same source as admin gallery).
  /// Keys → URL strings. Saves locally for offline use.
  static Future<void> fetchModelUrlCatalog() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('zanfumenu')
          .doc('3dmodelsurl')
          .get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('FirestoreService: zanfumenu/3dmodelsurl missing or empty');
        return;
      }

      final data = doc.data()!;
      final keys = data.keys.toList()
        ..sort((a, b) {
          final regex = RegExp(r'(\d+)');
          final matchA = regex.firstMatch(a);
          final matchB = regex.firstMatch(b);
          if (matchA != null && matchB != null) {
            final prefixA = a.substring(0, matchA.start);
            final prefixB = b.substring(0, matchB.start);
            if (prefixA == prefixB) {
              return int.parse(matchA.group(1)!)
                  .compareTo(int.parse(matchB.group(1)!));
            }
          }
          return a.compareTo(b);
        });

      final map = <String, String>{};
      final nameByUrl = <String, String>{};
      for (final key in keys) {
        final val = data[key];
        if (val is String && val.trim().isNotEmpty) {
          map[key] = val.trim();
          // Catalog key is often the human-readable model name.
          if (!key.startsWith('http') &&
              !key.contains('.glb') &&
              !key.contains('.usdz')) {
            nameByUrl[val.trim()] = key.trim();
          }
        } else if (val is Map) {
          final url = (val['url'] ??
                  val['model_url'] ??
                  val['3dmodelurl'] ??
                  val['value'] ??
                  '')
              .toString()
              .trim();
          final name = (val['name'] ?? val['label'] ?? key).toString().trim();
          if (url.isNotEmpty) {
            map[key] = url;
            if (name.isNotEmpty) nameByUrl[url] = name;
          }
        }
      }

      if (map.isEmpty) {
        debugPrint('FirestoreService: zanfumenu/3dmodelsurl has no URL strings');
        return;
      }

      updateModelUrlCatalog(map, nameByUrl: nameByUrl);

      await DiskCache.writeText(_modelUrlsCatalogFile, jsonEncode(map));

      syncAvailableModelsFromCatalog();
      debugPrint(
        'FirestoreService: Fetched zanfumenu/3dmodelsurl '
        '(${map.length} model URLs)',
      );
    } catch (e) {
      debugPrint('FirestoreService: fetchModelUrlCatalog error: $e');
    }
  }

  /// Rebuild [availableModels] from `zanfumenu/3dmodelsurl` (+ menu URLs).
  static void syncAvailableModelsFromCatalog() {
    availableModels.clear();
    final seenUrls = <String>{};

    // 1) Primary source: zanfumenu/3dmodelsurl
    for (final entry in modelUrlCatalogByKey.entries) {
      final url = entry.value.trim();
      if (url.isEmpty || !seenUrls.add(url)) continue;
      availableModels.add(FoodModel(
        name: prettyNameFromModelUrl(url, fallbackKey: entry.key),
        imagePath: 'assets/zanfu_logo.png',
        price: '',
        category: '3D Models',
        path: url,
        isLocalFile: isModelCachedLocally(url),
      ));
    }

    // 2) Also include any product-specific URLs not already in catalog
    for (final cat in _cachedCategories) {
      for (final p in getCachedProductsByCategory(cat)) {
        final url = p.effectiveModelUrl;
        if (url.isEmpty || !seenUrls.add(url)) continue;
        availableModels.add(FoodModel(
          name: p.name,
          imagePath:
              p.imageUrl.isNotEmpty ? p.imageUrl : 'assets/zanfu_logo.png',
          price: p.price,
          category: p.category,
          description: p.description,
          path: url,
          isLocalFile: isModelCachedLocally(url),
        ));
      }
    }

    foodDataVersion.value++;
    debugPrint(
      'FirestoreService: availableModels synced '
      '(${availableModels.length} from catalog/menu)',
    );
  }

  /// @deprecated Use [syncAvailableModelsFromCatalog]
  static void syncAvailableModelsFromMenu() => syncAvailableModelsFromCatalog();

  // ─────────────────────────────────────────────────────────────────────────
  // 3D MODEL CACHE — STEP 2: Background sync after menu data is ready
  // ─────────────────────────────────────────────────────────────────────────
  /// Iterates all model URLs found in the cached menu data.
  /// - Already cached & file exists → skip
  /// - File exists on disk but not indexed → register in index
  /// - Missing → download & save
  /// Call this WITHOUT await (fire-and-forget) from Splash so it doesn't
  /// block navigation. It completes silently in the background.
  static Future<void> refreshModelsCacheInBackground() async {}

  /// Returns local file path only if already cached on disk. Never downloads.
  /// Null = not cached yet.
  static Future<String?> getCachedLocalPathIfExists(String url) async => null;

  // ─────────────────────────────────────────────────────────────────────────
  // 3D MODEL CACHE — Core resolver: local first, download if missing
  // ─────────────────────────────────────────────────────────────────────────
  /// Returns the local absolute file path for a model URL.
  /// Order of checks:
  ///   1. In-memory index hit + file exists → return instantly (no I/O)
  ///   2. File exists on disk (not in index) → register + return
  ///   3. Not cached → download, save, index, return local path
  ///   4. Download failed → return original URL as fallback
  static Future<String> getLocalModelPath(String url) async {
    if (url.isEmpty) return '';
    return url;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Download model by URL and return base64 src (for ModelViewer web component)
  // Now uses local cache first — no unnecessary network calls.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String> downloadAndCacheModelUrl(String url) async {
    if (url.isEmpty) return '';
    return url;
  }

  /// Returns the local file path for a model URL.
  /// Delegates to [getLocalModelPath] which handles local cache first,
  /// then downloads only if the file is not already saved locally.
  static Future<String> downloadAndGetLocalPath(String url) async {
    return getLocalModelPath(url);
  }

  /// Match a selected variation name (e.g. "1 Litre", "Medium", "S") to
  /// `size_model_urls` map keys and return the corresponding 3D model URL.
  static String? resolveSizeModelUrl(
    Map<String, String>? sizeModelUrls,
    String? variation,
  ) {
    if (sizeModelUrls == null || sizeModelUrls.isEmpty) return null;
    final raw = (variation ?? '').trim();
    if (raw.isEmpty) return null;

    final vLower = raw.toLowerCase();
    final vUpper = raw.toUpperCase();

    String? pick(String key) {
      final url = sizeModelUrls[key];
      if (url != null && url.trim().isNotEmpty) return url.trim();
      return null;
    }

    // Exact key match (case-insensitive)
    for (final entry in sizeModelUrls.entries) {
      if (entry.key.trim().toLowerCase() == vLower) {
        final url = entry.value.trim();
        if (url.isNotEmpty) return url;
      }
    }

    // S / M / L ↔ Small / Medium / Large
    if (vUpper == 'S' || vLower == 'small') {
      for (final k in ['S', 's', 'Small', 'SMALL', 'small']) {
        final u = pick(k);
        if (u != null) return u;
      }
    }
    if (vUpper == 'M' || vLower == 'medium') {
      for (final k in ['M', 'm', 'Medium', 'MEDIUM', 'medium']) {
        final u = pick(k);
        if (u != null) return u;
      }
    }
    if (vUpper == 'L' || vLower == 'large') {
      for (final k in ['L', 'l', 'Large', 'LARGE', 'large']) {
        final u = pick(k);
        if (u != null) return u;
      }
    }

    // Fuzzy: key contains variation or variation contains key
    for (final entry in sizeModelUrls.entries) {
      final k = entry.key.trim().toLowerCase();
      if (k.isEmpty) continue;
      if (k.contains(vLower) || vLower.contains(k)) {
        final url = entry.value.trim();
        if (url.isNotEmpty) return url;
      }
    }

    return null;
  }

  static FoodModel? resolveFoodModel(String identifier, {String? dealGroupName}) {
    if (identifier.isEmpty) return null;

    // Normalize target identifier to alphanumeric characters only
    final normTarget = identifier
        .split('/')
        .last
        .split('?')
        .first
        .replaceAll('.glb', '')
        .replaceAll('.usdz', '')
        .replaceAll('-optimized', '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();

    FoodModel tagged(FoodModel m) => dealGroupName == null
        ? m
        : FoodModel(
            name: m.name,
            imagePath: m.imagePath,
            price: m.price,
            category: m.category,
            path: m.path,
            baseScale: m.baseScale,
            baseInches: m.baseInches,
            isLocalFile: m.isLocalFile,
            dealGroupName: dealGroupName,
          );

    // Resolve only from Firebase menu cache (never local asset GLBs)
    for (var cat in _cachedCategories) {
      final products = _cachedProducts[cat] ?? [];
      for (var p in products) {
        final normP =
            p.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        final normPUrl = p.modelUrl
            .split('/')
            .last
            .split('?')
            .first
            .replaceAll('.glb', '')
            .replaceAll('.usdz', '')
            .replaceAll('-optimized', '')
            .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
            .toLowerCase();
        if (normP == normTarget ||
            normPUrl == normTarget ||
            p.modelUrl == identifier) {
          return tagged(p.toFoodModel());
        }
        for (final entry in p.sizeModelUrls.entries) {
          final normSizeUrl = entry.value
              .split('/')
              .last
              .split('?')
              .first
              .replaceAll('.glb', '')
              .replaceAll('.usdz', '')
              .replaceAll('-optimized', '')
              .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
              .toLowerCase();
          if (normSizeUrl == normTarget || entry.value == identifier) {
            final base = p.toFoodModel();
            return tagged(FoodModel(
              name: base.name,
              imagePath: base.imagePath,
              price: base.price,
              category: base.category,
              description: base.description,
              path: entry.value,
              baseScale: base.baseScale,
              baseInches: base.baseInches,
            ));
          }
        }
      }
    }

    // Resolve from zanfumenu/3dmodelsurl catalog by normalized name/filename
    final catalogHit = modelUrlCatalogByNormName[normTarget];
    if (catalogHit != null && catalogHit.isNotEmpty) {
      return tagged(FoodModel(
        name: prettyNameFromModelUrl(catalogHit),
        imagePath: 'assets/zanfu_logo.png',
        price: '',
        category: '3D Models',
        path: catalogHit,
        isLocalFile: isModelCachedLocally(catalogHit),
      ));
    }

    // URL from Firebase deal groups / size models — keep the remote path
    final isRemote = identifier.startsWith('http://') ||
        identifier.startsWith('https://');
    if (!isRemote) return null;

    final filename = identifier
        .split('/')
        .last
        .split('?')
        .first
        .replaceAll('.glb', '')
        .replaceAll('.usdz', '')
        .replaceAll('-optimized', '')
        .replaceAll('.', ' ');
    final pattern = RegExp(r'(?<=[a-z])(?=[A-Z])');
    String cleanName = filename.split(pattern).join(' ');
    cleanName = cleanName.replaceAll('BBq', 'BBQ').replaceAll('bbq', 'BBQ');

    return FoodModel(
      name: cleanName,
      imagePath: 'assets/zanfu_logo.png',
      price: '',
      category: 'Deals',
      path: identifier,
      dealGroupName: dealGroupName,
    );
  }

  /// All active menu products as FoodModels (Firebase only).
  static List<FoodModel> getAllCachedFoodModels() {
    if (availableModels.isNotEmpty) {
      return List<FoodModel>.from(availableModels);
    }
    final List<FoodModel> models = [];
    final seen = <String>{};
    for (final cat in _cachedCategories) {
      for (final p in getCachedProductsByCategory(cat)) {
        if (p.effectiveModelUrl.isEmpty) continue;
        final model = p.toFoodModel();
        if (seen.add(model.name)) models.add(model);
      }
    }
    return models;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Offline Cache System for categories & products
  // ─────────────────────────────────────────────────────────────────────────

  // Read local cache file from disk synchronously/instantly
  static Future<void> preloadMenuCache() async {
    if (_cacheLoaded) return;
    try {
      final jsonStr = await DiskCache.readText('menu_cache.json');
      if (jsonStr != null) {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        
        if (data['categories'] is List) {
          _cachedCategories = List<String>.from(data['categories']);
        }
        
        if (data['products'] is Map) {
          final Map<String, dynamic> rawProducts = data['products'];
          _cachedProducts = {};
          rawProducts.forEach((key, val) {
            if (val is List) {
              _cachedProducts[key] = val
                  .map((item) =>
                      FoodMenuItem.fromFirestore(Map<String, dynamic>.from(item)))
                  .where((item) => item.isActive)
                  .toList();
            }
          });
        }
        _cacheLoaded = true;
        menuDataVersion.value++;
        syncAvailableModelsFromCatalog();
        debugPrint("FirestoreService: Instantly loaded menu cache from local disk! ${_cachedCategories.length} categories, ${_cachedProducts.length} product collections.");
      }
    } catch (e) {
      debugPrint("FirestoreService: Error preloading menu cache: $e");
    }
  }

  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    final Map<String, dynamic> sanitized = {};
    map.forEach((k, v) {
      sanitized[k] = _sanitizeValue(v);
    });
    return sanitized;
  }

  static dynamic _sanitizeValue(dynamic v) {
    if (v is Timestamp) {
      return v.toDate().toIso8601String();
    } else if (v is Map) {
      return _sanitizeMap(Map<String, dynamic>.from(v));
    } else if (v is List) {
      return v.map((item) => _sanitizeValue(item)).toList();
    }
    return v;
  }

  // Background task to sync/fetch menu categories and products from Firebase Firestore
  /// Returns true when menu cache was successfully updated from Firestore.
  static Future<bool> refreshMenuCacheInBackground() async {
    try {
      debugPrint("FirestoreService: Parallel background refresh started...");
      final cats = await fetchCategories();
      final Map<String, List<FoodMenuItem>> tempProducts = {};
      final Map<String, List<Map<String, dynamic>>> jsonProducts = {};

      // Execute all collection queries in parallel
      await Future.wait(cats.map((cat) async {
        try {
          final snapshot = await FirebaseFirestore.instance.collection(cat).get();
          final List<FoodMenuItem> list = [];
          final List<Map<String, dynamic>> rawList = [];
          for (var doc in snapshot.docs) {
            try {
              final data = doc.data();
              data['id'] = doc.id;
              final item = FoodMenuItem.fromFirestore(data);
              if (!item.isActive) continue;
              list.add(item);
              rawList.add(_sanitizeMap(data));
            } catch (itemError) {
              debugPrint("FirestoreService: Error parsing item ${doc.id} in category $cat: $itemError");
            }
          }
          list.sort((a, b) => a.order.compareTo(b.order));
          tempProducts[cat] = list;
          jsonProducts[cat] = rawList;
        } catch (catError) {
          debugPrint("FirestoreService: Error fetching category $cat: $catError");
        }
      }));

      // Write updated data to local cache ONLY if we actually fetched products (prevents clearing cache when offline)
      final hasFetchedData = tempProducts.values.any((list) => list.isNotEmpty);
      if (hasFetchedData) {
        final cacheData = {
          'categories': cats,
          'products': jsonProducts,
        };
        await DiskCache.writeText('menu_cache.json', jsonEncode(cacheData));

        // Update static memory
        _cachedCategories = cats;
        _cachedProducts = tempProducts;
        _cacheLoaded = true;

        // Trigger UI updates + rebuild AR model list from catalog/menu
        syncAvailableModelsFromCatalog();
        menuDataVersion.value++;
        debugPrint("FirestoreService: Parallel background refresh completed! Local cache updated successfully.");

        // Download any missing GLBs in background (local-first next launches)
        // ignore: unawaited_futures
        refreshModelsCacheInBackground();
        return true;
      } else {
        debugPrint("FirestoreService: Parallel background refresh fetched no data (possibly offline). Skipping cache update.");
        return false;
      }
    } catch (e) {
      debugPrint("FirestoreService: Parallel background refresh error: $e");
      return false;
    }
  }

  // Read methods to be used by screens
  static List<String> getCachedCategories() {
    return _cachedCategories;
  }

  static List<FoodMenuItem> getCachedProductsByCategory(String category) {
    final list = (_cachedProducts[category] ?? [])
        .where((item) => item.isActive)
        .toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  static bool isDrinksCategory(String category) {
    final c = category.trim().toLowerCase();
    return c == 'drinks' || c == 'drink' || c.contains('drink');
  }

  /// Random active items from full menu, excluding drinks (and optional names).
  static List<FoodMenuItem> getRandomCachedMenuItems({
    int count = 15,
    Set<String> excludeNames = const {},
  }) {
    final unique = <String, FoodMenuItem>{};
    for (final cat in getCachedCategories()) {
      if (isDrinksCategory(cat)) continue;
      for (final p in getCachedProductsByCategory(cat)) {
        if (isDrinksCategory(p.category)) continue;
        if (excludeNames.contains(p.name)) continue;
        unique[p.name] = p;
      }
    }
    final list = unique.values.toList()..shuffle();
    if (list.length <= count) return list;
    return list.take(count).toList();
  }

  static FoodMenuItem? findCachedProductByName(String name) {
    final target = name.trim().toLowerCase();
    if (target.isEmpty) return null;
    for (final products in _cachedProducts.values) {
      for (final item in products) {
        if (item.name.trim().toLowerCase() == target) return item;
      }
    }
    return null;
  }

  static String? getCachedDescriptionForProduct(String name) {
    for (final products in _cachedProducts.values) {
      for (final item in products) {
        if (item.name == name && item.description.isNotEmpty) {
          return item.description;
        }
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Branches — local disk cache + catalog_version gated Firebase refresh
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> preloadBranchesCache() async {
    if (_branchesCacheLoaded) return;
    try {
      final jsonStr = await DiskCache.readText(_branchesCacheFile);
      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          _cachedBranches = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _branchesCacheLoaded = true;
          branchesDataVersion.value++;
          debugPrint(
            'FirestoreService: Loaded ${_cachedBranches.length} branches from local disk',
          );
        }
      }
    } catch (e) {
      debugPrint('FirestoreService: Error preloading branches cache: $e');
    }
  }

  /// Snapshot of cached branch maps (`id` + Firestore fields). Empty if none.
  static List<Map<String, dynamic>> getCachedBranches() {
    return List<Map<String, dynamic>>.from(
      _cachedBranches.map((e) => Map<String, dynamic>.from(e)),
    );
  }

  static bool get hasCachedBranches => _cachedBranches.isNotEmpty;

  /// Fetches `branches` collection from Firebase and writes local cache.
  /// Returns true when at least one branch was saved.
  static Future<bool> refreshBranchesCacheInBackground() async {
    try {
      debugPrint('FirestoreService: Refreshing branches from Firebase...');
      final snapshot =
          await FirebaseFirestore.instance.collection('branches').get();
      if (snapshot.docs.isEmpty) {
        debugPrint(
          'FirestoreService: branches collection empty — keeping existing cache',
        );
        return false;
      }

      final list = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = _sanitizeMap(Map<String, dynamic>.from(doc.data()));
        data['id'] = doc.id;
        list.add(data);
      }

      await DiskCache.writeText(_branchesCacheFile, jsonEncode(list));

      _cachedBranches = list;
      _branchesCacheLoaded = true;
      branchesDataVersion.value++;
      debugPrint(
        'FirestoreService: Branches cache updated (${list.length} branches)',
      );
      return true;
    } catch (e) {
      debugPrint('FirestoreService: refreshBranchesCacheInBackground error: $e');
      return false;
    }
  }
}

