import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/custom_header.dart';
import '../utils/app_colors.dart';
import '../controllers/user_profile_controller.dart';

class ProfileScreen extends StatefulWidget {
  /// When true, shown as a right-side overlay panel (desktop/laptop).
  final bool asSidePanel;

  const ProfileScreen({super.key, this.asSidePanel = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserProfileController _profile = UserProfileController();
  bool _isLoading = true;

  String? _editingKey; // 'name' | 'phone'
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final FocusNode _nameFocus;
  late final FocusNode _phoneFocus;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _nameFocus = FocusNode();
    _phoneFocus = FocusNode();
    _profile.addListener(_onProfileChanged);
    _load();
  }

  void _onProfileChanged() {
    if (!mounted) return;
    if (_editingKey == null) {
      _syncControllersFromProfile();
    }
    setState(() {});
  }

  void _syncControllersFromProfile() {
    _nameCtrl.text = _profile.userName;
    var phone = _profile.userPhone;
    if (phone.startsWith('+92')) {
      phone = phone.substring(3).trim();
    } else if (phone.startsWith('0')) {
      phone = phone.substring(1).trim();
    }
    _phoneCtrl.text = phone;
  }

  Future<void> _load() async {
    await _profile.ensureLoaded();
    if (!mounted) return;
    _syncControllersFromProfile();
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _profile.removeListener(_onProfileChanged);
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _startEdit(String key) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (key == 'email') return;

    _syncControllersFromProfile();
    setState(() => _editingKey = key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (key == 'name') {
        _nameFocus.requestFocus();
      } else if (key == 'phone') {
        _phoneFocus.requestFocus();
      }
    });
  }

  Future<void> _saveEdit() async {
    final key = _editingKey;
    if (key == null) return;

    try {
      if (key == 'name') {
        final val = _nameCtrl.text.trim();
        if (val.isEmpty) {
          _showError('Name cannot be empty');
          return;
        }
        await _profile.updateProfile(name: val);
      } else if (key == 'phone') {
        var val = _phoneCtrl.text.trim();
        if (val.length < 9) {
          _showError('Enter a valid phone number');
          return;
        }
        if (val.startsWith('0')) val = val.substring(1);
        if (val.startsWith('+92')) val = val.substring(3);
        val = '+92$val';
        await _profile.updateProfile(phone: val);
      }
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _editingKey = null);
      _syncControllersFromProfile();
    } catch (e) {
      debugPrint('Profile update error: $e');
      _showError('Could not update: $e');
    }
  }

  void _cancelEdit() {
    FocusManager.instance.primaryFocus?.unfocus();
    _syncControllersFromProfile();
    setState(() => _editingKey = null);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile.userName;
    final phone = _profile.userPhone;
    final email = _profile.userEmail;

    return GestureDetector(
      onTap: () {
        if (_editingKey != null) _cancelEdit();
      },
      behavior: HitTestBehavior.deferToChild,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBackground,
        appBar: CustomHeader(
          title: "Profile",
          showBackButton: true,
          subtitle: "",
          showCartIcon: false,
          onBackTap: widget.asSidePanel
              ? () => Navigator.of(context).maybePop()
              : null,
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            : SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    _fieldCard(
                      label: 'NAME',
                      icon: Icons.person_outline,
                      displayValue: name,
                      editable: true,
                      isEditing: _editingKey == 'name',
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      onEdit: () => _startEdit('name'),
                      onSave: _saveEdit,
                      onCancel: _cancelEdit,
                    ),
                    const SizedBox(height: 14),
                    _fieldCard(
                      label: 'EMAIL',
                      icon: Icons.email_outlined,
                      displayValue: email,
                      editable: false,
                    ),
                    const SizedBox(height: 14),
                    _fieldCard(
                      label: 'MOBILE NUMBER',
                      icon: Icons.phone_outlined,
                      displayValue: phone,
                      editable: true,
                      isEditing: _editingKey == 'phone',
                      controller: _phoneCtrl,
                      focusNode: _phoneFocus,
                      keyboardType: TextInputType.phone,
                      prefixText: '+92 ',
                      onEdit: () => _startEdit('phone'),
                      onSave: _saveEdit,
                      onCancel: _cancelEdit,
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _fieldCard({
    required String label,
    required IconData icon,
    required String displayValue,
    required bool editable,
    bool isEditing = false,
    TextEditingController? controller,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    String? prefixText,
    VoidCallback? onEdit,
    VoidCallback? onSave,
    VoidCallback? onCancel,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEditing ? AppColors.primary : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                if (isEditing && controller != null && focusNode != null)
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    keyboardType: keyboardType ?? TextInputType.text,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onSave?.call(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixText: prefixText,
                      prefixStyle: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                else
                  Text(
                    displayValue.isEmpty ? '----' : displayValue,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          if (editable) ...[
            const SizedBox(width: 8),
            if (isEditing) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onCancel,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: Colors.white70),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSave,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.check, size: 18, color: AppColors.primary),
                ),
              ),
            ] else
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onEdit,
                child: const Padding(
                  padding: EdgeInsets.only(top: 2.0),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
