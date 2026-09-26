import 'package:flutter/material.dart';
import '../models/food_model.dart';
import '../screens/ar_screen.dart';
import 'device_ar_capability.dart';
import 'web_ar_launch.dart';

String? resolveWebArModelUrl(List<FoodModel> models) {
  for (final model in models) {
    final src = model.modelSrc.trim();
    if (src.startsWith('http://') ||
        src.startsWith('https://') ||
        src.startsWith('data:')) {
      return src;
    }
    if (FoodModel.isGlbOrUsdzUrl(src) && !src.startsWith('file:')) {
      return src;
    }
  }
  for (final model in models) {
    final path = model.path.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
  }
  return null;
}

/// Web: Scene Viewer on supported phones, otherwise in-app 3D viewer.
Future<void> openVisidineAr(
  BuildContext context, {
  List<FoodModel> dealModels = const [],
  List<FoodModel> manualModels = const [],
  List<FoodModel> displayModels = const [],
}) async {
  final models = displayModels.isNotEmpty
      ? displayModels
      : [...dealModels, ...manualModels];

  if (!await deviceSupportsVisidineAr()) return;
  final src = resolveWebArModelUrl(models);
  if (src != null) {
    final title = models.isNotEmpty ? models.first.name : null;
    final launched = await tryLaunchWebArDirect(src, title: title);
    if (launched) return;
  }

  if (!context.mounted) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ARScreen(
        dealModels: dealModels,
        manualModels: manualModels,
        displayModels: displayModels,
      ),
    ),
  );
}
