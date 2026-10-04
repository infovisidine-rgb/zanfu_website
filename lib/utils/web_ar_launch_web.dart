import 'dart:html' as html;

/// On Android mobile Chrome, open Google Scene Viewer directly (camera AR)
/// without an intermediate Flutter "View by Visidine" page.
///
/// Returns true if navigation was started. iOS / desktop return false so the
/// caller can fall back to in-page [model-viewer].
Future<bool> tryLaunchWebArDirect(String modelHttpsUrl, {String? title}) async {
  final url = modelHttpsUrl.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return false;
  }

  final ua = html.window.navigator.userAgent.toLowerCase();
  final isAndroid = ua.contains('android');
  if (!isAndroid) return false;

  final params = <String, String>{
    'file': url,
    // Prefer AR immediately; falls back to 3D if ARCore unavailable.
    'mode': 'ar_preferred',
  };
  final t = title?.trim();
  if (t != null && t.isNotEmpty) {
    params['title'] = t;
  }

  final sceneViewer = Uri.https('arvr.google.com', '/scene-viewer/1.0', params);

  // Same-tab assign keeps this a user-gesture navigation (reliable for AR).
  html.window.location.assign(sceneViewer.toString());
  return true;
}
