import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'firestore_service.dart';
import 'location_service.dart';
import 'route_distance_service.dart';

class BranchChoice {
  final String id;
  final String name;
  final double? latitude;
  final double? longitude;
  final String address;
  final String phone;
  final String openTime;
  final String closeTime;
  final bool deliveryAvailable;
  final bool takeawayAvailable;
  final bool dineInAvailable;
  /// Max delivery distance in km for THIS branch (Firestore `delivery_distance`).
  final double deliveryDistanceKm;
  /// Tax percent for THIS branch (e.g. 12 → 12%). `0` means tax included.
  final double taxPercent;
  /// Driving/route distance from user's selected location to this branch (km).
  final double? distanceKm;

  const BranchChoice({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
    this.address = '',
    this.phone = '',
    this.openTime = '',
    this.closeTime = '',
    this.deliveryAvailable = true,
    this.takeawayAvailable = true,
    this.dineInAvailable = true,
    this.deliveryDistanceKm = 0,
    this.taxPercent = 0,
    this.distanceKm,
  });

  bool get isOpenNow => BranchLocator.isOpenNow(openTime, closeTime);

  String get openClosedLabel => isOpenNow ? 'Open' : 'Closed';

  bool supportsOrderType(String orderType) {
    switch (orderType) {
      case 'Delivery':
        return deliveryAvailable;
      case 'Pickup':
        return takeawayAvailable;
      case 'Dine In':
        return dineInAvailable;
      default:
        return true;
    }
  }

  /// Delivery: route [distanceKm] must be ≤ this branch's [deliveryDistanceKm].
  bool get canDeliverToUserLocation {
    if (distanceKm == null) return false;
    if (deliveryDistanceKm <= 0) return true;
    return distanceKm! <= deliveryDistanceKm;
  }

  BranchChoice copyWithDistance(double? km) {
    return BranchChoice(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
      address: address,
      phone: phone,
      openTime: openTime,
      closeTime: closeTime,
      deliveryAvailable: deliveryAvailable,
      takeawayAvailable: takeawayAvailable,
      dineInAvailable: dineInAvailable,
      deliveryDistanceKm: deliveryDistanceKm,
      taxPercent: taxPercent,
      distanceKm: km,
    );
  }
}

/// Sorts / filters branches by driving-route distance and order-type rules.
class BranchLocator {
  BranchLocator._();

