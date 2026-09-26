class FoodModel {
  final String name;
  final String imagePath;
  final String path;
  final String price;
  final String category;
  final String description;
  final double baseScale;
  final double baseInches;
  final bool isLocalFile; // true = downloaded to device storage, false = asset
  final String? dealGroupName; // Deal name grouping identifier
  /// Selected size/variation label for AR bottom bar (e.g. "1 Litre", "Medium").
  final String? sizeLabel;
  /// How many copies to auto-place in AR for this line item.
  final int arQuantity;
  /// Firestore: `discount_type` — e.g. percent / rs / fixed.
  final String discountType;
  /// Firestore: `disc_price` — percent value or flat Rs amount.
  final String discPrice;
  /// Precomputed first-size price (after deal_model_types order) for menu tiles.
  final double? listPrice;
  double currentInches;

  FoodModel({
    required this.name,
    required this.imagePath,
    required this.price,
    required this.category,
    this.description = '',
    this.path = "",
    this.baseScale = 1.0,
    this.baseInches = 12.0,
    this.isLocalFile = false,
    this.dealGroupName,
    this.sizeLabel,
    this.arQuantity = 1,
    this.discountType = '',
    this.discPrice = '',
    this.listPrice,
  }) : currentInches = baseInches;

  double get calculatedScale => (currentInches / baseInches) * baseScale;

  /// True when [path] points at a placeable 3D asset (.glb / .usdz).
  bool get is3DAvailable => isGlbOrUsdzUrl(path);

  /// Remote/local URL is a GLB or USDZ model (ignores query string).
  static bool isGlbOrUsdzUrl(String? url) {
    if (url == null) return false;
    final path = url.trim().split('?').first.toLowerCase();
    if (path.isEmpty) return false;
    return path.endsWith('.glb') || path.endsWith('.usdz');
  }

  /// Numeric discount value from [discPrice].
  double get discountValue {
    final raw = discPrice.trim().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(raw) ?? 0;
  }

  bool get hasDiscount => discountValue > 0;

  bool get isPercentDiscount {
    final t = discountType.trim().toLowerCase();
    return t.contains('percent') ||
        t == '%' ||
        t == 'pct' ||
        t == 'percentage';
  }

  /// Badge text for menu cards: "20% OFF" or "Rs 50 OFF".
  String get discountBadgeLabel {
    if (!hasDiscount) return '';
    final v = discountValue;
    final whole = v == v.roundToDouble();
    final numStr = whole ? v.toInt().toString() : v.toStringAsFixed(0);
    if (isPercentDiscount) return '$numStr% OFF';
    return 'Rs $numStr OFF';
  }

  /// Apply this item's discount to an original variation price.
  double discountedFrom(double original) {
    if (!hasDiscount || original <= 0) return original;
    final v = discountValue;
    if (isPercentDiscount) {
      return (original * (1 - (v / 100))).clamp(0, original);
    }
    return (original - v).clamp(0, original);
  }

  double discountAmountFrom(double original) {
    final d = discountedFrom(original);
    return (original - d).clamp(0, original);
  }

  /// Same basis as DetailScreen's first selected size — not Medium-biased.
  double get displayOriginalPrice {
    if (listPrice != null && listPrice! > 0) return listPrice!;

    final variations = parsePriceVariations(price);
    if (variations.isNotEmpty) {
      return variations.first.price;
    }
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(price);
    return double.tryParse(m?.group(1) ?? '') ?? 0;
  }

  /// Parses `"S 590 | M 890 | L 1299"` style strings (last number = price).
  static List<({String name, double price})> parsePriceVariations(
    String priceStr,
  ) {
    final result = <({String name, double price})>[];
    if (!priceStr.contains('|')) {
      final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(priceStr);
      if (match != null) {
        result.add((
          name: 'Regular',
          price: double.tryParse(match.group(1)!) ?? 0,
        ));
      }
      return result;
    }
    for (final part in priceStr.split('|')) {
      final clean = part.trim();
      final match =
          RegExp(r'^(.+?)\s+(\d+(?:\.\d+)?)\s*$').firstMatch(clean);
      if (match == null) continue;
      var rawName = match
          .group(1)!
          .trim()
          .replaceAll(RegExp(r'\b(Rs|PKR)\b', caseSensitive: false), '')
          .trim();
      switch (rawName.toUpperCase()) {
        case 'S':
          rawName = 'Small';
          break;
        case 'M':
          rawName = 'Medium';
          break;
        case 'L':
          rawName = 'Large';
          break;
      }
      final p = double.tryParse(match.group(2)!) ?? 0;
      if (p > 0) result.add((name: rawName, price: p));
    }
    return result;
  }

  /// Returns correct src for ModelViewer:
  /// - local device file: "file:///path/to/file.glb"
  /// - remote / asset path: as stored in [path]
  String get modelSrc => isLocalFile ? 'file://$path' : path;

  FoodModel copyWith({
    String? name,
    String? imagePath,
    String? path,
    String? price,
    String? category,
    String? description,
    double? baseScale,
    double? baseInches,
    bool? isLocalFile,
    String? dealGroupName,
    String? sizeLabel,
    int? arQuantity,
    String? discountType,
    String? discPrice,
    double? listPrice,
  }) {
    return FoodModel(
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      path: path ?? this.path,
      price: price ?? this.price,
      category: category ?? this.category,
      description: description ?? this.description,
      baseScale: baseScale ?? this.baseScale,
      baseInches: baseInches ?? this.baseInches,
      isLocalFile: isLocalFile ?? this.isLocalFile,
      dealGroupName: dealGroupName ?? this.dealGroupName,
      sizeLabel: sizeLabel ?? this.sizeLabel,
      arQuantity: arQuantity ?? this.arQuantity,
      discountType: discountType ?? this.discountType,
      discPrice: discPrice ?? this.discPrice,
      listPrice: listPrice ?? this.listPrice,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'imagePath': imagePath,
        'path': path,
        'price': price,
        'category': category,
        'description': description,
        'baseScale': baseScale,
        'baseInches': baseInches,
        'isLocalFile': isLocalFile,
        'dealGroupName': dealGroupName,
        'sizeLabel': sizeLabel,
        'arQuantity': arQuantity,
        'discountType': discountType,
        'discPrice': discPrice,
        'listPrice': listPrice,
      };

  factory FoodModel.fromJson(Map<String, dynamic> json) {
    return FoodModel(
      name: json['name'] as String? ?? '',
      imagePath: json['imagePath'] as String? ?? '',
      path: json['path'] as String? ?? '',
      price: json['price'] as String? ?? '',
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      baseScale: (json['baseScale'] as num?)?.toDouble() ?? 1.0,
      baseInches: (json['baseInches'] as num?)?.toDouble() ?? 12.0,
      isLocalFile: json['isLocalFile'] as bool? ?? false,
      dealGroupName: json['dealGroupName'] as String?,
      sizeLabel: json['sizeLabel'] as String?,
      arQuantity: (json['arQuantity'] as num?)?.toInt() ?? 1,
      discountType: json['discountType']?.toString() ?? '',
      discPrice: json['discPrice']?.toString() ?? '',
      listPrice: (json['listPrice'] as num?)?.toDouble(),
    );
  }
}
