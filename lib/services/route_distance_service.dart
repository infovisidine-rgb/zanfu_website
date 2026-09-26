import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fetches driving-route distances via the public OSRM API.
class RouteDistanceService {
  static const _baseUrl = 'https://router.project-osrm.org';
  static const _timeout = Duration(seconds: 12);

  /// Returns driving distances in km from [originLat]/[originLng] to each
  /// destination. List length matches [destinations]; null entries mean the
  /// route could not be resolved for that point.
  static Future<List<double?>> getDrivingDistancesKm({
    required double originLat,
    required double originLng,
    required List<({double lat, double lng})> destinations,
  }) async {
    if (destinations.isEmpty) return const [];

    // OSRM expects lon,lat pairs separated by semicolons.
    final coords = [
      '$originLng,$originLat',
      ...destinations.map((d) => '${d.lng},${d.lat}'),
    ].join(';');

    final uri = Uri.parse(
      '$_baseUrl/table/v1/driving/$coords'
      '?sources=0&annotations=distance',
    );

    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('OSRM table error: HTTP ${response.statusCode}');
        return List<double?>.filled(destinations.length, null);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') {
        debugPrint('OSRM table error: ${data['code']}');
        return List<double?>.filled(destinations.length, null);
      }

      final rows = data['distances'] as List<dynamic>?;
      if (rows == null || rows.isEmpty) {
        return List<double?>.filled(destinations.length, null);
      }

      final row = rows.first as List<dynamic>;
      // Index 0 is origin→origin (0 m); branch i is at index i + 1.
      return List<double?>.generate(destinations.length, (i) {
        if (i + 1 >= row.length) return null;
        final meters = row[i + 1];
        if (meters == null) return null;
        return (meters as num).toDouble() / 1000.0;
      });
    } catch (e) {
      debugPrint('OSRM route distance fetch failed: $e');
      return List<double?>.filled(destinations.length, null);
    }
  }
}
