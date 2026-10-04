import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../controllers/bottom_nav_controller.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import '../services/route_distance_service.dart';
import '../services/branch_locator.dart';
import '../utils/app_colors.dart';
import '../widgets/custom_header.dart';

class Branch {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String status;
  final String openingTime; // e.g. "09:00"
  final String closingTime; // e.g. "22:00"
  final String phone;
  final String address;
  double distanceKm; // Calculated at runtime

  Branch({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.status = 'Open Now',
    this.openingTime = '09:00',
    this.closingTime = '22:00',
    this.phone = '',
    this.address = '',
    this.distanceKm = 0.0,
  });

  factory Branch.fromFirestore(String docId, Map<String, dynamic> data) {
    String extractTime(dynamic value) {
      if (value == null) return '';
      if (value is Timestamp) {
        final dt = value.toDate();
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      if (value is DateTime) {
        return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
      }
      if (value is num) {
        // Support 900 / 2200 style or hour-only numbers
        final n = value.toInt();
        if (n >= 0 && n <= 23) {
          return '${n.toString().padLeft(2, '0')}:00';
        }
        if (n >= 100 && n <= 2359) {
          final h = n ~/ 100;
          final m = n % 100;
          return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        }
      }
      if (value is Map) {
        final h = value['hour'] ?? value['hours'] ?? value['h'];
        final m = value['minute'] ?? value['minutes'] ?? value['m'] ?? 0;
        if (h != null) {
          return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        }
      }

      final raw = value.toString().trim();
      if (raw.isEmpty) return '';
      // Ignore status-like values
      final lower = raw.toLowerCase();
      if (lower.contains('open now') ||
          lower == 'open' ||
          lower == 'closed' ||
          lower == 'true' ||
          lower == 'false') {
        return '';
      }
      return raw;
    }

    // Prefer explicit time fields — avoid ambiguous keys like `open` / `close`
    // which are often booleans or status strings ("Open Now").
    dynamic pickOpen() {
      for (final key in [
        'openingTime',
        'opening_time',
        'openTime',
        'open_time',
        'opensAt',
        'opens_at',
        'startTime',
        'start_time',
        'from',
      ]) {
        if (data[key] != null) return data[key];
      }
      final hours = data['hours'] ?? data['timings'] ?? data['timing'];
      if (hours is Map) {
        return hours['open'] ??
            hours['opening'] ??
            hours['from'] ??
            hours['start'];
      }
      return null;
    }

    dynamic pickClose() {
      for (final key in [
        'closingTime',
        'closing_time',
        'closeTime',
        'close_time',
        'closesAt',
        'closes_at',
        'endTime',
        'end_time',
        'to',
      ]) {
        if (data[key] != null) return data[key];
      }
      final hours = data['hours'] ?? data['timings'] ?? data['timing'];
      if (hours is Map) {
        return hours['close'] ??
            hours['closing'] ??
            hours['to'] ??
            hours['end'];
      }
      return null;
    }

    // Combined string like "09:00 - 22:00" / "9 AM - 10 PM"
    String openTime = extractTime(pickOpen());
    String closeTime = extractTime(pickClose());
    if (openTime.isEmpty || closeTime.isEmpty) {
      final combined =
          (data['hours'] ??
                  data['timings'] ??
                  data['timing'] ??
                  data['workingHours'] ??
                  data['working_hours'] ??
                  '')
              .toString();
      final rangeMatch = RegExp(
        r'(.+?)\s*[-–—to]+\s*(.+)',
        caseSensitive: false,
      ).firstMatch(combined);
      if (rangeMatch != null) {
        if (openTime.isEmpty) openTime = extractTime(rangeMatch.group(1));
        if (closeTime.isEmpty) closeTime = extractTime(rangeMatch.group(2));
      }
    }

    if (openTime.isEmpty) openTime = '09:00';
    if (closeTime.isEmpty) closeTime = '22:00';

    debugPrint(
      'Branch[$docId] keys=${data.keys.toList()} open=$openTime close=$closeTime',
    );

    final rawPhone =
        data['phone'] ??
        data['phone_number'] ??
        data['phoneNumber'] ??
        data['number'] ??
        data['contact'] ??
        '';

    final rawAddress =
        data['address'] ??
        data['address_line'] ??
        data['location'] ??
        data['addr'] ??
        '';

    return Branch(
      id: docId,
      name: data['name']?.toString() ?? 'Branch',
      latitude:
          (data['latitude'] as num?)?.toDouble() ??
          (data['lat'] as num?)?.toDouble() ??
          0.0,
      longitude:
          (data['longitude'] as num?)?.toDouble() ??
          (data['lng'] as num?)?.toDouble() ??
          (data['lon'] as num?)?.toDouble() ??
          0.0,
      status: data['status']?.toString() ?? 'Open Now',
      openingTime: openTime,
      closingTime: closeTime,
      phone: rawPhone.toString(),
      address: rawAddress.toString(),
    );
  }
}

class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  // Pulse animation for user location marker
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Track current zoom level for zoom-responsive marker sizes
  double _mapZoom = 13.0;
  StreamSubscription<MapEvent>? _mapEventSub;
  bool _mapReady = false;
  LatLng? _pendingMapCenter;
  double _pendingZoom = 13.0;

