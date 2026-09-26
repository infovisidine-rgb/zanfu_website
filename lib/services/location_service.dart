import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../utils/google_maps_api_key.dart';
import '../utils/permission_helper.dart';
import 'google_reverse_geocode.dart';

/// Session-only delivery location (map pin + written address).
/// Not persisted to Firebase, SharedPreferences, or profile.
class LocationService extends ChangeNotifier {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  String? _currentAddress;
  Position? _currentPosition;
  bool _permissionDenied = false;
  bool _serviceDisabled = false;

  double? _deliveryLatitude;
  double? _deliveryLongitude;
  String _writtenAddress = '';

  String? get currentAddress =>
      _writtenAddress.isNotEmpty ? _writtenAddress : _currentAddress;
  Position? get currentPosition => _currentPosition;
  bool get permissionDenied => _permissionDenied;
  bool get serviceDisabled => _serviceDisabled;
  bool get hasLocation =>
      (currentAddress != null && currentAddress!.isNotEmpty) &&
      !_permissionDenied;

  double? get deliveryLatitude => _deliveryLatitude;
  double? get deliveryLongitude => _deliveryLongitude;
  String get writtenAddress => _writtenAddress;

  bool get hasDeliveryPin =>
      _deliveryLatitude != null && _deliveryLongitude != null;

  bool get hasValidDeliveryLocation =>
      hasDeliveryPin && _writtenAddress.trim().isNotEmpty;

  double? get effectiveLatitude =>
      _deliveryLatitude ?? _currentPosition?.latitude;
  double? get effectiveLongitude =>
      _deliveryLongitude ?? _currentPosition?.longitude;

  /// Silent GPS init (splash) — no dialogs. Does not persist address.
  Future<void> initLocation() async {
    await _resolveLocation(context: null, showDialogOnDeny: false);
  }

  Future<bool> requestLocationWithUi(BuildContext context) async {
    return _resolveLocation(context: context, showDialogOnDeny: true);
  }

  /// GPS fix for Pickup / Dine In nearest-branch.
  /// Does not set the session delivery pin (map remains source for Delivery).
  Future<Position?> ensureCurrentPosition(BuildContext context) async {
    final allowed = await PermissionHelper.ensureLocation(
      context,
      showDialogOnDeny: true,
    );
    if (!allowed) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      _serviceDisabled = !serviceEnabled;
      _permissionDenied = true;
      notifyListeners();
      return null;
    }

