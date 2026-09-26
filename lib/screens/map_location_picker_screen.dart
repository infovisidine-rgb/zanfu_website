import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../utils/app_colors.dart';
import '../utils/network_helper.dart';
import '../utils/responsive_helper.dart';
import '../widgets/app_bottom_action_button.dart';
import '../widgets/custom_header.dart';

/// Result returned when user confirms map + written address.
class DeliveryLocationResult {
  final double latitude;
  final double longitude;
  final String writtenAddress;

  const DeliveryLocationResult({
    required this.latitude,
    required this.longitude,
    required this.writtenAddress,
  });
}

/// Pick delivery pin on map + confirm written address.
/// - Location ON: starts at GPS (or last pin); user can move pin.
/// - Location OFF: must pick pin on map + write address (required).
class MapLocationPickerScreen extends StatefulWidget {
  final bool requireSelection;
  final String? initialWrittenAddress;
  final double? initialLatitude;
  final double? initialLongitude;

  const MapLocationPickerScreen({
    super.key,
    this.requireSelection = true,
    this.initialWrittenAddress,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _addressController = TextEditingController();
  final LocationService _location = LocationService();

  static const LatLng _fallbackCenter = LatLng(33.6007, 73.0679);

  LatLng _pin = _fallbackCenter;
  bool _mapReady = false;
  bool _geocoding = false;
  bool _saving = false;
  bool _gpsAvailable = false;
  String? _statusHint;
  Timer? _geocodeDebounce;
  /// Last pin for which Address was successfully reverse-geocoded.
  LatLng? _resolvedPin;

  bool _samePin(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < 0.00001 &&
      (a.longitude - b.longitude).abs() < 0.00001;

  bool get _addressReadyForPin {
    final text = _addressController.text.trim();
    return _resolvedPin != null &&
        _samePin(_resolvedPin!, _pin) &&
        text.isNotEmpty &&
        !LocationService.looksLikeCoordinateLabel(text);
  }

  bool get _canConfirm => !_saving && !_geocoding;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final loc = _location;
    double? lat = widget.initialLatitude ?? loc.deliveryLatitude;
    double? lng = widget.initialLongitude ?? loc.deliveryLongitude;
    String written = (widget.initialWrittenAddress ?? loc.writtenAddress).trim();

    // Try GPS — on web, explicitly request permission so browser shows popup
    var gpsOk = false;
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      var perm = await Geolocator.checkPermission();

      // On web: always request permission so the browser popup fires
      if (perm == LocationPermission.denied) {
        try {
          perm = await Geolocator.requestPermission();
        } catch (_) {}
      }

      final allowed = serviceOn &&
          perm != LocationPermission.deniedForever &&
          perm != LocationPermission.denied;

      if (allowed) {
        // Web GPS can be slow — give it more time
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(Duration(seconds: kIsWeb ? 10 : 5));
        gpsOk = true;
        lat ??= pos.latitude;
        lng ??= pos.longitude;
        if (written.isEmpty) {
          try {
            written = await LocationService.reverseGeocodeLatLng(
                  pos.latitude,
                  pos.longitude,
                ) ??
                '';
          } catch (_) {}
        }
      }
    } catch (_) {}

    // If GPS failed on web and we still have no pin, try IP-based location
    if (!gpsOk && lat == null && lng == null && kIsWeb) {
      try {
        final ipLoc = await LocationService.fetchIpLocation();
        if (ipLoc != null) {
          lat = ipLoc.lat;
          lng = ipLoc.lng;
          // IP location is city-level only — don't set resolvedPin
        }
      } catch (_) {}
    }

    lat ??= _fallbackCenter.latitude;
    lng ??= _fallbackCenter.longitude;

    if (!mounted) return;
    setState(() {
      _pin = LatLng(lat!, lng!);
      _gpsAvailable = gpsOk;
      _addressController.text = written;
      if (written.isNotEmpty) {
        _resolvedPin = LatLng(lat, lng);
      }
      if (gpsOk) {
        _statusHint = 'Drag the map to adjust your pin. Address updates automatically.';
      } else if (kIsWeb) {
        _statusHint =
            'GPS requires HTTPS. Drag the map pin to your exact location — address fills automatically.';
      } else {
        _statusHint = 'Move the map to select your point. Internet is required to fill Address.';
      }
    });

    if (_mapReady) {
      // GPS: zoom to street level. IP fallback: zoom to city level
      _mapController.move(_pin, gpsOk ? 17 : 14);
    }
    // Ensure address matches pin when online
    if (written.isEmpty || _resolvedPin == null) {
      _scheduleGeocode(_pin);
    }
  }

  void _onMapReady() {
    _mapReady = true;
    _mapController.move(_pin, 15);
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMove ||
        event is MapEventMoveEnd ||
        event is MapEventFlingAnimation ||
        event is MapEventDoubleTapZoom) {
      final center = _mapController.camera.center;
      _pin = center;
      // Pin moved — address must be re-fetched for the new point
      if (_resolvedPin == null || !_samePin(_resolvedPin!, center)) {
        _resolvedPin = null;
      }
      if (event is MapEventMoveEnd ||
          event is MapEventFlingAnimationEnd ||
          event is MapEventDoubleTapZoomEnd) {
        _scheduleGeocode(center);
      }
    }
  }

