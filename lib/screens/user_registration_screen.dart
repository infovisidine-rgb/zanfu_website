import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_colors.dart';
import '../utils/network_helper.dart';
import '../services/location_service.dart';
import '../controllers/user_profile_controller.dart';
import '../widgets/touch_scale_effect.dart';
import 'menu_screen.dart';

class UserRegistrationScreen extends StatefulWidget {
  final String uid;
  final String email;
  final String displayName;

  const UserRegistrationScreen({
    Key? key,
    required this.uid,
    required this.email,
    required this.displayName,
  }) : super(key: key);

  @override
  State<UserRegistrationScreen> createState() => _UserRegistrationScreenState();
}

class _UserRegistrationScreenState extends State<UserRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  final TextEditingController _phoneController = TextEditingController();
  bool _isSaving = false;
  String _fetchedAddress = "Adyala Islamabad";

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.displayName);
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      await LocationService().initLocation();
      if (LocationService().currentAddress != null && LocationService().currentAddress!.isNotEmpty) {
        if (mounted) {
          setState(() {
            _fetchedAddress = LocationService().currentAddress!;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching location during registration: $e");
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveUserData() async {
    if (!_formKey.currentState!.validate()) return;

    if (!await NetworkHelper.hasConnectivity()) {
      if (mounted) {
        NetworkHelper.showNoInternetDialog(
          context,
          message:
              'No internet connection. Please turn on internet to save your details.',
        );
      }
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      String phoneVal = _phoneController.text.trim();
      if (phoneVal.startsWith('0')) {
        phoneVal = phoneVal.substring(1);
      }
      if (phoneVal.startsWith('+92')) {
        phoneVal = phoneVal.substring(3);
      }
      phoneVal = '+92$phoneVal';

      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'uid': widget.uid,
        'name': _nameController.text.trim(),
        'email': widget.email,
        'phone': phoneVal,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await UserProfileController().saveAfterRegistration(
        uid: widget.uid,
        name: _nameController.text.trim(),
        email: widget.email,
        phone: phoneVal,
        address: '',
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MenuScreen()),
        );
      }
    } catch (e) {
      debugPrint("Error saving user details: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving details: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.matteBlack,
      appBar: AppBar(
        title: const Text(
          "Complete Profile",
          style: TextStyle(color: AppColors.matteBlack, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.matteBlack,
        elevation: 0.5,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Form(
                        key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 20),
                          const Text(
                            "Tell us a bit about yourself",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "We need your phone number and delivery location to complete your orders.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Name input field
                          const Text(
                            "FULL NAME",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameController,
                            keyboardType: TextInputType.name,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Please enter your name";
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                              hintText: "Enter your full name",
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Phone input field
                          const Text(
                            "PHONE NUMBER",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Focus(
                            child: Builder(
                              builder: (context) {
                                final isFocused = Focus.of(context).hasFocus;
                                return Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isFocused
                                          ? AppColors.primary
                                          : AppColors.border,
                                      width: isFocused ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(color: AppColors.border),
                                          ),
                                        ),
                                        child: const Text(
                                          "+92",
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _phoneController,
                                          keyboardType: TextInputType.phone,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          validator: (value) {
                                            if (value == null || value.trim().isEmpty) {
                                              return "Please enter your phone number";
                                            }
                                            if (value.trim().length < 9) {
                                              return "Please enter a valid phone number";
                                            }
                                            return null;
                                          },
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                          const Spacer(),
                          const SizedBox(height: 24),

                          // Save button
                          if (_isSaving)
                            const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                              ),
                            )
                          else
                            TouchScaleEffect(
                              onTap: _saveUserData,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  gradient: AppColors.flameGradient,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  "Save and Continue",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.matteBlack,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
    );
  }
}
