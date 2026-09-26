import 'package:flutter/material.dart';
import '../data/food_data.dart';
import '../services/firestore_service.dart';
import '../utils/app_colors.dart';
import '../controllers/size_settings_controller.dart';
import 'package:flutter/services.dart';
import '../utils/device_ar_capability.dart';
import '../utils/visidine_ar_open.dart';

class SizeSettingsScreen extends StatefulWidget {
  const SizeSettingsScreen({super.key});

  @override
  State<SizeSettingsScreen> createState() => _SizeSettingsScreenState();
}

class _SizeSettingsScreenState extends State<SizeSettingsScreen> {
  final SizeSettingsController _controller = SizeSettingsController();
  bool _deviceSupportsAr = false;

  @override
  void initState() {
    super.initState();
    FirestoreService.syncAvailableModelsFromCatalog();
    deviceSupportsVisidineAr().then((ok) {
      if (!mounted) return;
      if (_deviceSupportsAr == ok) return;
      setState(() => _deviceSupportsAr = ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF37383D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF37383D),
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        leading: null,
        automaticallyImplyLeading: false,
        title: const Text(
          "Scale & Multi-Select Settings",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: foodDataVersion,
        builder: (context, _, __) {
          return ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final models = availableModels.isNotEmpty
                  ? availableModels
                  : FirestoreService.getAllCachedFoodModels();

              if (models.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No Firebase 3D models loaded yet.\nOpen the menu first, then come back.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: models.length,
                itemBuilder: (context, index) {
                  final model = models[index];
                  final isSelected = _controller.isSelected(model);
                  return GestureDetector(
                    onTap: () {
                      _controller.toggleSelection(model);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isSelected
                                  ? AppColors.primary.withOpacity(0.2)
                                  : Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primary
                                              .withOpacity(0.1)
                                          : Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.restaurant_rounded,
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.white54,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          model.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "Size: ${model.currentInches.toStringAsFixed(1)}\"",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: (val) {
                                      _controller.toggleSelection(model);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Divider(
                                      color: Colors.white10,
                                      height: 1,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          "Adjust Model Size (AR Scale)",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          "${model.currentInches.toStringAsFixed(1)}\"",
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor:
                                            AppColors.primary,
                                        inactiveTrackColor: Colors.white10,
                                        thumbColor: AppColors.primary,
                                        overlayColor: AppColors.primary
                                            .withOpacity(0.1),
                                        trackHeight: 3,
                                        thumbShape:
                                            const RoundSliderThumbShape(
                                          enabledThumbRadius: 8,
                                        ),
                                      ),
                                      child: Slider(
                                        value: model.currentInches,
                                        min: 2.0,
                                        max: 40.0,
                                        onChanged: (val) {
                                          _controller.updateModelSize(
                                            model,
                                            val,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return !_deviceSupportsAr || _controller.selectedModels.isEmpty
              ? const SizedBox.shrink()
              : Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: AppColors.flameGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      openVisidineAr(
                        context,
                        manualModels: _controller.selectedModels,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.view_in_ar, color: Colors.white),
                        const SizedBox(width: 12),
                        Text(
                          'VIEW IN 3D (${_controller.selectedModels.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
        },
      ),
    );
  }
}
