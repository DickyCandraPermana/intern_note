import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WidgetSyncService {
  static const String channelName = 'com.example.intern_noter/widget';
  static const MethodChannel _defaultChannel = MethodChannel(channelName);

  final MethodChannel _channel;

  const WidgetSyncService({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> updateWidget() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('updateWidget');
    } on MissingPluginException {
      // Safe no-op in tests or builds without the native Android channel.
    } on PlatformException {
      // Do not fail user mutations if launcher widget refresh fails.
    }
  }

  Future<String?> consumePendingRoute() async {
    if (!_isAndroid) return null;
    try {
      final result = await _channel.invokeMethod<dynamic>('consumePendingRoute');
      if (result is String && result.trim().isNotEmpty) {
        return result.trim();
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