  static Future<List<BranchChoice>> getBranchesSortedByDistance({
    double? latitude,
    double? longitude,
    String? orderType,
  }) async {
    final loc = LocationService();
    final lat = latitude ??
        loc.deliveryLatitude ??
        loc.currentPosition?.latitude;
    final lng = longitude ??
        loc.deliveryLongitude ??
        loc.currentPosition?.longitude;

    await FirestoreService.preloadBranchesCache();
    var raw = FirestoreService.getCachedBranches();
    if (raw.isEmpty) {
      await FirestoreService.refreshBranchesCacheInBackground();
      raw = FirestoreService.getCachedBranches();
    }

    // Parse + filter by order type first (no distance yet)
    final parsed = <BranchChoice>[];
    for (final data in raw) {
      final branch = _fromMap(data);
      if (branch == null) continue;
      if (orderType != null && !branch.supportsOrderType(orderType)) continue;
      if (branch.latitude == null || branch.longitude == null) continue;
      parsed.add(branch);
    }

    if (parsed.isEmpty) return [];

    List<double?> routeDistances = List<double?>.filled(parsed.length, null);
    if (lat != null && lng != null) {
      routeDistances = await RouteDistanceService.getDrivingDistancesKm(
        originLat: lat,
        originLng: lng,
        destinations: parsed
            .map((b) => (lat: b.latitude!, lng: b.longitude!))
            .toList(),
      );
    }

    final list = <BranchChoice>[];
    for (var i = 0; i < parsed.length; i++) {
      final b = parsed[i];
      double? distanceKm = routeDistances[i];
      // Fallback only if OSRM fails for that point
      if (distanceKm == null &&
          lat != null &&
          lng != null &&
          b.latitude != null &&
          b.longitude != null) {
        distanceKm = Geolocator.distanceBetween(
              lat,
              lng,
              b.latitude!,
              b.longitude!,
            ) /
            1000.0;
        debugPrint(
          'BranchLocator: OSRM miss for ${b.name} — straight-line fallback '
          '${distanceKm.toStringAsFixed(2)} km',
        );
      }
      list.add(b.copyWithDistance(distanceKm));
    }

    list.sort((a, b) {
      final da = a.distanceKm;
      final db = b.distanceKm;
      if (da == null && db == null) return a.name.compareTo(b.name);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    debugPrint(
      'BranchLocator: ${list.length} branches by route distance '
      '(type=$orderType, origin=${lat != null && lng != null ? "$lat,$lng" : "none"})',
    );
    return list;
  }

  static Future<BranchChoice?> nearestBranch({
    double? latitude,
    double? longitude,
    String? orderType,
    bool preferOpen = true,
  }) async {
    final list = await getBranchesSortedByDistance(
      latitude: latitude,
      longitude: longitude,
      orderType: orderType,
    );
    if (list.isEmpty) return null;
    if (preferOpen) {
      final open = list.where((b) => b.isOpenNow).toList();
      if (open.isNotEmpty) return open.first;
    }
    return list.first;
  }

  /// Supports overnight windows e.g. open 10:00 PM → close 5:00 AM.
  static bool isOpenNow(String openRaw, String closeRaw, {DateTime? now}) {
    final open = _parseTimeOfDay(openRaw);
    final close = _parseTimeOfDay(closeRaw);
    if (open == null || close == null) {
      // Missing hours → don't block orders
      return true;
    }

    final n = now ?? DateTime.now();
    final minutes = n.hour * 60 + n.minute;
    final openM = open.hour * 60 + open.minute;
    final closeM = close.hour * 60 + close.minute;

    if (openM == closeM) return true; // 24h
    if (openM < closeM) {
      // Same-day window e.g. 10:00–22:00
      return minutes >= openM && minutes < closeM;
    }
    // Overnight e.g. 22:00–05:00
    return minutes >= openM || minutes < closeM;
  }

  static BranchChoice? _fromMap(Map<String, dynamic> data) {
    final id = (data['id'] ?? '').toString();
    final name = (data['name'] ?? id).toString().trim();
    if (name.isEmpty) return null;

    final bLat = (data['latitude'] as num?)?.toDouble() ??
        (data['lat'] as num?)?.toDouble();
    final bLng = (data['longitude'] as num?)?.toDouble() ??
        (data['lng'] as num?)?.toDouble() ??
        (data['lon'] as num?)?.toDouble();

    final address = (data['address'] ??
            data['address_line'] ??
            data['location'] ??
            '')
        .toString();

    final phone = (data['phone'] ?? data['phone_number'] ?? '').toString();

    final openTime = (data['open_time'] ??
            data['openingTime'] ??
            data['opening_time'] ??
            '')
        .toString();
    final closeTime = (data['close_time'] ??
            data['closingTime'] ??
            data['closing_time'] ??
            '')
        .toString();

    bool flag(dynamic v, {bool defaultValue = true}) {
      if (v == null) return defaultValue;
      if (v is bool) return v;
      final s = v.toString().toLowerCase().trim();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
      return defaultValue;
    }

    final deliveryDistance =
        (data['delivery_distance'] as num?)?.toDouble() ??
            (data['deliveryDistance'] as num?)?.toDouble() ??
            0;

    final tax = (data['tax'] as num?)?.toDouble() ?? 0;

    return BranchChoice(
      id: id.isNotEmpty ? id : name,
      name: name,
      latitude: bLat,
      longitude: bLng,
      address: address,
      phone: phone,
      openTime: openTime,
      closeTime: closeTime,
      deliveryAvailable:
          flag(data['delivery_available'] ?? data['deliveryAvailable']),
      takeawayAvailable: flag(
        data['takeaway_available'] ?? data['takeawayAvailable'],
      ),
      dineInAvailable: flag(
        data['dine_in_available'] ?? data['dineInAvailable'],
      ),
      deliveryDistanceKm: deliveryDistance,
      taxPercent: tax,
    );
  }

  static TimeOfDay? _parseTimeOfDay(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final ampm = RegExp(
      r'^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(s);
    if (ampm != null) {
      var h = int.parse(ampm.group(1)!);
      final m = int.parse(ampm.group(2) ?? '0');
      final period = ampm.group(3)!.toUpperCase();
      if (period == 'AM') {
        if (h == 12) h = 0;
      } else {
        if (h != 12) h += 12;
      }
      if (h > 23 || m > 59) return null;
      return TimeOfDay(hour: h, minute: m);
    }

    final hm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
    if (hm != null) {
      final h = int.parse(hm.group(1)!);
      final m = int.parse(hm.group(2)!);
      if (h > 23 || m > 59) return null;
      return TimeOfDay(hour: h, minute: m);
    }

    return null;
  }
}

/// Minimal TimeOfDay without importing Flutter material.
class TimeOfDay {
  final int hour;
  final int minute;
  const TimeOfDay({required this.hour, required this.minute});
}
