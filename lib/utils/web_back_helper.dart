import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void safeBack(BuildContext context) {
  if (kIsWeb) {
    // Navigates back in the browser history natively
    html.window.history.back();
  } else {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }
}
