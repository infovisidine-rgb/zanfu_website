import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/disk_cache.dart';
import 'cart_controller.dart';
import '../models/menu_item_model.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import '../services/branch_locator.dart';

class OrderItem {
  final String name;
  final String imagePath;
  final String price;
  final int quantity;
  final String? selectedVariation;
  final Set<String> selectedToppings;
  /// Deal group choices (flavors / sizes / drinks), in group order.
  final List<String> selectedDealOptions;

  OrderItem({
    required this.name,
    required this.imagePath,
    required this.price,
    required this.quantity,
    this.selectedVariation,
    required this.selectedToppings,
    this.selectedDealOptions = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'imagePath': imagePath,
      'price': price,
      'unitPrice': double.tryParse(price) ?? 0,
      'quantity': quantity,
      'selectedVariation': selectedVariation,
      'selectedToppings': selectedToppings.toList(),
      'selectedDealOptions': selectedDealOptions,
    };
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final dealsRaw =
        json['selectedDealOptions'] ?? json['dealOptions'] ?? json['choices'];
    return OrderItem(
      name: json['name'] ?? '',
      imagePath: (json['imagePath'] ??
              json['imageUrl'] ??
              json['image'] ??
              json['img'] ??
              '')
          .toString(),
      price: json['price'] ?? '',
      quantity: json['quantity'] ?? 1,
      selectedVariation: json['selectedVariation'],
      selectedToppings: Set<String>.from(json['selectedToppings'] ?? []),
      selectedDealOptions: dealsRaw is List
          ? dealsRaw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
          : const [],
    );
  }
}

class OrderModel {
  final String orderId;
  final List<OrderItem> items;
  final double totalAmount;
  final double tax;
  final double? deliveryFee;
  /// Dine-in service charge — set by restaurant after order is placed.
  final double? serviceCharge;
  final DateTime orderDate;
  final String status;
  final String deliveryAddress;
  final String deliveryInstructions;
  final String specialInstructions;
  final String customerName;
  final String customerPhone;
  final String userId;
  final String orderType;
  final String riderName;
  final String riderPhone;
  final String tableNumber;
  final String customerCurrentAddress;
  final String branchName;
  /// Branch street address (shown under pickup branch name).
  final String branchAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  /// Reason when order is cancelled or declined (from Firebase).
  final String statusReason;

  OrderModel({
    required this.orderId,
    required this.items,
    required this.totalAmount,
    required this.tax,
    this.deliveryFee,
    this.serviceCharge,
    required this.orderDate,
    required this.status,
    required this.deliveryAddress,
    required this.deliveryInstructions,
    this.specialInstructions = '',
    required this.customerName,
    required this.customerPhone,
    required this.userId,
    this.orderType = 'Delivery',
    this.riderName = '',
    this.riderPhone = '',
    this.tableNumber = '',
    this.customerCurrentAddress = '',
    this.branchName = '',
    this.branchAddress = '',
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.statusReason = '',
  });

  static String normalizeStatus(String? raw, {String orderType = 'Delivery'}) {
    final s = (raw ?? '').trim().toLowerCase();
    final type = orderType.trim().toLowerCase();
    final isPickup = type.contains('pickup') || type.contains('takeaway');
    final isDineIn = type.contains('dine');

    if (s.contains('cancel')) return 'Cancelled';
    if (s.contains('decline') || s.contains('reject')) return 'Declined';

    if (isPickup) {
      if (s.isEmpty) return 'Processing';
      if (s.contains('ready')) return 'Ready for Pickup';
      if (s.contains('picked') || s == 'pick' || s == 'picked up') {
        return 'Picked';
      }
      if (s.contains('prepar')) return 'Order Preparing';
      // Confirm auto-advances to the next stage (Preparing).
      if (s.contains('confirm')) return 'Order Preparing';
      if (s.contains('process')) return 'Processing';
      return raw!.trim();
    }

    if (isDineIn) {
      if (s.isEmpty) return 'Processing';
      // Dine-in: "done/complete" ka UI mein matlab "Served" hi rakha jaye
      // taake Served last step ho.
      if (s.contains('complete') ||
          s.contains('done') ||
          s.contains('finish')) {
        return 'Served';
      }
      if (s.contains('serv')) return 'Served';
      if (s.contains('prepar')) return 'Order Preparing';
      // Confirm auto-advances to the next stage (Preparing).
      if (s.contains('confirm')) return 'Order Preparing';
      if (s.contains('process')) return 'Processing';
      return raw!.trim();
    }

    // Delivery
    if (s.isEmpty) return 'Processing';
    if (s.contains('delivered') || s == 'deliver') return 'Delivered';
    if (s.contains('out') && (s.contains('deliver') || s.contains('way'))) {
      return 'Out for Delivery';
    }
    if (s == 'on the way') return 'Out for Delivery';
    // Some backends store final state as "Delivery" / "Deliver..." (without
    // "out"/"way"). In that case we treat it as delivered.
    if (s == 'delivery' ||
        (s.contains('deliver') &&
            !s.contains('out') &&
            !s.contains('way'))) {
      return 'Delivered';
    }
    if (s.contains('prepar')) return 'Order Preparing';
    // Confirm auto-advances to the next stage (Preparing).
    if (s.contains('confirm')) return 'Order Preparing';
    if (s.contains('process')) return 'Processing';
    return raw!.trim();
  }

