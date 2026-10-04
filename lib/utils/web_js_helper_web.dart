// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop_unsafe';
import 'dart:async';

void registerJsCallback(String name, Function callback) {
  final parts = name.split('_');
  if (parts.length < 2) return;
  final viewerId = 'viewer_${parts[1]}';

  Timer? timer;
  int attempts = 0;

  void notify() {
    timer?.cancel();
    callback();
  }

  timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
    attempts++;
    
    // Evaluate a JS snippet that traverses the main DOM and all Shadow DOMs
    final evalFunc = globalContext.getProperty('eval'.toJS) as JSFunction;
    final jsCode = '''
      (function(id) {
        function traverse(root) {
          if (root.getElementById && root.getElementById(id)) return root.getElementById(id);
          if (root.querySelectorAll) {
            for (let el of root.querySelectorAll('*')) {
              if (el.shadowRoot) {
                let found = traverse(el.shadowRoot);
                if (found) return found;
              }
            }
          }
          return null;
        }
        return traverse(document);
      })('$viewerId')
    ''';
    
    final viewer = evalFunc.callAsFunction(globalContext, jsCode.toJS) as JSObject?;

    if (viewer != null) {
      t.cancel();
      
      // Check if already visible
      final isVisible = viewer.getProperty('modelIsVisible'.toJS);
      if (isVisible != null && (isVisible.dartify() == true || isVisible.dartify() == 'true')) {
        notify();
        return;
      }
      
      // Listen to events natively
      final jsNotify = notify.toJS;
      viewer.callMethod('addEventListener'.toJS, 'model-visibility'.toJS, jsNotify);
      viewer.callMethod('addEventListener'.toJS, 'load'.toJS, jsNotify);
      viewer.callMethod('addEventListener'.toJS, 'error'.toJS, jsNotify);
      
      // Fallback
      Future.delayed(const Duration(seconds: 3), notify);
    } else if (attempts > 50) {
      t.cancel();
      notify();
    }
  });
}
