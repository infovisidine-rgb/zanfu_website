import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../models/food_model.dart';
import '../utils/app_colors.dart';
import '../utils/visidine_ar_open.dart';

/// Web AR via Google Scene Viewer / WebXR / Quick Look (model-viewer).
/// Used as iOS / desktop fallback when direct Scene Viewer launch is not used.
class ARScreen extends StatefulWidget {
  final List<FoodModel> dealModels;
  final List<FoodModel> manualModels;
  final List<FoodModel> displayModels;

  const ARScreen({
    super.key,
    this.dealModels = const [],
    this.manualModels = const [],
    this.displayModels = const [],
  });

  @override
  State<ARScreen> createState() => _ARScreenState();
}

class _ARScreenState extends State<ARScreen> {
  static const _viewerId = 'visidine-web-ar-viewer';

  List<FoodModel> get _models {
    if (widget.displayModels.isNotEmpty) return widget.displayModels;
    return [...widget.dealModels, ...widget.manualModels];
  }

  String? get _src => resolveWebArModelUrl(_models);

  @override
  Widget build(BuildContext context) {
    final src = _src;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.matteBlack,
        // Minimal chrome — avoid a full "second page" feel while AR starts.
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.primary,
          title: const Text(''),
        ),
        body: src == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No 3D model available for AR on this item.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  // Viewer stays in DOM for activateAR / Quick Look.
                  Opacity(
                    opacity: 0.01,
                    child: ModelViewer(
                      id: _viewerId,
                      src: src,
                      alt: _models.isNotEmpty ? _models.first.name : 'Food',
                      ar: true,
                      arModes: const ['scene-viewer', 'webxr', 'quick-look'],
                      arScale: ArScale.auto,
                      arPlacement: ArPlacement.floor,
                      autoRotate: false,
                      cameraControls: false,
                      backgroundColor: Colors.transparent,
                      loading: Loading.eager,
                      relatedJs: '''
(function () {
  function tryActivate(mv) {
    if (!mv || typeof mv.activateAR !== 'function') return;
    try { mv.activateAR(); } catch (e) {}
  }
  function bind() {
    var mv = document.querySelector('#$_viewerId') ||
             document.querySelector('model-viewer');
    if (!mv) return false;
    if (mv.loaded) {
      tryActivate(mv);
    } else {
      mv.addEventListener('load', function () { tryActivate(mv); }, { once: true });
    }
    setTimeout(function () { tryActivate(mv); }, 300);
    setTimeout(function () { tryActivate(mv); }, 800);
    setTimeout(function () { tryActivate(mv); }, 1400);
    return true;
  }
  if (!bind()) {
    var n = 0;
    var t = setInterval(function () {
      n++;
      if (bind() || n > 20) clearInterval(t);
    }, 150);
  }
})();
''',
                    ),
                  ),
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.primary),
                        SizedBox(height: 16),
                        Text(
                          'Opening camera…',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
