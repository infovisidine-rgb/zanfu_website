import 'package:flutter/foundation.dart';

class CheckoutController extends ChangeNotifier {
  String _selectedOrderType = 'Delivery';

  String get selectedOrderType => _selectedOrderType;
  bool get isDelivery => _selectedOrderType == 'Delivery';
  bool get isPickup => _selectedOrderType == 'Pickup';
  bool get isDineIn => _selectedOrderType == 'Dine In';

  void setOrderType(String type) {
    if (_selectedOrderType == type) return;
    _selectedOrderType = type;
    notifyListeners();
  }
}