    _permissionDenied = false;
    _serviceDisabled = false;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentPosition = position;
      notifyListeners();
      return position;
    } catch (e) {
      debugPrint('LocationService: ensureCurrentPosition error: $e');
      _permissionDenied = true;
      notifyListeners();
      return null;
    }
  }

  /// IP-based geolocation fallback when browser blocks HTML5 location over HTTP.
  static Future<({double lat, double lng, String city})?> fetchIpLocation() async {
    try {
      final uri = Uri.parse('https://ipapi.co/json/');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['latitude'] != null && data['longitude'] != null) {
          final lat = (data['latitude'] as num).toDouble();
          final lng = (data['longitude'] as num).toDouble();
          final city = (data['city'] ?? data['region'] ?? '').toString();
          return (lat: lat, lng: lng, city: city);
        }
      }
    } catch (_) {}
    try {
      final uri = Uri.parse('https://freeipapi.com/api/json');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['latitude'] != null && data['longitude'] != null) {
          final lat = (data['latitude'] as num).toDouble();
          final lng = (data['longitude'] as num).toDouble();
          final city = (data['cityName'] ?? data['regionName'] ?? '').toString();
          return (lat: lat, lng: lng, city: city);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _resolveLocation({
    required BuildContext? context,
    required bool showDialogOnDeny,
  }) async {
    final allowed = await PermissionHelper.ensureLocation(
      context,
      showDialogOnDeny: showDialogOnDeny,
    );

    if (!allowed) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      _serviceDisabled = !serviceEnabled;
      _permissionDenied = true;
      notifyListeners();
      return false;
    }

    _permissionDenied = false;
    _serviceDisabled = false;

    try {
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentPosition = position;

      if (!hasDeliveryPin) {
        _deliveryLatitude = position.latitude;
        _deliveryLongitude = position.longitude;
      }

      final geo = await reverseGeocodeLatLng(
        position.latitude,
        position.longitude,
      );
      if (geo != null && geo.isNotEmpty) {
        _currentAddress = geo;
        if (_writtenAddress.trim().isEmpty) {
          _writtenAddress = geo;
        }
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('LocationService: position/geocode error: $e');
      _permissionDenied = true;
      notifyListeners();
      return false;
    }
  }

  /// Session-only: used for current order / UI. Not saved to Firebase/local DB.
  void setDeliveryLocation({
    required double latitude,
    required double longitude,
    required String writtenAddress,
  }) {
    _deliveryLatitude = latitude;
    _deliveryLongitude = longitude;
    _writtenAddress = writtenAddress.trim();
    _currentAddress = _writtenAddress;
    _permissionDenied = false;
    notifyListeners();
  }

  void setManualAddress(String address) {
    _writtenAddress = address.trim();
    _currentAddress = _writtenAddress;
    _permissionDenied = false;
    notifyListeners();
  }

  /// Clear session delivery pin (e.g. after order) — optional.
  void clearDeliveryLocation() {
    _deliveryLatitude = null;
    _deliveryLongitude = null;
    _writtenAddress = '';
    notifyListeners();
  }

  /// Helper to format a placemark / generic address object into a clean string.
  static String formatPlacemark(dynamic p) {
    if (p == null) return '';
    try {
      if (p is String) return p.trim();
      final name = (p.name ?? '').toString().trim();
      final street = (p.street ?? '').toString().trim();
      final subLocality = (p.subLocality ?? p.subAdministrativeArea ?? '').toString().trim();
      final locality = (p.locality ?? '').toString().trim();
      final state = (p.administrativeArea ?? '').toString().trim();
      final country = (p.country ?? '').toString().trim();

      final parts = <String>[];
      if (name.isNotEmpty && name != street && !name.contains('+')) parts.add(name);
      if (street.isNotEmpty) parts.add(street);
      if (subLocality.isNotEmpty) parts.add(subLocality);
      if (locality.isNotEmpty) parts.add(locality);
      if (state.isNotEmpty) parts.add(state);
      if (country.isNotEmpty) parts.add(country);

      final deduped = <String>[];
      for (final pt in parts) {
        if (!deduped.any((x) => x.toLowerCase() == pt.toLowerCase())) {
          deduped.add(pt);
        }
      }
      return deduped.join(', ');
    } catch (_) {
      return (p ?? '').toString().trim();
    }
  }

  static Future<String?> _googleRestGeocode(double lat, double lng) async {
    final key = googleMapsApiKey();
    if (key.isEmpty) return null;
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$key&language=en',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['status'] == 'OK') {
          final results = data['results'];
          if (results is List && results.isNotEmpty) {
            for (final r in results) {
              final types = (r['types'] as List?)?.cast<String>() ?? [];
              if (types.contains('street_address') ||
                  types.contains('premise') ||
                  types.contains('subpremise') ||
                  types.contains('route') ||
                  types.contains('establishment')) {
                final formatted = (r['formatted_address'] ?? '').toString().trim();
                if (formatted.isNotEmpty) return formatted;
              }
            }
            final first = (results[0]['formatted_address'] ?? '').toString().trim();
            if (first.isNotEmpty) return first;
          }
        }
      }
    } catch (e) {
      debugPrint('Google REST geocode error: $e');
    }
    return null;
  }

  /// Reverse-geocode a pin. Prefer street-level (house / road), not city-only.
  ///
  /// Web platform notes:
  ///  - Photon (komoot.io) is CORS-blocked in browsers — skipped on web.
  ///  - BigDataCloud is the most reliable free CORS-friendly source.
  ///  - Google JS geocoder (via JS interop) works if Maps API is loaded.
  static Future<String?> reverseGeocodeLatLng(double lat, double lng) async {
    try {
      // On web: skip Photon (CORS blocked). On native: run all APIs.
      final futures = <Future<String?>>[
        // BigDataCloud — best free CORS-friendly API with street detail
        _bigDataCloudReverse(lat, lng)
            .timeout(const Duration(seconds: 5), onTimeout: () => null),
        // Nominatim — good fallback, strict rate limit
        _nominatimReverse(lat, lng)
            .timeout(const Duration(seconds: 5), onTimeout: () => null),
        // Google REST — works if Geocoding API is enabled on the key
        _googleRestGeocode(lat, lng)
            .timeout(const Duration(seconds: 5), onTimeout: () => null),
        // Google JS interop — web only (uses window.vdReverseGeocode)
        googleReverseGeocode(lat, lng)
            .timeout(const Duration(seconds: 5), onTimeout: () => null),
      ];

      // Photon is CORS-blocked on web browsers — only run on native
      if (!kIsWeb) {
        futures.add(
          _photonReverse(lat, lng)
              .timeout(const Duration(seconds: 4), onTimeout: () => null),
        );
      }

      final results = await Future.wait(futures);

      String? best;
      var bestScore = -999;

      for (final text in results) {
        if (text == null) continue;
        final t = text.trim();
        if (t.isEmpty || looksLikeCoordinateLabel(t)) continue;
        final score = _addressDetailScore(t);
        if (score > bestScore) {
          bestScore = score;
          best = t;
        }
      }

      return best;
    } catch (_) {
      return null;
    }
  }

  static bool _hasStreetLevelDetail(String text) {
    if (RegExp(r'\d').hasMatch(text)) return true;
    final lower = text.toLowerCase();
    const hints = [
      'street',
      'st ',
      ' road',
      ' rd',
      'avenue',
      'ave',
      'lane',
      'block',
      'house',
      'gali',
      'sector',
      'phase',
      'colony',
      'town',
      'plaza',
      'market',
      'chowk',
      'boulevard',
      'drive',
      ' highway',
      ' express',
    ];
    return hints.any(lower.contains);
  }

  static int _addressDetailScore(String text) {
    final parts = text
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    var score = parts.length;
    if (RegExp(r'\d').hasMatch(text)) score += 8;
    if (RegExp(r'^\s*\d+\s').hasMatch(text)) score += 12;
    final lower = text.toLowerCase();
    const houseHints = ['house', 'h#', 'h.', 'flat', 'unit', 'building', 'premise', 'gali'];
    const streetHints = [
      'street',
      'st ',
      'road',
      'rd',
      'avenue',
      'lane',
      'block',
      'sector',
      'phase',
      'colony',
      'town',
    ];
    if (houseHints.any(lower.contains)) score += 15;
    if (streetHints.any(lower.contains)) score += 8;
    if (!_hasStreetLevelDetail(text)) score -= 10;
    if (parts.length <= 2) score -= 4;
    return score;
  }

  static Future<String?> _bigDataCloudReverse(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client'
        '?latitude=$lat&longitude=$lng&localityLanguage=en',
      );
      final res = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      final parts = <String>[];
      void add(dynamic v) {
        final t = (v ?? '').toString().trim();
        if (t.isEmpty) return;
        if (parts.any((p) => p.toLowerCase() == t.toLowerCase())) return;
        parts.add(t);
      }

      final house = (data['houseNumber'] ?? data['building'] ?? '').toString().trim();
      final street = (data['street'] ?? data['streetName'] ?? '').toString().trim();
      if (house.isNotEmpty && street.isNotEmpty) {
        add('House $house, $street');
      } else {
        add(house.isNotEmpty ? 'House $house' : '');
        add(street);
      }
      add(data['locality']);
      add(data['city']);
      final info = data['localityInfo'];
      if (info is Map) {
        final informative = info['informative'];
        if (informative is List) {
          for (final item in informative.take(3)) {
            if (item is Map) add(item['name']);
          }
        }
      }
      add(data['principalSubdivision']);
      add(data['postcode']);
      add(data['countryName']);
      if (parts.isNotEmpty) return parts.join(', ');
      final plus = (data['plusCode'] ?? '').toString().trim();
      return plus.isEmpty ? null : plus;
    } catch (e) {
      debugPrint('LocationService BigDataCloud geocode: $e');
      return null;
    }
  }

  static Future<String?> _nominatimReverse(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2&lat=$lat&lon=$lng&addressdetails=1&zoom=18&accept-language=en',
      );
      final res = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'VisiDineWebApp/1.0 (zanfu.pk)',
        },
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map) return null;

      final addr = data['address'];
      if (addr is Map) {
        final house = (addr['house_number'] ??
                addr['house_name'] ??
                addr['building'] ??
                addr['premise'] ??
                addr['subpremise'] ??
                addr['unit'] ??
                addr['flat'] ??
                '')
            .toString()
            .trim();
        final road = (addr['road'] ??
                addr['street'] ??
                addr['pedestrian'] ??
                addr['residential'] ??
                addr['footway'] ??
                addr['path'] ??
                addr['lane'] ??
                addr['avenue'] ??
                '')
            .toString()
            .trim();
        final poi = (data['name'] ??
                addr['amenity'] ??
                addr['shop'] ??
                addr['office'] ??
                addr['tourism'] ??
                '')
            .toString()
            .trim();
        final sector = (addr['sector'] ??
                addr['block'] ??
                addr['phase'] ??
                addr['neighbourhood'] ??
                addr['suburb'] ??
                addr['quarter'] ??
                addr['city_block'] ??
                '')
            .toString()
            .trim();

        final houseLabel = house.isNotEmpty
            ? (RegExp(r'^\d+$').hasMatch(house) ? 'House $house' : house)
            : '';
        final streetLine = [
          if (houseLabel.isNotEmpty) houseLabel,
          if (road.isNotEmpty) road,
        ].join(', ').trim();

        final parts = [
          streetLine.isNotEmpty ? streetLine : (road.isNotEmpty ? road : houseLabel),
          if (poi.isNotEmpty && poi != road && poi != houseLabel) poi,
          sector,
          addr['city_district'] ?? addr['district'],
          addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['municipality'],
          addr['state'],
          addr['postcode'],
          addr['country'],
        ]
            .map((e) => (e ?? '').toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
        final built = _dedupeAddressParts(parts);
        if (built.isNotEmpty) return built;
      }
      final disp = (data['display_name'] ?? '').toString().trim();
      return disp.isNotEmpty ? disp : null;
    } catch (e) {
      debugPrint('LocationService Nominatim geocode: $e');
      return null;
    }
  }

  static Future<String?> _photonReverse(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/reverse?lat=$lat&lon=$lng',
      );
      final res = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      final features = data['features'];
      if (features is! List || features.isEmpty) return null;

      String? best;
      var bestScore = -999;

      for (final feature in features) {
        if (feature is! Map) continue;
        final props = feature['properties'];
        if (props is! Map) continue;

        final house = (props['housenumber'] ?? '').toString().trim();
        final street = (props['street'] ?? '').toString().trim();
        final streetLine = [
          if (house.isNotEmpty) house,
          if (street.isNotEmpty) street,
        ].join(' ').trim();
        final name = (props['name'] ?? '').toString().trim();
        final osmValue = (props['osm_value'] ?? '').toString().toLowerCase();

        final parts = [
          streetLine.isNotEmpty ? streetLine : name,
          props['district'] ?? props['locality'],
          props['city'] ?? props['town'] ?? props['village'],
          props['state'],
          props['postcode'],
          props['country'],
        ]
            .map((e) => (e ?? '').toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
        final built = _dedupeAddressParts(parts);
        if (built.isEmpty) continue;

        var score = _addressDetailScore(built);
        if (['city', 'country', 'state', 'county'].contains(osmValue)) {
          score -= 6;
        }
        if (['house', 'building', 'residential', 'yes'].contains(osmValue)) {
          score += 4;
        }
        if (score > bestScore) {
          bestScore = score;
          best = built;
        }
      }
      return best;
    } catch (e) {
      debugPrint('LocationService Photon geocode: $e');
      return null;
    }
  }

  static String _dedupeAddressParts(List<String> parts) {
    final out = <String>[];
    for (final p in parts) {
      final t = p.trim();
      if (t.isEmpty) continue;
      if (out.any((x) => x.toLowerCase() == t.toLowerCase())) continue;
      out.add(t);
    }
    return out.join(', ');
  }

  static bool looksLikeCoordinateLabel(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    final lower = s.toLowerCase();
    if (lower.startsWith('selected location') ||
        lower == 'selected map location' ||
        lower.startsWith('selected address')) {
      return true;
    }
    return RegExp(
      r'^-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+$',
    ).hasMatch(s);
  }

  /// Re-geocode pin into a human address when UI is showing lat/lng text.
  Future<String?> refreshAddressFromPin() async {
    final lat = _deliveryLatitude;
    final lng = _deliveryLongitude;
    if (lat == null || lng == null) return null;
    try {
      final text = await reverseGeocodeLatLng(lat, lng);
      if (text == null || text.isEmpty) return null;
      _writtenAddress = text;
      _currentAddress = text;
      notifyListeners();
      return text;
    } catch (e) {
      debugPrint('LocationService.refreshAddressFromPin: $e');
      return null;
    }
  }
}
