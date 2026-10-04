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
          foregroundColor: Colors.white,
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
            : Column(
                children: [
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Tap the Visidine button in the corner to open camera.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ModelViewer(
                      id: _viewerId,
                      src: src,
                      alt: _models.isNotEmpty ? _models.first.name : 'Food',
                      ar: true,
                      arModes: const ['scene-viewer', 'webxr', 'quick-look'],
                      arScale: ArScale.auto,
                      arPlacement: ArPlacement.floor,
                      autoRotate: true,
                      cameraControls: true,
                      minCameraOrbit: 'auto 0deg auto',
                      maxCameraOrbit: 'auto 90deg auto',
                      backgroundColor: Colors.transparent,
                      loading: Loading.eager,
                      innerModelViewerHtml: '''
                        <button slot="ar-button" id="ar-button">
                          <img src="assets/assets/visidine_logo.png" onerror="this.onerror=null; this.src='assets/visidine_logo.png';" style="width: 24px; height: 24px; object-fit: contain;">
                        </button>
                      ''',
                      relatedCss: '''
                        #ar-button {
                          background-color: #1c1c1e;
                          border-radius: 50%;
                          border: none;
                          position: absolute;
                          bottom: 24px;
                          right: 24px;
                          width: 48px;
                          height: 48px;
                          display: flex;
                          align-items: center;
                          justify-content: center;
                          box-shadow: 0 4px 12px rgba(0,0,0,0.5);
                          cursor: pointer;
                        }
                        #ar-button:active {
                          opacity: 0.8;
                        }
                      ''',
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }
}
