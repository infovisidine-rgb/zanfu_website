import 'dart:async';
import 'dart:js_interop';

import '../utils/google_maps_api_key.dart';

@JS('vdInitMapsGeocoder')
external JSPromise<JSAny?> _vdInitMapsGeocoder(JSString apiKey);

@JS('vdReverseGeocode')
external JSPromise<JSString> _vdReverseGeocode(double lat, double lng);

/// Google Maps JS reverse geocode via web interop.
/// Returns null silently if:
///  - API key is empty
///  - Google Maps script failed to load (e.g. key not configured for Maps API)
///  - Any network or JS error
Future<String?> googleReverseGeocode(double lat, double lng) async {
  final key = googleMapsApiKey();
  if (key.isEmpty) return null;

  try {
    // Init the geocoder (loads Maps JS script if not already loaded).
    // Throws if the API key is not enabled for Maps JavaScript API.
    await _vdInitMapsGeocoder(key.toJS).toDart;
    final result = await _vdReverseGeocode(lat, lng).toDart;
    final text = result.toDart.trim();
    return text.isEmpty ? null : text;
  } catch (e) {
    // Google Maps API not enabled or network error — fall through to other APIs
    return null;
  }
}
