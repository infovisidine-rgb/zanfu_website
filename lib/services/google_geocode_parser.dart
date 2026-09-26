/// Parses Google Geocoding API JSON into a readable delivery address.
class GoogleGeocodeParser {
  static String? bestFromResponse(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString();
    if (status != 'OK') return null;
    final results = data['results'];
    if (results is! List || results.isEmpty) return null;

    String? best;
    var bestScore = -1;
    for (final raw in results) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final text = formatResult(map);
      if (text == null || text.isEmpty) continue;
      final score = scoreResult(map, text);
      if (score > bestScore) {
        bestScore = score;
        best = text;
      }
    }
    return best;
  }

  static int scoreResult(Map<String, dynamic> result, String text) {
    var score = 0;
    final types = (result['types'] as List?)?.cast<String>() ?? const [];
    const priority = {
      'street_address': 100,
      'premise': 90,
      'subpremise': 85,
      'establishment': 80,
      'point_of_interest': 75,
      'route': 70,
      'intersection': 65,
      'neighborhood': 45,
      'sublocality': 40,
      'locality': 20,
      'administrative_area_level_2': 15,
      'administrative_area_level_1': 10,
    };
    for (final t in types) {
      score = score > (priority[t] ?? 0) ? score : (priority[t] ?? 0);
    }

    final components = result['address_components'];
    if (components is List) {
      for (final raw in components) {
        if (raw is! Map) continue;
        final cTypes = (raw['types'] as List?)?.cast<String>() ?? const [];
        if (cTypes.contains('street_number')) score += 30;
        if (cTypes.contains('route')) score += 20;
        if (cTypes.contains('premise') || cTypes.contains('subpremise')) {
          score += 15;
        }
      }
    }

    if (RegExp(r'\d').hasMatch(text)) score += 8;
    score += text.split(',').where((p) => p.trim().isNotEmpty).length;
    return score;
  }

  static String? formatResult(Map<String, dynamic> result) {
    final formatted = (result['formatted_address'] ?? '').toString().trim();
    final components = result['address_components'];
    if (components is! List) {
      return formatted.isEmpty ? null : formatted;
    }

    String? streetNumber;
    String? route;
    String? subpremise;
    String? premise;
    String? neighborhood;
    String? locality;
    String? adminArea;
    String? postal;
    String? country;

    for (final raw in components) {
      if (raw is! Map) continue;
      final types = (raw['types'] as List?)?.cast<String>() ?? const [];
      final long = (raw['long_name'] ?? '').toString().trim();
      if (long.isEmpty) continue;
      if (types.contains('street_number')) streetNumber = long;
      if (types.contains('route')) route = long;
      if (types.contains('subpremise')) subpremise = long;
      if (types.contains('premise')) premise = long;
      if (types.contains('neighborhood') ||
          types.contains('sublocality') ||
          types.contains('sublocality_level_1') ||
          types.contains('sublocality_level_2')) {
        neighborhood ??= long;
      }
      if (types.contains('locality')) locality = long;
      if (types.contains('administrative_area_level_1')) adminArea = long;
      if (types.contains('postal_code')) postal = long;
      if (types.contains('country')) country = long;
    }

    final streetLine = [
      if (subpremise != null && subpremise.isNotEmpty) subpremise,
      if (streetNumber != null && streetNumber.isNotEmpty) streetNumber,
      if (route != null && route.isNotEmpty) route,
    ].join(' ').trim();

    final parts = <String>[
      if (streetLine.isNotEmpty)
        streetLine
      else if (premise != null && premise.isNotEmpty)
        premise,
      if (neighborhood != null && neighborhood.isNotEmpty) neighborhood,
      if (locality != null && locality.isNotEmpty) locality,
      if (adminArea != null && adminArea.isNotEmpty) adminArea,
      if (postal != null && postal.isNotEmpty) postal,
      if (country != null && country.isNotEmpty) country,
    ];

    final built = _dedupe(parts);
    if (built.isNotEmpty &&
        _detailScore(built) >= _detailScore(formatted)) {
      return built;
    }
    return formatted.isEmpty ? null : formatted;
  }

  static String _dedupe(List<String> parts) {
    final out = <String>[];
    for (final p in parts) {
      final t = p.trim();
      if (t.isEmpty) continue;
      if (out.any((x) => x.toLowerCase() == t.toLowerCase())) continue;
      out.add(t);
    }
    return out.join(', ');
  }

  static int _detailScore(String text) {
    var score = text.split(',').where((p) => p.trim().isNotEmpty).length;
    if (RegExp(r'\d').hasMatch(text)) score += 6;
    return score;
  }
}