  /// Steps for the order-history status tracker (excludes Cancelled).
  /// Through [Order Preparing] all order types share the same early steps.
  static List<String> statusStepsFor(String orderType) {
    final type = orderType.trim().toLowerCase();
    if (type.contains('pickup') || type.contains('takeaway')) {
      return const [
        'Processing',
        'Order Confirm',
        'Order Preparing',
        'Ready for Pickup',
        'Picked',
      ];
    }
    if (type.contains('dine')) {
      return const [
        'Processing',
        'Order Confirm',
        'Order Preparing',
        'Served',
      ];
    }
    return const [
      'Processing',
      'Order Confirm',
      'Order Preparing',
      'Out for Delivery',
      'Delivered',
    ];
  }

  static String initialStatusFor(String orderType) {
    return 'Processing';
  }

  /// Final orders are kept locally and not re-fetched from Firebase.
  bool get isFinalStatus {
    final s = status.toLowerCase();
    return s.contains('delivered') ||
        s.contains('cancel') ||
        s.contains('decline') ||
        s.contains('reject') ||
        s.contains('completed') ||
        s.contains('served') ||
        s == 'picked' ||
        s.contains('picked');
  }

  bool get hasStatusReason {
    if (statusReason.trim().isEmpty) return false;
    final s = status.toLowerCase();
    return s.contains('cancel') ||
        s.contains('decline') ||
        s.contains('reject');
  }

