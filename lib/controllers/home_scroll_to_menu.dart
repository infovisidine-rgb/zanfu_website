import 'package:flutter/foundation.dart';

/// Home listens; cart Explore Menu calls [request] after closing the cart.
class HomeScrollToMenu {
  HomeScrollToMenu._();
  static final HomeScrollToMenu instance = HomeScrollToMenu._();

  final ObserverList<VoidCallback> _listeners = ObserverList<VoidCallback>();

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void request() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      listener();
    }
  }
}
