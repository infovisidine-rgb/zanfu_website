import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/app_colors.dart';
import '../utils/google_auth_helper.dart';
import '../utils/responsive_helper.dart';
import '../controllers/cart_controller.dart';
import '../controllers/order_controller.dart';
import '../controllers/checkout_controller.dart';
import '../controllers/user_profile_controller.dart';
import '../services/location_service.dart';
import '../services/branch_locator.dart';
import '../utils/network_helper.dart';
import '../widgets/app_bottom_action_button.dart';
import '../utils/app_navigation.dart';
import 'map_location_picker_screen.dart';
import 'google_login_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final CartController _cart = CartController();
  final CheckoutController _checkoutController = CheckoutController();
  final TextEditingController _deliveryInstructionsController =
      TextEditingController();
  final TextEditingController _locationEditController = TextEditingController();
  final TextEditingController _phoneEditController = TextEditingController();
  final TextEditingController _tableNumberController = TextEditingController();
  bool _isEditingLocation = false;
  bool _isEditingPhone = false;
  String _deliveryAddress = "Loading location...";
  String _phoneNumber = "Loading phone...";
  String _customerName = "";
  String? _phoneFieldError;

  List<BranchChoice> _branches = [];
  BranchChoice? _selectedBranch;
  bool _loadingBranches = false;
  String? _branchGateMessage;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _checkoutController.addListener(_onCheckoutChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureBranchAssignment(forceNearest: true);
    });
  }

  void _onCheckoutChanged() {
    if (!mounted) return;
    setState(() {});
    _ensureBranchAssignment(forceNearest: true);
  }

  @override
  void dispose() {
    _checkoutController.removeListener(_onCheckoutChanged);
    _deliveryInstructionsController.dispose();
    _locationEditController.dispose();
    _phoneEditController.dispose();
    _tableNumberController.dispose();
    super.dispose();
  }

  double get _branchTaxPercent => _selectedBranch?.taxPercent ?? 0;

  double _taxAmountFor(double subtotal) {
    final p = _branchTaxPercent;
    if (p <= 0) return 0;
    return subtotal * p / 100.0;
  }

  double _billTotalFor(double subtotal) {
    return subtotal - _discountAmount + _taxAmountFor(subtotal);
  }

  Future<bool> _ensureBranchAssignment({bool forceNearest = false}) async {
    if (_loadingBranches) return false;
    final orderType = _checkoutController.selectedOrderType;

    setState(() {
      _loadingBranches = true;
      _branchGateMessage = null;
    });
    try {
      double? lat;
      double? lng;

      if (_checkoutController.isDelivery) {
        final loc = LocationService();
        if (!loc.hasDeliveryPin) {
          setState(() {
            _branches = [];
            _selectedBranch = null;
            _branchGateMessage =
                'Select delivery location on the map to find a branch.';
          });
          return false;
        }
        lat = loc.deliveryLatitude;
        lng = loc.deliveryLongitude;
      } else {
        // Pickup / Dine In: internet + live GPS
        if (!await NetworkHelper.hasConnectivity()) {
          if (!mounted) return false;
          final retry = await NetworkHelper.showNoInternetDialog(
            context,
            message:
                'Internet is required to find the nearest branch. Turn on internet and try again.',
            showRetryButton: true,
          );
          if (!mounted) return false;
          if (!retry || !await NetworkHelper.hasConnectivity()) {
            setState(() {
              _branches = [];
              _selectedBranch = null;
              _branchGateMessage = 'Turn on internet to find nearest branch.';
            });
            return false;
          }
        }

        if (!mounted) return false;
        final pos = await LocationService().ensureCurrentPosition(context);
        if (!mounted) return false;
        if (pos != null) {
          lat = pos.latitude;
          lng = pos.longitude;
        }
      }

      final list = await BranchLocator.getBranchesSortedByDistance(
        latitude: lat,
        longitude: lng,
        orderType: orderType,
      );
      if (!mounted) return false;

      if (list.isEmpty) {
        setState(() {
          _branches = [];
          _selectedBranch = null;
          if (_checkoutController.isDelivery) {
            _branchGateMessage =
                'No branch available for delivery right now.';
          } else if (_checkoutController.isPickup) {
            _branchGateMessage = 'No pickup (takeaway) branch available.';
          } else {
            _branchGateMessage = 'No dine-in branch available.';
          }
        });
        return false;
      }

      // Nearest by calculated distance only (no delivery_distance radius filter)
      final openList = list.where((b) => b.isOpenNow).toList();
      final preferredPool = openList.isNotEmpty ? openList : list;

      setState(() {
        _branches = list;
        _branchGateMessage = null;
        if (forceNearest ||
            _selectedBranch == null ||
            !list.any((b) => b.name == _selectedBranch!.name)) {
          _selectedBranch = preferredPool.first;
        } else {
          // Keep user pick but refresh THIS branch's live distance/specs
          _selectedBranch = list.firstWhere(
            (b) => b.name == _selectedBranch!.name,
            orElse: () => preferredPool.first,
          );
        }
      });
      return _selectedBranch != null;
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  Future<void> _showBranchPicker() async {
    // Dine In always uses nearest branch — no manual change
    if (_checkoutController.isDineIn) return;
    if (_branches.isEmpty || _selectedBranch == null) {
      final ok = await _ensureBranchAssignment();
      if (!ok || !mounted) return;
    }
    if (_branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _branchGateMessage ?? 'No branches available right now.',
          ),
        ),
      );
      return;
    }

    final chosen = await showModalBottomSheet<BranchChoice>(
      context: context,
      backgroundColor: AppColors.matteBlack,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choose branch',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nearest is suggested. You can pick another.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _branches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final b = _branches[index];
                      final selected = _selectedBranch?.name == b.name;
                      final isNearest = index == 0;
                      return Material(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : AppColors.scaffoldBackground,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(ctx, b),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    _zanfuBranchLogo(size: 40),
                                    if (selected)
                                      Positioned(
                                        right: -2,
                                        bottom: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(1),
                                          decoration: const BoxDecoration(
                                            color: AppColors.cardBackground,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check_circle,
                                            color: AppColors.primary,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              b.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          if (isNearest)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'Nearest',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 6),
                                          _openClosedChip(b.isOpenNow),
                                        ],
                                      ),
                                      if (b.address.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          b.address,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                      if (b.distanceKm != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '${b.distanceKm!.toStringAsFixed(1)} km away',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                      if (b.openTime.isNotEmpty ||
                                          b.closeTime.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          '${b.openTime}${b.openTime.isNotEmpty && b.closeTime.isNotEmpty ? ' – ' : ''}${b.closeTime}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (chosen != null && mounted) {
      setState(() => _selectedBranch = chosen);
    }
  }

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

  List<Widget> _branchDetailLines(BranchChoice b, {bool showStatusInline = true}) {
    final wide = ResponsiveHelper.isDesktop(context);
    final nameSize = wide ? 15.5 : 14.0;
    final detailSize = wide ? 13.5 : 12.0;
    final metaSize = wide ? 12.5 : 11.0;
    return [
      if (showStatusInline)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                b.name,
                style: TextStyle(
                  fontSize: nameSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _openClosedChip(b.isOpenNow),
          ],
        )
      else ...[
        Text(
          b.name,
          style: TextStyle(
            fontSize: nameSize,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        _openClosedChip(b.isOpenNow),
      ],
      if (b.address.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          b.address,
          style: TextStyle(fontSize: detailSize, color: AppColors.textSecondary),
        ),
      ],
      if (b.distanceKm != null) ...[
        const SizedBox(height: 4),
        Text(
          '${b.distanceKm!.toStringAsFixed(1)} km away'
          '${_branches.isNotEmpty && _branches.first.name == b.name ? ' · nearest' : ''}',
          style: TextStyle(fontSize: metaSize, color: AppColors.textSecondary),
        ),
      ],
      if (b.openTime.isNotEmpty || b.closeTime.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          'Hours: ${b.openTime}${b.openTime.isNotEmpty && b.closeTime.isNotEmpty ? ' – ' : ''}${b.closeTime}',
          style: TextStyle(fontSize: metaSize, color: AppColors.textSecondary),
        ),
      ],
    ];
  }

  Widget _zanfuBranchLogo({double size = 52}) {
    return Container(
      width: size,
      height: size,
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
        padding: EdgeInsets.all(size * 0.06),
        child: Image.asset(
          'assets/zanfu_logo.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildBranchSection() {
    final title = _checkoutController.isDelivery
        ? 'Delivery branch'
        : _checkoutController.isDineIn
            ? 'Dine In branch'
            : 'Pickup branch';
    final branchRow = _selectedBranch == null
        ? null
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _zanfuBranchLogo(size: ResponsiveHelper.isWide(context) ? 40 : 48),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _branchDetailLines(
                    _selectedBranch!,
                    // Pickup: status below name so it doesn't sit against CHANGE
                    showStatusInline: !_checkoutController.isPickup,
                  ),
                ),
              ),
              if (_checkoutController.isPickup) ...[
                const SizedBox(width: 14),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    'CHANGE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          title,
          style: TextStyle(
            fontSize: ResponsiveHelper.isWide(context) ? 16.5 : 15,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: _loadingBranches
              ? Row(
                  children: [
                    _zanfuBranchLogo(size: ResponsiveHelper.isWide(context) ? 40 : 48),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 14,
                            width: 140,
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 11,
                            width: 90,
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                )
              : _selectedBranch == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _branchGateMessage ??
                              'Select location to find your nearest branch.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () {
                            if (_checkoutController.isDelivery &&
                                !LocationService().hasDeliveryPin) {
                              _openLocationPicker();
                            } else {
                              _ensureBranchAssignment(forceNearest: true);
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            _checkoutController.isDelivery &&
                                    !LocationService().hasDeliveryPin
                                ? 'SELECT LOCATION'
                                : 'TRY AGAIN',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    )
                  : (_checkoutController.isPickup
                      ? InkWell(
                          onTap: _showBranchPicker,
                          borderRadius: BorderRadius.circular(8),
                          child: branchRow,
                        )
                      : branchRow!),
        ),
      ],
    );
  }

  Future<void> _loadProfileData() async {
    final loc = LocationService();
    final user = FirebaseAuth.instance.currentUser;

    if (loc.writtenAddress.trim().isNotEmpty) {
      _deliveryAddress = loc.writtenAddress;
    }

    if (LocationService.looksLikeCoordinateLabel(_deliveryAddress) ||
        _deliveryAddress.trim().isEmpty ||
        _deliveryAddress == 'Loading location...') {
      // ignore: unawaited_futures
      loc.refreshAddressFromPin().then((text) {
        if (!mounted || text == null || text.isEmpty) return;
        setState(() => _deliveryAddress = text);
      });
    }

    if (user != null) {
      try {
        final profile = UserProfileController();
        await profile.ensureLoaded();
        setState(() {
          _customerName = profile.userName.isNotEmpty
              ? profile.userName
              : (user.displayName ?? "Customer");
          if (_deliveryAddress == "Loading location..." ||
              _deliveryAddress.trim().isEmpty) {
            if (loc.currentAddress != null &&
                loc.currentAddress!.trim().isNotEmpty) {
              _deliveryAddress = loc.currentAddress!;
            } else {
              _deliveryAddress = "No Location Selected";
            }
          }
          if (profile.userPhone.trim().isNotEmpty) {
            _phoneNumber = _normalizePhoneDisplay(profile.userPhone);
          } else {
            _phoneNumber = "No phone number added";
          }
        });
        return;
      } catch (e) {
        debugPrint("Error loading profile details in checkout: $e");
      }
    }
    setState(() {
      _customerName = "Customer";
      if (_deliveryAddress == "Loading location..." ||
          _deliveryAddress.trim().isEmpty) {
        _deliveryAddress = loc.writtenAddress.isNotEmpty
            ? loc.writtenAddress
            : "No Location Selected";
      }
      _phoneNumber = "No phone number added";
    });
  }

  // Line-item discounts are applied in subtotal; this is an extra bill-level discount.
  double get _discountAmount => 0;

  double _getCartSubtotal() {
    double total = 0;
    for (var item in _cart.items) {
      double priceVal = 0;
      final priceStr = item.foodModel.price;
      final variation = item.selectedVariation?.trim().toLowerCase() ?? '';
      if (priceStr.contains('|')) {
        if (variation.isNotEmpty) {
          for (final part in priceStr.split('|')) {
            final clean = part.trim();
            final match =
                RegExp(r'^(.+?)\s+(\d+(?:\.\d+)?)\s*$').firstMatch(clean);
            if (match == null) continue;
            var name = match.group(1)!.trim().toLowerCase();
            name = name.replaceAll(RegExp(r'\b(rs|pkr)\b'), '').trim();
            if (name == 's') name = 'small';
            if (name == 'm') name = 'medium';
            if (name == 'l') name = 'large';
            if (name == variation ||
                name.startsWith(variation) ||
                variation.startsWith(name)) {
              priceVal = double.tryParse(match.group(2)!) ?? 0;
              break;
            }
          }
        }
        if (priceVal <= 0) {
          priceVal = item.foodModel.displayOriginalPrice;
        }
      } else {
        priceVal = item.foodModel.displayOriginalPrice;
      }
      total += item.foodModel.discountedFrom(priceVal) * item.quantity;
    }
    return total;
  }

  String get _displayAddress {
    final loc = LocationService();
    final local = _deliveryAddress.trim();
    if (local.isNotEmpty &&
        local != 'Loading location...' &&
        local != 'Fetching location...' &&
        local != 'No Location Selected' &&
        !LocationService.looksLikeCoordinateLabel(local)) {
      return local;
    }
    final written = loc.writtenAddress.trim();
    if (written.isNotEmpty &&
        !LocationService.looksLikeCoordinateLabel(written)) {
      return written;
    }
    return local.isEmpty ? 'No Location Selected' : local;
  }

  void _startEditLocation() {
    _openLocationPicker();
  }

  Future<void> _openLocationPicker() async {
    final loc = LocationService();
    final result = await Navigator.push<DeliveryLocationResult>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          initialWrittenAddress:
              (_displayAddress == "No Location Selected" ||
                      _displayAddress == "Loading location..." ||
                      _displayAddress == "Fetching location...")
                  ? loc.writtenAddress
                  : _displayAddress,
          initialLatitude: loc.deliveryLatitude,
          initialLongitude: loc.deliveryLongitude,
        ),
      ),
    );
    if (result != null && mounted) {
      final loc = LocationService();
      var addr = result.writtenAddress.trim();
      if (LocationService.looksLikeCoordinateLabel(addr) || addr.isEmpty) {
        addr = loc.writtenAddress.trim();
      }
      if (LocationService.looksLikeCoordinateLabel(addr) || addr.isEmpty) {
        final refreshed = await loc.refreshAddressFromPin();
        if (refreshed != null && refreshed.isNotEmpty) addr = refreshed;
      }
      setState(() {
        _deliveryAddress = addr.isNotEmpty ? addr : result.writtenAddress;
        _isEditingLocation = false;
      });
      await _ensureBranchAssignment(forceNearest: true);
    }
  }

  void _saveEditedLocation() {
    final text = _locationEditController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _deliveryAddress = text;
      });
      LocationService().setManualAddress(text);
    }
    setState(() {
      _isEditingLocation = false;
    });
  }

  void _startEditPhone() {
    setState(() {
      _isEditingPhone = true;
      _phoneFieldError = null;
      _phoneEditController.text = _localPhoneDigits(_phoneNumber);
    });
  }

  void _saveEditedPhone() {
    final digits = _localPhoneDigits(_phoneEditController.text);
    if (!_isValidLocalPhone(digits)) {
      setState(() {
        _phoneFieldError = 'Enter proper number';
        _phoneEditController.text = digits;
      });
      return;
    }
    setState(() {
      _phoneNumber = _fullPhoneFromLocal(digits);
      _phoneFieldError = null;
      _isEditingPhone = false;
    });
  }

  /// Digits after country code. If number starts with +92 / 92 / 0, strip that
  /// and keep the next 10 digits only (for the field + fixed "+92 " prefix).
  String _localPhoneDigits(String raw) {
    var s = raw.trim();
    if (s == 'Loading phone...' || s == 'No phone number added') return '';

    // Prefer stripping "+92" from the original string first.
    final lower = s.replaceAll(RegExp(r'[\s-]'), '');
    if (lower.startsWith('+92')) {
      s = lower.substring(3);
    } else if (lower.startsWith('0092')) {
      s = lower.substring(4);
    } else {
      s = lower;
    }

    var digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('92') && digits.length > 10) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0') && digits.length > 10) {
      digits = digits.substring(1);
    }
    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }
    return digits;
  }

  bool _isValidLocalPhone(String digits) =>
      RegExp(r'^\d{10}$').hasMatch(digits);

  String _fullPhoneFromLocal(String digits) => '+92$digits';

  /// Normalize any incoming phone for display / place-order (always +92 + 10).
  String _normalizePhoneDisplay(String raw) {
    final digits = _localPhoneDigits(raw);
    if (digits.isEmpty) return 'No phone number added';
    if (_isValidLocalPhone(digits)) return _fullPhoneFromLocal(digits);
    // Partial / invalid — still show +92 + whatever local digits we have
    return _fullPhoneFromLocal(digits);
  }

  bool _hasValidCheckoutPhone() {
    final digits = _localPhoneDigits(_phoneNumber);
    return _isValidLocalPhone(digits);
  }

  Future<void> _showOrderBlockedDialog(
    String message, {
    String title = 'Cannot Place Order',
    VoidCallback? onOk,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.matteBlack,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.cancel_rounded,
                color: Color(0xFFDC2626),
                size: 26,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.matteBlack,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onOk?.call();
              },
              child: const Text(
                'OK',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSuccessDialog() async {
    // Capture cart items and totals before clearing
    final cartItemsCopy = List.from(_cart.items);
    final subtotal = _getCartSubtotal();
    final taxAmount = _taxAmountFor(subtotal);
    final total = _billTotalFor(subtotal);
    final address = _displayAddress;
    final specialInstructions = CartController().specialInstructions;
    final deliveryInstructions = _checkoutController.isDelivery
        ? _deliveryInstructionsController.text.trim()
        : '';
    final tableNo = _tableNumberController.text.trim();
    final loc = LocationService();

    String deliveryAddress;
    if (_checkoutController.isDelivery) {
      deliveryAddress = address;
    } else if (_checkoutController.isDineIn) {
      deliveryAddress = 'Dine In - Table $tableNo';
    } else {
      deliveryAddress = 'Pickup';
    }

    // Block UI until Firebase write succeeds
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    final placed = await OrderController().placeOrder(
      cartItems: cartItemsCopy.cast(),
      totalAmount: total,
      tax: taxAmount,
      deliveryAddress: deliveryAddress,
      deliveryInstructions: deliveryInstructions,
      specialInstructions: specialInstructions,
      customerName: _customerName.isEmpty ? "Customer" : _customerName,
      customerPhone:
          _phoneNumber == "Loading phone..." ||
              _phoneNumber == "No phone number added"
          ? ""
          : _phoneNumber,
      orderType: _checkoutController.selectedOrderType,
      tableNumber: _checkoutController.isDineIn ? tableNo : '',
      deliveryLatitude: _checkoutController.isDelivery
          ? loc.deliveryLatitude
          : null,
      deliveryLongitude: _checkoutController.isDelivery
          ? loc.deliveryLongitude
          : null,
      branchName: _selectedBranch?.name,
      branchAddress: _selectedBranch?.address,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // loading

    if (!placed) {
      await _showOrderBlockedDialog(
        'Order could not be placed. Check internet and try again.',
      );
      return;
    }

    _cart.clearCart();

    final nav = Navigator.of(context, rootNavigator: true);

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => const _SuccessDialog(),
    ).then((_) {
      nav.popUntil((route) => route.isFirst);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final homeCtx = nav.context;
        if (homeCtx.mounted) {
          AppNavigation.openOrders(homeCtx);
        }
      });
    });
  }

  Future<void> _onPlaceOrderPressed() async {
    // Guest: sign in only — do not place order until they tap PLACE ORDER again.
    if (FirebaseAuth.instance.currentUser == null) {
      final signedIn = await _showGuestSignInDialog();
      if (!signedIn || !mounted) return;
      await _reloadProfileAfterSignIn();
      return;
    }

    final phone = _phoneNumber.trim();

    if (_checkoutController.isDelivery) {
      final address = _displayAddress.trim();
      if (address == "Loading location..." ||
          address == "Fetching location...") {
        await _showOrderBlockedDialog('Please wait, loading location...');
        return;
      }
      if (address == "No Location Selected" || address.isEmpty) {
        await _showOrderBlockedDialog(
          'Please select delivery location on the map.',
          onOk: _openLocationPicker,
        );
        return;
      }
      if (!LocationService().hasDeliveryPin) {
        await _showOrderBlockedDialog(
          'Please confirm your pin on the map (required for delivery).',
          onOk: _openLocationPicker,
        );
        return;
      }
    }

    if (_checkoutController.isDineIn) {
      final tableNo = _tableNumberController.text.trim();
      if (tableNo.isEmpty) {
        await _showOrderBlockedDialog('Please enter table number.');
        return;
      }
    }

    if (_checkoutController.isPickup || _checkoutController.isDineIn) {
      if (!await NetworkHelper.hasConnectivity()) {
        if (!mounted) return;
        await NetworkHelper.showNoInternetDialog(
          context,
          message:
              'Internet is required to place a Pickup / Dine In order. Turn on internet and try again.',
          showRetryButton: true,
        );
        return;
      }
    }

    // Resolve / refresh branch for current order type
    if (_selectedBranch == null || _selectedBranch?.distanceKm == null) {
      final ok = await _ensureBranchAssignment(forceNearest: true);
      if (!ok || !mounted) {
        if (mounted) {
          await _showOrderBlockedDialog(
            _branchGateMessage ??
                'No suitable branch available for this order.',
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final branch = _selectedBranch;
    if (branch == null) {
      await _showOrderBlockedDialog(
        _branchGateMessage ??
            'No suitable branch available for this order.',
      );
      return;
    }

    final orderType = _checkoutController.selectedOrderType;
    if (!branch.supportsOrderType(orderType)) {
      await _showOrderBlockedDialog(
        'This branch does not support $orderType orders.',
      );
      return;
    }

    if (!branch.isOpenNow) {
      await _showOrderBlockedDialog(
        '${branch.name} is closed now'
        '${branch.openTime.isNotEmpty ? ' (opens ${branch.openTime})' : ''}.',
      );
      return;
    }

    // Delivery: calculated distance vs THIS branch's delivery_distance limit
    if (_checkoutController.isDelivery) {
      final dist = branch.distanceKm;
      if (dist == null) {
        await _showOrderBlockedDialog(
          'Could not calculate distance to the selected branch.',
        );
        return;
      }
      if (branch.deliveryDistanceKm > 0 && dist > branch.deliveryDistanceKm) {
        await _showOrderBlockedDialog(
          'Sorry, we do not deliver to your selected area. '
          'Please choose a closer location on the map, or place a Pickup order instead.',
        );
        return;
      }
    }

    // Phone required for Delivery / Pickup; optional for Dine In.
    if (!_checkoutController.isDineIn) {
      if (phone == "Loading phone...") {
        await _showOrderBlockedDialog('Please wait, loading phone number...');
        return;
      }
      if (!_hasValidCheckoutPhone()) {
        setState(() {
          _phoneFieldError = 'Enter proper number';
          _isEditingPhone = true;
          _phoneEditController.text = _localPhoneDigits(_phoneNumber);
        });
        return;
      }
      // Normalize stored value to +92XXXXXXXXXX
      final digits = _localPhoneDigits(_phoneNumber);
      _phoneNumber = _fullPhoneFromLocal(digits);
    }

    setState(() => _phoneFieldError = null);
    await _showSuccessDialog();
  }

  Future<void> _reloadProfileAfterSignIn() async {
    try {
      final profile = UserProfileController();
      profile.resetSession();
      await profile.ensureLoaded();
      if (!mounted) return;
      setState(() {
        _customerName = profile.userName;
        final p = profile.userPhone.trim();
        _phoneNumber =
            p.isNotEmpty ? _normalizePhoneDisplay(p) : 'No phone number added';
      });
    } catch (e) {
      debugPrint('Checkout: reload profile after sign-in failed: $e');
    }
  }

  Future<bool> _showGuestSignInDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 650),
          child: const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(24)),
            child: GoogleLoginScreen(),
          ),
        ),
      ),
    );
    return FirebaseAuth.instance.currentUser != null;
  }

  double _sectionTitleSize(BuildContext context) =>
      ResponsiveHelper.isWide(context) ? 17.5 : 15;

  double _bodyTextSize(BuildContext context) =>
      ResponsiveHelper.isWide(context) ? 15.5 : 13.5;

  Widget _buildCheckoutLeftColumn({
    required double titleSize,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Order Type",
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: _checkoutController,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        _buildOrderTypeTab(
                          type: 'Delivery',
                          label: 'Delivery',
                          icon: Icons.delivery_dining_rounded,
                        ),
                        _buildOrderTypeTab(
                          type: 'Pickup',
                          label: 'Pickup',
                          icon: Icons.storefront_rounded,
                        ),
                        _buildOrderTypeTab(
                          type: 'Dine In',
                          label: 'Dine In',
                          icon: Icons.restaurant_rounded,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_checkoutController.isPickup ||
                    _checkoutController.isDineIn)
                  _buildBranchSection(),

                if (_checkoutController.isDineIn) ...[
                  const SizedBox(height: 14),
                  Text(
                    "Table Number",
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _tableNumberController,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        hintText: "Enter table number",
                        hintStyle: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                      ),
                      style: TextStyle(fontSize: _bodyTextSize(context)),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                if (_checkoutController.selectedOrderType ==
                    'Delivery') ...[
                  Text(
                    "Deliver To",
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isEditingLocation
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _locationEditController,
                                autofocus: true,
                                keyboardType: TextInputType.multiline,
                                maxLines: null,
                                decoration: InputDecoration(
                                  hintText: "Enter your delivery address",
                                  hintStyle: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: AppColors.border,
                                    ),
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                style: TextStyle(
                                  fontSize: _bodyTextSize(context),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () => setState(
                                      () => _isEditingLocation = false,
                                    ),
                                    child: const Text(
                                      "Cancel",
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _saveEditedLocation,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text(
                                      "OK",
                                      style: TextStyle(
                                        color: AppColors.matteBlack,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : InkWell(
                            onTap: _openLocationPicker,
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2,
                                horizontal: 2,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    color: AppColors.primary,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _displayAddress,
                                          style: TextStyle(
                                            fontSize: ResponsiveHelper.isWide(
                                                    context)
                                                ? 16
                                                : 14,
                                            fontWeight: FontWeight.normal,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          LocationService().hasDeliveryPin
                                              ? 'Tap to change pin / address on map'
                                              : 'Tap to select location on map',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.map_outlined,
                                          color: AppColors.primary,
                                          size: 14,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          "MAP",
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),

                  const SizedBox(height: 20),
                  _buildBranchSection(),
                  const SizedBox(height: 20),
                ],
              ],
            );
          },
        ),

        if (FirebaseAuth.instance.currentUser != null) ...[
          Text(
            "Contact Phone Number",
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _isEditingPhone
                ? TextField(
                    controller: _phoneEditController,
                    autofocus: true,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onChanged: (value) {
                      if (_phoneFieldError != null) {
                        setState(() => _phoneFieldError = null);
                      }
                      if (_isValidLocalPhone(_localPhoneDigits(value))) {
                        _saveEditedPhone();
                      }
                    },
                    onSubmitted: (_) => _saveEditedPhone(),
                    decoration: InputDecoration(
                      hintText: "3XXXXXXXXX",
                      hintStyle: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.5,
                        height: 1.2,
                      ),
                      isDense: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: 1,
                          child: Text(
                            '+92',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.2,
                              fontWeight: FontWeight.normal,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                      errorText: _phoneFieldError,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppColors.border,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.2,
                      fontWeight: FontWeight.normal,
                      color: Colors.white,
                    ),
                  )
                : InkWell(
                    onTap: _startEditPhone,
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _phoneNumber,
                            style: TextStyle(
                              fontSize:
                                  ResponsiveHelper.isWide(context) ? 15 : 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "EDIT",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 20),
        ],

        if (_checkoutController.isDelivery) ...[
          Text(
            "Payment Method",
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.payments_outlined,
                    color: Colors.green.shade600,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  "Cash on Delivery",
                  style: TextStyle(
                    fontSize: ResponsiveHelper.isWide(context) ? 15 : 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildCheckoutRightColumn({
    required double titleSize,
    required double subtotal,
    required String taxLabel,
    required double total,
  }) {
    final billFont = ResponsiveHelper.isWide(context) ? 15.5 : 13.0;
    final totalFont = ResponsiveHelper.isWide(context) ? 16.5 : 14.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Bill Summary",
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListenableBuilder(
            listenable: _checkoutController,
            builder: (context, _) => Column(
              children: [
                _buildBillRow(
                  "Items Price",
                  "Rs ${subtotal.round()}",
                  fontSize: billFont,
                ),
                const SizedBox(height: 8),
                if (_discountAmount > 0) ...[
                  _buildBillRow(
                    "Discount",
                    "-Rs.${_discountAmount.round()}",
                    fontSize: billFont,
                  ),
                  const SizedBox(height: 8),
                ],
                if (_checkoutController.isDelivery) ...[
                  _buildBillRow(
                    "Delivery Fee",
                    "To be Calculated",
                    fontSize: billFont,
                  ),
                  const SizedBox(height: 8),
                ],
                if (_checkoutController.isDineIn) ...[
                  _buildBillRow(
                    "Service Charges",
                    "To be Calculated",
                    fontSize: billFont,
                  ),
                  const SizedBox(height: 8),
                ],
                _buildBillRow("Tax", taxLabel, fontSize: billFont),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Total",
                      style: TextStyle(
                        fontSize: totalFont,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "Rs ${total.round()}",
                      style: TextStyle(
                        fontSize: totalFont,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        ListenableBuilder(
          listenable: _checkoutController,
          builder: (context, _) {
            if (!_checkoutController.isDelivery) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  "Delivery Instructions",
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Any notes for the rider / delivery?",
                  style: TextStyle(
                    fontSize: ResponsiveHelper.isWide(context) ? 13 : 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _deliveryInstructionsController,
                    decoration: const InputDecoration(
                      hintText: "e.g. No doorbell, leave at gate...",
                      hintStyle: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                    ),
                    maxLines: 2,
                    style: TextStyle(fontSize: _bodyTextSize(context)),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = _getCartSubtotal();
    final taxAmount = _taxAmountFor(subtotal);
    final total = _billTotalFor(subtotal);
    final taxLabel = _branchTaxPercent <= 0
        ? 'Included'
        : 'Rs ${taxAmount.round()} (${_branchTaxPercent.toStringAsFixed(_branchTaxPercent % 1 == 0 ? 0 : 1)}%)';
    // Tablet should behave like mobile (one-column layout + bottom CTA),
    // only desktop uses the wide two-column layout.
    final isWide = ResponsiveHelper.isDesktop(context);
    final titleSize = _sectionTitleSize(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.matteBlack,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBackground,
        appBar: AppBar(
          backgroundColor: AppColors.matteBlack,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              Text(
                "Your Bucket",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Review & Place Order",
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
        bottomNavigationBar: isWide
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Align(
                    alignment: Alignment.center,
                    heightFactor: 1,
                    child: AppBottomActionButton(
                      label: 'PLACE ORDER',
                      width: ResponsiveHelper.isTablet(context)
                          ? 230
                          : AppBottomActionButton.preferredWidth(context),
                      onTap: _onPlaceOrderPressed,
                    ),
                  ),
                ),
              ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: isWide
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 500),
                              child: _buildCheckoutLeftColumn(
                                titleSize: titleSize,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: _buildCheckoutRightColumn(
                                  titleSize: titleSize,
                                  subtotal: subtotal,
                                  taxLabel: taxLabel,
                                  total: total,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
                              child: Center(
                                child: AppBottomActionButton(
                                  label: 'PLACE ORDER',
                                  width: 340,
                                  onTap: _onPlaceOrderPressed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCheckoutLeftColumn(titleSize: titleSize),
                      _buildCheckoutRightColumn(
                        titleSize: titleSize,
                        subtotal: subtotal,
                        taxLabel: taxLabel,
                        total: total,
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildOrderTypeTab({
    required String type,
    required String label,
    required IconData icon,
  }) {
    final selected = _checkoutController.selectedOrderType == type;
    final wide = ResponsiveHelper.isDesktop(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => _checkoutController.setOrderType(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: BoxConstraints(minHeight: wide ? 36 : 40),
          padding: EdgeInsets.symmetric(vertical: wide ? 6 : 8),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.flameGradient : null,
            color: selected ? null : AppColors.cardBackground,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: wide ? 16 : 15,
                color: selected ? AppColors.onPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: wide ? 13 : 12,
                    fontWeight: FontWeight.bold,
                    color: selected ? AppColors.onPrimary : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillRow(String label, String value, {double fontSize = 13}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: fontSize, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Self-dismissing success dialog — auto-closes when Lottie animation finishes
// ─────────────────────────────────────────────────────────────────────────────
class _SuccessDialog extends StatefulWidget {
  const _SuccessDialog();

  @override
  State<_SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<_SuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _lottieController;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
    // Listen for animation completion and auto-dismiss
    _lottieController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  void dispose() {
    _lottieController.dispose();
    super.dispose();
  }

  Widget _buildAnimation() {
    return Lottie.asset(
      'assets/success.lottie',
      controller: _lottieController,
      width: 260,
      height: 260,
      onLoaded: (composition) {
        // Set the duration from the composition and start playing
        _lottieController
          ..duration = composition.duration
          ..forward();
      },
      decoder: (bytes) {
        return LottieComposition.decodeZip(
          bytes,
          filePicker: (files) {
            return files.firstWhere(
              (f) =>
                  f.name.startsWith('animations/') && f.name.endsWith('.json'),
              orElse: () => files.first,
            );
          },
        );
      },
      errorBuilder: (ctx, error, stackTrace) {
        // Fallback: show icon and auto-dismiss after 2 seconds
        // Capture the navigator before the async gap to avoid lint warning
        final nav = Navigator.of(context);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) nav.pop();
        });
        return Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_rounded,
            size: 96,
            color: Colors.green.shade500,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.matteBlack,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAnimation(),
              const SizedBox(height: 20),
              const Text(
                "Order Placed Successfully!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Your order is being prepared.\nTrack it in My Orders.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