  Map<String, dynamic> toJson() {
    return {
      'orderId': orderId,
      'items': items.map((i) => i.toJson()).toList(),
      'totalAmount': totalAmount,
      'tax': tax,
      if (deliveryFee != null) 'deliveryFee': deliveryFee,
      if (serviceCharge != null) 'serviceCharge': serviceCharge,
      'orderDate': orderDate.toIso8601String(),
      'status': status,
      'deliveryAddress': deliveryAddress,
      'deliveryInstructions': deliveryInstructions,
      'specialInstructions': specialInstructions,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'userId': userId,
      'orderType': orderType,
      'riderName': riderName,
      'riderPhone': riderPhone,
      'tableNumber': tableNumber,
      'branchName': branchName,
      'branchAddress': branchAddress,
      if (deliveryLatitude != null) 'deliveryLatitude': deliveryLatitude,
      if (deliveryLongitude != null) 'deliveryLongitude': deliveryLongitude,
      if (statusReason.trim().isNotEmpty) 'reason': statusReason,
    };
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    final rider = json['rider'];
    String riderName =
        json['riderName']?.toString() ?? json['rider_name']?.toString() ?? '';
    String riderPhone =
        json['riderPhone']?.toString() ??
        json['rider_phone']?.toString() ??
        json['riderNumber']?.toString() ??
        '';
    if (rider is Map) {
      if (riderName.isEmpty) {
        riderName = (rider['name'] ?? rider['riderName'] ?? '').toString();
      }
      if (riderPhone.isEmpty) {
        riderPhone =
            (rider['phone'] ?? rider['number'] ?? rider['riderPhone'] ?? '')
                .toString();
      }
    }

    DateTime orderDate;
    final rawDate = json['orderDate'];
    if (rawDate is Timestamp) {
      orderDate = rawDate.toDate();
    } else {
      orderDate =
          DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();
    }

    final liveLoc = json['customerLiveLocation'] ?? json['liveLocation'];
    String currentAddress = json['customerCurrentAddress']?.toString() ?? '';
    if (currentAddress.isEmpty && liveLoc is Map) {
      currentAddress =
          (liveLoc['address'] ??
                  liveLoc['currentAddress'] ??
                  liveLoc['deliveryAddress'] ??
                  '')
              .toString();
    }

    double? parseOptionalDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    String parseOptionalReason(dynamic value) {
      if (value == null) return '';
      return value.toString().trim();
    }

    final deliveryFee = parseOptionalDouble(
      json['deliveryFee'] ?? json['delivery_fee'] ?? json['deliveryCharges'],
    );
    final serviceCharge = parseOptionalDouble(
      json['serviceCharge'] ??
          json['service_charge'] ??
          json['serviceCharges'] ??
          json['service_charges'] ??
          json['serviceFee'] ??
          json['service_fee'],
    );
    final statusReason = parseOptionalReason(
      json['reason'] ??
          json['statusReason'] ??
          json['status_reason'] ??
          json['cancelReason'] ??
          json['cancel_reason'] ??
          json['cancellationReason'] ??
          json['declineReason'] ??
          json['decline_reason'] ??
          json['rejectionReason'] ??
          json['rejection_reason'],
    );

    final liveLat = (json['deliveryLatitude'] as num?)?.toDouble() ??
        (liveLoc is Map ? (liveLoc['latitude'] as num?)?.toDouble() : null);
    final liveLng = (json['deliveryLongitude'] as num?)?.toDouble() ??
        (liveLoc is Map ? (liveLoc['longitude'] as num?)?.toDouble() : null);

    final orderType = json['orderType']?.toString() ?? 'Delivery';

    return OrderModel(
      orderId: json['orderId'] ?? json['id'] ?? '',
      items: itemsList
          .map((i) => OrderItem.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      tax: (json['tax'] as num?)?.toDouble() ?? 0.0,
      deliveryFee: deliveryFee,
      serviceCharge: serviceCharge,
      orderDate: orderDate,
      status: normalizeStatus(
        json['status']?.toString(),
        orderType: orderType,
      ),
      deliveryAddress: json['deliveryAddress'] ?? '',
      deliveryInstructions: json['deliveryInstructions'] ?? '',
      specialInstructions: json['specialInstructions']?.toString() ??
          json['special_instructions']?.toString() ??
          '',
      customerName: json['customerName'] ?? '',
      customerPhone: json['customerPhone'] ?? '',
      userId: json['userId'] ?? '',
      orderType: orderType,
      riderName: riderName,
      riderPhone: riderPhone,
      tableNumber:
          json['tableNumber']?.toString() ??
          json['table_number']?.toString() ??
          '',
      customerCurrentAddress: currentAddress,
      branchName:
          json['branchName']?.toString() ??
          json['branch_name']?.toString() ??
          json['branch']?.toString() ??
          '',
      branchAddress:
          json['branchAddress']?.toString() ??
          json['branch_address']?.toString() ??
          json['branchAddr']?.toString() ??
          '',
      deliveryLatitude: liveLat,
      deliveryLongitude: liveLng,
      statusReason: statusReason,
    );
  }

  OrderModel copyWith({
    String? status,
    String? riderName,
    String? riderPhone,
    double? deliveryFee,
    double? serviceCharge,
    String? branchName,
    String? branchAddress,
    String? customerCurrentAddress,
    String? statusReason,
  }) {
    return OrderModel(
      orderId: orderId,
      items: items,
      totalAmount: totalAmount,
      tax: tax,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      serviceCharge: serviceCharge ?? this.serviceCharge,
      orderDate: orderDate,
      status: status ?? this.status,
      deliveryAddress: deliveryAddress,
      deliveryInstructions: deliveryInstructions,
      specialInstructions: specialInstructions,
      customerName: customerName,
      customerPhone: customerPhone,
      userId: userId,
      orderType: orderType,
      riderName: riderName ?? this.riderName,
      riderPhone: riderPhone ?? this.riderPhone,
      tableNumber: tableNumber,
      customerCurrentAddress:
          customerCurrentAddress ?? this.customerCurrentAddress,
      branchName: branchName ?? this.branchName,
      branchAddress: branchAddress ?? this.branchAddress,
      deliveryLatitude: deliveryLatitude,
      deliveryLongitude: deliveryLongitude,
      statusReason: statusReason ?? this.statusReason,
    );
  }
}

class OrderController extends ChangeNotifier {
  static final OrderController _instance = OrderController._internal();
  factory OrderController() => _instance;
  OrderController._internal() {
    loadOrders();
  }