  List<Branch> _rawBranches = []; // un-sorted, needed for re-calc
  List<Branch> _branches = [];
  bool _isLoading = true;
  bool _isCalculatingDistances = false;
  String? _error;
  bool _showAllBranches = false;
  int _distanceCalcGeneration = 0;
  String? _expandedBranchId;

  // Fallback branches matching user screenshot/data
  final List<Map<String, dynamic>> _fallbackBranchesData = [
    {
      'id': 'adyala',
      'name': 'Adyala Rawalpindi',
      'latitude': 33.5657,
      'longitude': 73.0169,
      'status': 'Open Now',
      'openingTime': '09:00',
      'closingTime': '22:00',
      'phone': '+92-51-1234567',
      'address': 'Adyala Road, Rawalpindi',
    },
    {
      'id': 'bahria_7',
      'name': 'Bahria Town Phase 7 Rawalpindi',
      'latitude': 33.5255,
      'longitude': 73.0815,
      'status': 'Open Now',
      'openingTime': '09:00',
      'closingTime': '22:00',
      'phone': '+92-51-2345678',
      'address': 'Phase 7, Bahria Town, Rawalpindi',
    },
    {
      'id': 'scheme_3',
      'name': 'Scheme 3 Rawalpindi',
      'latitude': 33.5912,
      'longitude': 73.1112,
      'status': 'Open Now',
      'openingTime': '09:00',
      'closingTime': '22:00',
      'phone': '+92-51-3456789',
      'address': 'Scheme 3, Rawalpindi',
    },
    {
      'id': 'civic_center',
      'name': 'Bahria Town Civic Center Islamabad',
      'latitude': 33.5684,
      'longitude': 73.1254,
      'status': 'Open Now',
      'openingTime': '10:00',
      'closingTime': '22:00',
      'phone': '+92-51-4567890',
      'address': 'Civic Center, Bahria Town, Islamabad',
    },
    {
      'id': 'kalma_chowk',
      'name': 'Kalma Chowk Rawalpindi',
      'latitude': 33.6010,
      'longitude': 73.0682,
      'status': 'Open Now',
      'openingTime': '09:00',
      'closingTime': '21:00',
      'phone': '+92-51-5678901',
      'address': 'Kalma Chowk, Rawalpindi',
    },
    {
      'id': 'pwd',
      'name': 'PWD Islamabad',
      'latitude': 33.5932,
      'longitude': 73.1610,
      'status': 'Open Now',
      'openingTime': '09:00',
      'closingTime': '22:00',
      'phone': '+92-51-6789012',
      'address': 'PWD Housing Scheme, Islamabad',
    },
    {
      'id': 'madison',
      'name': 'Madison Square Mall',
      'latitude': 33.6515,
      'longitude': 73.0722,
      'status': 'Open Now',
      'openingTime': '11:00',
      'closingTime': '23:00',
      'phone': '+92-51-7890123',
      'address': 'Madison Square Mall, Rawalpindi',
    },
  ];