  void _scheduleGeocode(LatLng point) {
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) {
        setState(() {
          _geocoding = true;
          _resolvedPin = null;
          if (LocationService.looksLikeCoordinateLabel(_addressController.text)) {
            _addressController.clear();
          }
          _statusHint = 'Fetching address for this pin…';
        });
      }
      _reverseGeocode(point, waitForInternet: false);
    });
  }

  /// Returns geocoded address text, or null on failure.
  Future<String?> _reverseGeocode(
    LatLng point, {
    required bool waitForInternet,
  }) async {
    if (!mounted) return null;
    setState(() => _geocoding = true);
    try {
      final online = await NetworkHelper.hasConnectivity();
      if (!online && !waitForInternet) {
        if (mounted) {
          if (LocationService.looksLikeCoordinateLabel(_addressController.text)) {
            _addressController.clear();
          }
          setState(() {
            _resolvedPin = point;
            _statusHint = 'No internet — Type your address below or edit.';
          });
        }
        return null;
      }

      String? text;
      try {
        text = await LocationService.reverseGeocodeLatLng(
          point.latitude,
          point.longitude,
        );
      } catch (e) {
        debugPrint('Map picker geocode error: $e');
      }

      if (mounted) {
        if (text != null && text.isNotEmpty) {
          _addressController.text = text;
          setState(() {
            _resolvedPin = point;
            _statusHint =
                'Address updated for this pin. You can edit it, then confirm.';
          });
          return text;
        } else {
          if (LocationService.looksLikeCoordinateLabel(_addressController.text)) {
            _addressController.clear();
          }
          setState(() {
            _resolvedPin = point;
            _statusHint =
                'Address could not be auto-filled. Type your house # and street below.';
          });
          return _addressController.text.trim().isNotEmpty
              ? _addressController.text
              : null;
        }
      }
      return null;
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _goToMyLocation() async {
    setState(() {
      _geocoding = true;
      _statusHint = 'Requesting your location…';
    });

    try {
      // On web: must request permission to trigger the browser popup
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        try {
          perm = await Geolocator.requestPermission();
        } catch (_) {}
      }

      // Only attempt GPS if permission is actually granted
      // NOTE: On HTTP sites, browser returns deniedForever — we skip GPS
      // but still fall through to IP fallback below (do NOT return early here)
      final gpsAllowed = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;

      if (gpsAllowed) {
        Position? pos;
        try {
          // Web GPS can take longer — give it more time
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(Duration(seconds: kIsWeb ? 12 : 7));
        } catch (e) {
          debugPrint('getCurrentPosition error: $e');
          try {
            pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium,
            ).timeout(Duration(seconds: kIsWeb ? 8 : 4));
          } catch (_) {
            try {
              pos = await Geolocator.getLastKnownPosition();
            } catch (_) {}
          }
        }

        if (pos != null && mounted) {
          final target = LatLng(pos.latitude, pos.longitude);
          setState(() {
            _pin = target;
            _resolvedPin = null;
            if (LocationService.looksLikeCoordinateLabel(_addressController.text)) {
              _addressController.clear();
            }
            _gpsAvailable = true;
            _statusHint = 'Moved to your GPS location. Fetching address…';
          });
          // GPS is accurate — zoom to street level
          _mapController.move(target, 17);
          await _reverseGeocode(target, waitForInternet: false);
          return;
        }
      }
    } catch (e) {
      debugPrint('GPS my location error: $e');
    }

    // Fallback: IP-based location (city-level only)
    // This kicks in when: HTTP site (GPS blocked by browser), or GPS timed out
    final ipLoc = await LocationService.fetchIpLocation();
    if (ipLoc != null && mounted) {
      final target = LatLng(ipLoc.lat, ipLoc.lng);
      setState(() {
        _pin = target;
        _resolvedPin = null;
        if (LocationService.looksLikeCoordinateLabel(_addressController.text)) {
          _addressController.clear();
        }
        _gpsAvailable = false;
        _statusHint = kIsWeb
            ? 'Exact GPS needs HTTPS. Showing city area (${ipLoc.city}) — drag the pin to your street/house.'
            : 'GPS unavailable. Showing approximate city area (${ipLoc.city}) — drag pin to your location.';
      });
      // IP location is city-level — use wider zoom (13) so user can navigate to their street
      _mapController.move(target, 13);
      await _reverseGeocode(target, waitForInternet: false);
      return;
    }

    if (!mounted) return;
    setState(() {
      _gpsAvailable = false;
      _geocoding = false;
      _statusHint = kIsWeb
          ? 'Location unavailable. If using HTTP, GPS requires HTTPS. Drag the map pin to your location.'
          : 'Location permission blocked. Please drag map pin to your location.';
    });
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _statusHint =
          'Confirming… waiting for internet and Address update for this pin.';
    });

    try {
      // Always resolve Address for the current pin before leaving
      String? address;
      final text = _addressController.text.trim();
      if (_addressReadyForPin) {
        address = text;
      } else if (text.isNotEmpty &&
          !LocationService.looksLikeCoordinateLabel(text)) {
        address = text;
      } else {
        address = await _reverseGeocode(_pin, waitForInternet: true);
      }

      if (!mounted) return;
      var written = (address ?? '').trim();
      if (written.isEmpty || LocationService.looksLikeCoordinateLabel(written)) {
        written = text.isNotEmpty && !LocationService.looksLikeCoordinateLabel(text)
            ? text
            : '';
      }
      _addressController.text = written;

      _location.setDeliveryLocation(
        latitude: _pin.latitude,
        longitude: _pin.longitude,
        writtenAddress: written,
      );

      Navigator.pop(
        context,
        DeliveryLocationResult(
          latitude: _pin.latitude,
          longitude: _pin.longitude,
          writtenAddress: written,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildMapStack() {
    return Stack(
      alignment: Alignment.center,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _pin,
            initialZoom: 15,
            onMapReady: _onMapReady,
            onMapEvent: _onMapEvent,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.zanfu.visidine_website',
              retinaMode: RetinaMode.isHighDensity(context),
            ),
          ],
        ),
        // Fixed center pin
        const IgnorePointer(
          child: Padding(
            padding: EdgeInsets.only(bottom: 36),
            child: Icon(
              Icons.location_on,
              size: 48,
              color: AppColors.primary,
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Material(
            color: AppColors.cardBackground,
            elevation: 2,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: _goToMyLocation,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.my_location, size: 18, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'My location',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_geocoding)
          const Positioned(
            top: 12,
            left: 12,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAddressPanel({required bool wide}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, wide ? 20 : 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: wide ? const Offset(-3, 0) : const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_statusHint != null) ...[
              Text(
                _statusHint!,
                style: TextStyle(
                  fontSize: 12,
                  color: _gpsAvailable
                      ? AppColors.textSecondary
                      : AppColors.primary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
            ],
            const Text(
              'Address',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _addressController,
              maxLines: 3,
              minLines: 2,
              readOnly: _saving,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _saving
                    ? 'Updating address…'
                    : 'Address fills from map pin (internet required)',
                hintStyle: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: AppColors.scaffoldBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide:
                      BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(fontSize: 14, color: AppColors.heading),
            ),
            const SizedBox(height: 8),
            Text(
              'Pin: ${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (wide) const Spacer() else const SizedBox(height: 12),
            Center(
              child: AppBottomActionButton(
                label: 'CONFIRM LOCATION',
                width: math.min(
                  AppBottomActionButton.preferredWidth(context),
                  MediaQuery.sizeOf(context).width * (wide ? 0.4 : 1.0) - 32,
                ),
                loading: _saving,
                onTap: _canConfirm ? _confirm : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveHelper.isWide(context);
    final panelWidth =
        math.min(420.0, MediaQuery.sizeOf(context).width * 0.4);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: const CustomHeader(
        title: 'Select Location',
        showBackButton: true,
        subtitle: '',
        showCartIcon: false,
      ),
      body: isWide
          ? Row(
              children: [
                Expanded(child: _buildMapStack()),
                SizedBox(
                  width: panelWidth,
                  child: _buildAddressPanel(wide: true),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(child: _buildMapStack()),
                _buildAddressPanel(wide: false),
              ],
            ),
    );
  }
}