  final List<OrderModel> _orders = [];
  List<OrderModel> get orders => _orders;
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;
  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  static const _ordersCacheFile = 'orders.json';

  String _migrationPrefsKey(String uid) => 'orders_migrated_$uid';

  Future<void> _loadOrdersFromDisk() async {
    final contents = await DiskCache.readText(_ordersCacheFile);
    if (contents == null) {
      _orders.clear();
      return;
    }
    final List<dynamic> jsonList = jsonDecode(contents);
    _orders
      ..clear()
      ..addAll(
        jsonList.map(
          (item) => OrderModel.fromJson(Map<String, dynamic>.from(item)),
        ),
      );
    _orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
  }

  /// One-time migration when local cache is empty (e.g. first install / cleared data).
  Future<void> _fullSyncFromFirebase(String uid) async {
    final rootSnapshot =
        await FirebaseFirestore.instance.collection('orders').get();
    final freshOrders = <OrderModel>[];

    for (final rootDoc in rootSnapshot.docs) {
      final rootData = rootDoc.data();

      if (rootData['userId'] == uid &&
          (rootData['orderId'] != null || rootData['items'] != null)) {
        rootData['orderId'] = rootData['orderId'] ?? rootDoc.id;
        freshOrders.add(OrderModel.fromJson(rootData));
      }

      final branchOrders = await rootDoc.reference
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .get();
      for (final orderDoc in branchOrders.docs) {
        final data = orderDoc.data();
        data['orderId'] = data['orderId'] ?? orderDoc.id;
        if (data['branchName'] == null ||
            data['branchName'].toString().isEmpty) {
          data['branchName'] = (rootData['name'] ?? rootDoc.id).toString();
        }
        if ((data['branchAddress'] == null ||
                data['branchAddress'].toString().isEmpty) &&
            rootData['address'] != null) {
          data['branchAddress'] = rootData['address'].toString();
        }
        freshOrders.add(OrderModel.fromJson(data));
      }
    }

    _orders
      ..clear()
      ..addAll(freshOrders);
    _orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    await saveOrders();
    debugPrint(
      'OrderController: one-time migration loaded ${_orders.length} orders',
    );
  }

  /// Only active (non-final) orders are refreshed from Firebase.
  Future<void> _refreshActiveOrdersFromFirebase(String uid) async {
    final activeOrders = _orders.where((o) => !o.isFinalStatus).toList();
    if (activeOrders.isEmpty) {
      debugPrint('OrderController: no active orders to refresh from Firebase');
      return;
    }

    var updatedCount = 0;
    for (final order in activeOrders) {
      if (order.orderId.isEmpty) continue;

      try {
        DocumentSnapshot<Map<String, dynamic>>? snap;

        final branchDocId = _sanitizeBranchDocId(order.branchName);
        if (branchDocId.isNotEmpty && branchDocId != 'Unknown Branch') {
          snap = await FirebaseFirestore.instance
              .collection('orders')
              .doc(branchDocId)
              .collection('orders')
              .doc(order.orderId)
              .get();
        }

        // Fallback for legacy orders stored directly under /orders/{orderId}
        if (snap == null || !snap.exists) {
          snap = await FirebaseFirestore.instance
              .collection('orders')
              .doc(order.orderId)
              .get();
        }

        if (!snap.exists) continue;

        final data = Map<String, dynamic>.from(snap.data() ?? {});
        if (data['userId'] != null && data['userId'] != uid) continue;

        data['orderId'] = data['orderId'] ?? snap.id;
        if ((data['branchName'] == null ||
                data['branchName'].toString().isEmpty) &&
            order.branchName.isNotEmpty) {
          data['branchName'] = order.branchName;
        }
        if ((data['branchAddress'] == null ||
                data['branchAddress'].toString().isEmpty) &&
            order.branchAddress.isNotEmpty) {
          data['branchAddress'] = order.branchAddress;
        }

        final updated = OrderModel.fromJson(data);
        final idx = _orders.indexWhere((o) => o.orderId == order.orderId);
        if (idx < 0) continue;

        _orders[idx] = updated;
        updatedCount++;
      } catch (e) {
        debugPrint(
          'OrderController: failed to refresh ${order.orderId}: $e',
        );
      }
    }

    _orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    await saveOrders();
    debugPrint(
      'OrderController: refreshed $updatedCount active order(s) from Firebase',
    );
  }

