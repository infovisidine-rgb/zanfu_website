import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/google_maps_api_key.dart';
import 'google_geocode_parser.dart';

Future<String?> googleReverseGeocode(double lat, double lng) async {
  final key = googleMapsApiKey();
  if (key.isEmpty) return null;

  try {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?latlng=$lat,$lng&key=$key&language=en',
    );
    final res = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) return null;
    return GoogleGeocodeParser.bestFromResponse(data);
  } catch (_) {
    return null;
  }
}