  Widget _openClosedChip(bool isOpen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isOpen
            ? const Color(0xFF16A34A).withValues(alpha: 0.12)
            : const Color(0xFFDC2626).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isOpen ? 'Open' : 'Closed',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isOpen ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        ),
      ),
    );
  }

  /// Formats opening/closing times for display, e.g. "9:00 AM - 10:00 PM"
  String _formatBranchHours(Branch branch) {
    String fmt(String raw) {
      final cleaned = raw.trim();
      if (cleaned.isEmpty) return '';

      // Already has AM/PM — keep as-is (normalize spacing)
      final lower = cleaned.toLowerCase();
      if (lower.contains('am') || lower.contains('pm')) {
        return cleaned
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAllMapped(
              RegExp(r'\b(am|pm)\b', caseSensitive: false),
              (m) => m.group(0)!.toUpperCase(),
            );
      }

      try {
        final parts = cleaned.split(RegExp(r'[:\.]'));
        final hour = int.parse(parts[0].trim());
        final minute = parts.length > 1
            ? int.parse(parts[1].trim().split(' ').first)
            : 0;
        final h = hour == 0
            ? 12
            : hour > 12
            ? hour - 12
            : hour;
        final m = minute.toString().padLeft(2, '0');
        final period = hour < 12 ? 'AM' : 'PM';
        return '$h:$m $period';
      } catch (_) {
        return cleaned;
      }
    }

    final open = fmt(branch.openingTime);
    final close = fmt(branch.closingTime);
    if (open.isEmpty && close.isEmpty) return '--';
    if (open.isEmpty) return close;
    if (close.isEmpty) return open;
    return '$open-$close';
  }

  void _setShowAllBranches(bool show) {
    setState(() => _showAllBranches = show);
    Provider.of<BottomNavController>(
      context,
      listen: false,
    ).setHideBottomNav(show);
  }

  @override
  void initState() {
    super.initState();
    // Pulse animation setup
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 14.0, end: 22.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    // Map event listener is attached in onMapReady (controller not ready before that)
    _loadBranches();
  }

  void _onMapReady() {
    _mapReady = true;
    _mapEventSub?.cancel();
    _mapEventSub = _mapController.mapEventStream.listen((event) {
      if (event is MapEventMove ||
          event is MapEventScrollWheelZoom ||
          event is MapEventDoubleTapZoom ||
          event is MapEventFlingAnimation) {
        final zoom = _mapController.camera.zoom;
        if ((zoom - _mapZoom).abs() > 0.1) {
          setState(() => _mapZoom = zoom);
        }
      }
    });
    if (_pendingMapCenter != null) {
      _mapController.move(_pendingMapCenter!, _pendingZoom);
      _pendingMapCenter = null;
    }
  }

  void _safeMoveMap(LatLng target, double zoom) {
    if (_mapReady) {
      _mapController.move(target, zoom);
    } else {
      _pendingMapCenter = target;
      _pendingZoom = zoom;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Triggered every time LocationService notifies; recalculate distances
    if (_rawBranches.isNotEmpty) {
      final pos = Provider.of<LocationService>(context).currentPosition;
      _recalculateDistances(pos);
    }
  }

  @override
  void dispose() {
    _mapEventSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<Branch> fetchedBranches = [];

      // Prefer local disk / memory cache (filled on splash via catalog_version)
      await FirestoreService.preloadBranchesCache();
      var cached = FirestoreService.getCachedBranches();

      // First launch / empty cache: one Firebase fetch, then persist locally
      if (cached.isEmpty) {
        await FirestoreService.refreshBranchesCacheInBackground();
        cached = FirestoreService.getCachedBranches();
      }

      if (cached.isNotEmpty) {
        fetchedBranches = cached.map((data) {
          final id = data['id']?.toString() ?? '';
          return Branch.fromFirestore(id, data);
        }).toList();
      }

      // If still empty, use hardcoded fallback
      if (fetchedBranches.isEmpty) {
        fetchedBranches = _fallbackBranchesData
            .map(
              (d) => Branch(
                id: d['id'],
                name: d['name'],
                latitude: d['latitude'],
                longitude: d['longitude'],
                status: d['status'] ?? 'Open Now',
                openingTime: d['openingTime'] ?? '09:00',
                closingTime: d['closingTime'] ?? '22:00',
                phone: d['phone'] ?? '',
                address: d['address'] ?? '',
              ),
            )
            .toList();
      }

      _rawBranches = fetchedBranches;

      // Initial distance calculation (position may be null yet)
      final pos = Provider.of<LocationService>(
        context,
        listen: false,
      ).currentPosition;
      _recalculateDistances(pos);

      // Move camera when map is ready (IndexedStack / loading can delay FlutterMap)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final latestPos = Provider.of<LocationService>(
          context,
          listen: false,
        ).currentPosition;
        if (latestPos != null) {
          _safeMoveMap(LatLng(latestPos.latitude, latestPos.longitude), 13.0);
        } else if (_branches.isNotEmpty) {
          _safeMoveMap(
            LatLng(_branches.first.latitude, _branches.first.longitude),
            13.0,
          );
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  double _straightLineDistanceKm(
    double originLat,
    double originLng,
    Branch branch,
  ) {
    final meters = Geolocator.distanceBetween(
      originLat,
      originLng,
      branch.latitude,
      branch.longitude,
    );
    return meters / 1000.0;
  }

  /// Re-sort branches by driving-route distance from [userPos].
  Future<void> _recalculateDistances(Position? userPos) async {
    if (_rawBranches.isEmpty) return;

    final generation = ++_distanceCalcGeneration;
    final originLat =
        userPos?.latitude ?? LocationService().deliveryLatitude ?? 33.6007;
    final originLng =
        userPos?.longitude ?? LocationService().deliveryLongitude ?? 73.0679;
    final branches = List<Branch>.from(_rawBranches);

    if (mounted) {
      setState(() => _isCalculatingDistances = true);
    }

    final routeDistances = await RouteDistanceService.getDrivingDistancesKm(
      originLat: originLat,
      originLng: originLng,
      destinations: branches
          .map((b) => (lat: b.latitude, lng: b.longitude))
          .toList(),
    );

    if (!mounted || generation != _distanceCalcGeneration) return;

    for (var i = 0; i < branches.length; i++) {
      branches[i].distanceKm =
          routeDistances[i] ??
          _straightLineDistanceKm(originLat, originLng, branches[i]);
    }

    branches.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    setState(() {
      _branches = branches;
      _isLoading = false;
      _isCalculatingDistances = false;
    });
  }

  void _moveToLocation(double lat, double lng) {
    _safeMoveMap(LatLng(lat, lng), 15.0);
  }

  @override
  Widget build(BuildContext context) {
    // listen:true → rebuild + didChangeDependencies fires when location updates
    final locationService = Provider.of<LocationService>(context);
    final userPos = locationService.currentPosition;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.matteBlack,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.matteBlack,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $_error', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadBranches,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final nearestBranch = _branches.isNotEmpty ? _branches.first : null;
    final otherBranches = _branches.length > 1
        ? _branches.sublist(1)
        : <Branch>[];

    // ── Markers ──────────────────────────────────────────────────────────────
    final List<Marker> markers = [];

    // Zoom-responsive marker sizes: scale smoothly with zoom level
    // At zoom 13 → base sizes; each zoom step scales proportionally
    final double zoomScale = (_mapZoom / 13.0).clamp(0.55, 1.6);
    final double userMarkerSize = 46.0 * zoomScale;
    final double userInnerSize = 24.0 * zoomScale;
    final double userIconSize = 13.0 * zoomScale;
    final double branchMarkerSize = 28.0 * zoomScale;
    final double branchIconSize = 13.0 * zoomScale;

    // 1. User location marker — animated pulse + person icon
    if (userPos != null) {
      markers.add(
        Marker(
          width: userMarkerSize,
          height: userMarkerSize,
          point: LatLng(userPos.latitude, userPos.longitude),
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, __) => Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulse ring
                Container(
                  width: _pulseAnimation.value * zoomScale,
                  height: _pulseAnimation.value * zoomScale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue.withOpacity(0.18),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.35),
                      width: 1.5,
                    ),
                  ),
                ),
                // Inner solid circle with person icon
                Container(
                  width: userInnerSize,
                  height: userInnerSize,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x661E88E5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.person,
                    color: Colors.white,
                    size: userIconSize,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 2. Branch markers — black circle + zanfu logo + name label above
    for (var branch in _branches) {
      final double labelFontSize = (9.0 * zoomScale).clamp(7.0, 12.0);
      final double totalHeight = branchMarkerSize + 35.0 * zoomScale + 15.0;
      markers.add(
        Marker(
          width: 90.0 * zoomScale,
          height: totalHeight,
          point: LatLng(branch.latitude, branch.longitude),
          child: GestureDetector(
            onTap: () {
              _moveToLocation(branch.latitude, branch.longitude);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${branch.name} — ${branch.distanceKm.toStringAsFixed(1)} km away',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Branch name label above the circle
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    branch.name,
                    style: TextStyle(
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                SizedBox(height: 2 * zoomScale),
                // Black circle with zanfu logo
                Container(
                  width: branchMarkerSize,
                  height: branchMarkerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.30),
                        blurRadius: 5,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(2.0 * zoomScale),
                    child: Image.asset(
                      'assets/zanfu_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_showAllBranches,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showAllBranches) {
          _setShowAllBranches(false);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.matteBlack,
        // Tab already has Zanfu header — only show CustomHeader on full list.
        appBar: _showAllBranches
            ? CustomHeader(
                title: 'Branches',
                subtitle: '',
                showBackButton: true,
                showCartIcon: false,
                onBackTap: () => _setShowAllBranches(false),
              )
            : null,
        body: _showAllBranches
            ? ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                children: [
                  if (nearestBranch != null) ...[
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        'Nearest Branch',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    _buildBranchTile(nearestBranch, userPos),
                    const SizedBox(height: 24),
                  ],
                  if (otherBranches.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        'Other Branches',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    ...otherBranches.map((b) => _buildBranchTile(b, userPos)),
                  ],
                ],
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: userPos != null
                            ? LatLng(userPos.latitude, userPos.longitude)
                            : (_branches.isNotEmpty
                                  ? LatLng(
                                      _branches.first.latitude,
                                      _branches.first.longitude,
                                    )
                                  : const LatLng(33.6007, 73.0679)),
                        initialZoom: 13.0,
                        onMapReady: _onMapReady,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.zanfu.visidine_website',
                        ),
                        MarkerLayer(markers: markers),
                      ],
                    ),
                  ),
                  if (userPos != null)
                    Positioned(
                      right: 16,
                      bottom: 190,
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: AppColors.cardBackground,
                        foregroundColor: AppColors.primary,
                        onPressed: () {
                          _moveToLocation(userPos.latitude, userPos.longitude);
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.matteBlack,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        border: Border(
                          top: BorderSide(color: AppColors.border),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 36,
                              height: 3,
                              decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Nearest Branch',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () {
                                  _setShowAllBranches(true);
                                },
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Show all branches',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 2),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (nearestBranch != null)
                            _buildExpandableBranchCard(
                              nearestBranch,
                              userPos,
                              compact: true,
                              onHeaderTap: () {
                                _moveToLocation(
                                  nearestBranch.latitude,
                                  nearestBranch.longitude,
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBranchTile(Branch branch, Position? userPos) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _buildExpandableBranchCard(
        branch,
        userPos,
        compact: false,
        onHeaderTap: () {
          _setShowAllBranches(false);
          _moveToLocation(branch.latitude, branch.longitude);
        },
      ),
    );
  }

  Widget _buildExpandableBranchCard(
    Branch branch,
    Position? userPos, {
    required bool compact,
    VoidCallback? onHeaderTap,
  }) {
    final isExpanded = _expandedBranchId == branch.id;
    final logoSize = compact ? 36.0 : 44.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
            onTap: onHeaderTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 16,
                vertical: compact ? 10 : 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: logoSize,
                    height: logoSize,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 2.0 : 3.0),
                      child: Image.asset(
                        'assets/zanfu_logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 12 : 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                branch.name,
                                style: TextStyle(
                                  fontSize: compact ? 14 : 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _openClosedChip(
                              BranchLocator.isOpenNow(
                                branch.openingTime,
                                branch.closingTime,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatBranchHours(branch),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (_isCalculatingDistances && compact)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.primary,
                            ),
                          )
                        else
                          Text(
                            userPos != null
                                ? '${branch.distanceKm.toStringAsFixed(1)} km away'
                                : 'Location unavailable',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _expandedBranchId = isExpanded ? null : branch.id;
                      });
                    },
                    child: AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 16,
                      0,
                      compact ? 12 : 16,
                      compact ? 12 : 14,
                    ),
                    child: Column(
                      children: [
                        const Divider(height: 1, color: AppColors.divider),
                        const SizedBox(height: 10),
                        if (branch.address.isNotEmpty)
                          _buildDetailRow(
                            Icons.location_on_outlined,
                            branch.address,
                          ),
                        if (branch.address.isNotEmpty &&
                            branch.phone.isNotEmpty)
                          const SizedBox(height: 8),
                        if (branch.phone.isNotEmpty)
                          _buildDetailRow(Icons.phone_outlined, branch.phone),
                        if (branch.address.isEmpty && branch.phone.isEmpty)
                          const Text(
                            'No extra details available',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