  Future<void> loadOrders({bool showRefreshing = false}) async {
    if (showRefreshing) {
      _isRefreshing = true;
      notifyListeners();
    }
    try {
      await _loadOrdersFromDisk();

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        final migrated = prefs.getBool(_migrationPrefsKey(user.uid)) ?? false;

        if (!migrated && _orders.isEmpty) {
          await _fullSyncFromFirebase(user.uid);
          await prefs.setBool(_migrationPrefsKey(user.uid), true);
        } else {
          await _refreshActiveOrdersFromFirebase(user.uid);
        }
      }
    } catch (e) {
      debugPrint("Error loading orders: $e");
    } finally {
      _isLoaded = true;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> saveOrders() async {
    try {
      final List<Map<String, dynamic>> jsonList = _orders
          .map((o) => o.toJson())
          .toList();
      await DiskCache.writeText(_ordersCacheFile, jsonEncode(jsonList));
    } catch (e) {
      debugPrint("Error saving orders: $e");
    }
  }

  Future<bool> placeOrder({
    required List<CartItem> cartItems,
    required double totalAmount,
    required double tax,
    required String deliveryAddress,
    required String deliveryInstructions,
    String specialInstructions = '',
    required String customerName,
    required String customerPhone,
    String orderType = 'Delivery',
    String tableNumber = '',
    String customerCurrentAddress = '',
    String? branchName,
    String? branchAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? '';
    final randomId = 10000 + (DateTime.now().microsecondsSinceEpoch % 90000);
    final orderId = "ZF-$randomId";

    final loc = LocationService();
    final lat = deliveryLatitude ?? loc.deliveryLatitude ?? loc.currentPosition?.latitude;
    final lng = deliveryLongitude ?? loc.deliveryLongitude ?? loc.currentPosition?.longitude;
    final resolvedBranch = (branchName != null && branchName.trim().isNotEmpty)
        ? branchName.trim()
        : await _resolveNearestBranchName(
            latitude: lat,
            longitude: lng,
          );
    final resolvedBranchAddress = (branchAddress ?? '').trim();

    final orderItems = cartItems.map((c) {
      final unitPrice = _resolveCartItemUnitPrice(c);
      return OrderItem(
        name: c.foodModel.name,
        imagePath: c.foodModel.imagePath,
        price: unitPrice.toStringAsFixed(0),
        quantity: c.quantity,
        selectedVariation: c.selectedVariation,
        selectedToppings: Set<String>.from(c.selectedToppings),
        // Choices + included/static deal items (names from Firestore).
        selectedDealOptions: _dealOptionsForOrder(c),
      );
    }).toList();

    final newOrder = OrderModel(
      orderId: orderId,
      items: orderItems,
      totalAmount: totalAmount,
      tax: tax,
      orderDate: DateTime.now(),
      status: OrderModel.initialStatusFor(orderType),
      deliveryAddress: deliveryAddress,
      deliveryInstructions: deliveryInstructions,
      specialInstructions: specialInstructions,
      customerName: customerName,
      customerPhone: customerPhone,
      userId: userId,
      orderType: orderType,
      tableNumber: tableNumber,
      customerCurrentAddress: '',
      branchName: resolvedBranch,
      branchAddress: resolvedBranchAddress,
      deliveryLatitude: lat,
      deliveryLongitude: lng,
    );

    try {
      final branchDocId = _sanitizeBranchDocId(resolvedBranch);
      final branchRef = FirebaseFirestore.instance
          .collection('orders')
          .doc(branchDocId);

      await branchRef.set({
        'name': resolvedBranch,
        if (resolvedBranchAddress.isNotEmpty) 'address': resolvedBranchAddress,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await branchRef.collection('orders').doc(orderId).set(newOrder.toJson());
    } catch (e) {
      debugPrint("Error saving order to Firestore: $e");
      return false;
    }

    _orders.insert(0, newOrder);
    await saveOrders();
    notifyListeners();
    return true;
  }

  static String _sanitizeBranchDocId(String name) {
    final cleaned = name.trim().replaceAll('/', '-');
    return cleaned.isEmpty ? 'Unknown Branch' : cleaned;
  }

  Future<String> _resolveNearestBranchName({
    double? latitude,
    double? longitude,
  }) async {
    try {
      final nearest = await BranchLocator.nearestBranch(
        latitude: latitude,
        longitude: longitude,
        preferOpen: true,
      );
      return nearest?.name ?? 'Unknown Branch';
    } catch (e) {
      debugPrint('Error resolving nearest branch: $e');
      return 'Unknown Branch';
    }
  }

  /// Selected multi-choice names + included/static included items for Firestore.
  static List<String> _dealOptionsForOrder(CartItem cartItem) {
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

    final target = cartItem.foodModel.name.trim().toLowerCase();
    if (target.isEmpty) return lines;

    FoodMenuItem? menu;
    for (final cat in FirestoreService.getCachedCategories()) {
      for (final p in FirestoreService.getCachedProductsByCategory(cat)) {
        if (p.name.trim().toLowerCase() == target) {
          menu = p;
          break;
        }
      }
      if (menu != null) break;
    }
    if (menu == null || menu.dealFixedItems.isEmpty) return lines;

    int qtyFor(String itemUrl) {
      final direct = menu!.dealModelQuantities[itemUrl];
      if (direct != null && direct > 0) return direct;
      final norm = FoodMenuItem.normalizeModelKeyPublic(itemUrl);
      if (norm.isEmpty) return 1;
      for (final e in menu.dealModelQuantities.entries) {
        if (FoodMenuItem.normalizeModelKeyPublic(e.key) == norm &&
            e.value > 0) {
          return e.value;
        }
      }
      return 1;
    }

    for (final url in menu.dealFixedItems) {
      final name = menu.displayNameFor(url).trim();
      if (name.isEmpty) continue;
      final qty = qtyFor(url);
      addLine(qty > 1 ? '$qty $name' : name);
    }
    return lines;
  }

  static double _resolveCartItemUnitPrice(CartItem item) {
    final raw = item.foodModel.price.trim();
    final variation = (item.selectedVariation ?? '').trim();
    double original = 0;

    if (raw.contains('|')) {
      final parts = raw.split('|');
      for (final part in parts) {
        final match = RegExp(
          r'([a-zA-Z\s]+)\s+(\d+(?:\.\d+)?)',
        ).firstMatch(part.trim());
        if (match == null) continue;
        final name = _expandSizeName(match.group(1)!.trim());
        final price = double.tryParse(match.group(2)!) ?? 0;
        if (variation.isEmpty) {
          original = price;
          break;
        }
        if (name.toLowerCase() == variation.toLowerCase() ||
            name.toLowerCase().startsWith(variation.toLowerCase()) ||
            variation.toLowerCase().startsWith(name.toLowerCase())) {
          original = price;
          break;
        }
      }
      if (original <= 0) {
        final first = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
        original =
            first != null ? (double.tryParse(first.group(1)!) ?? 0) : 0;
      }
    } else {
      final cleaned = raw
          .replaceAll(RegExp(r'[Rr][Ss]\.?\s*'), '')
          .replaceAll(',', '')
          .trim();
      final direct = double.tryParse(cleaned);
      if (direct != null) {
        original = direct;
      } else {
        final any = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
        original = any != null ? (double.tryParse(any.group(1)!) ?? 0) : 0;
      }
    }

    return item.foodModel.discountedFrom(original);
  }

  static String _expandSizeName(String name) {
    switch (name.trim().toUpperCase()) {
      case 'M':
        return 'Medium';
      case 'L':
        return 'Large';
      case 'S':
        return 'Small';
      default:
        return name;
    }
  }
}
