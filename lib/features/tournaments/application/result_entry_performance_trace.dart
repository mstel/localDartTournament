import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Adds named spans to Flutter DevTools while running a profile build.
///
/// These spans intentionally exclude player names and result values so a
/// performance capture can be shared without exposing match details.
abstract final class ResultEntryPerformanceTrace {
  static bool get _enabled => kProfileMode;

  static T measureSync<T>(String name, T Function() action) {
    if (!_enabled) return action();
    final task = developer.TimelineTask()..start('result_entry.$name');
    try {
      return action();
    } finally {
      task.finish();
    }
  }

  static Future<T> measureAsync<T>(
    String name,
    Future<T> Function() action,
  ) async {
    if (!_enabled) return await action();
    final task = developer.TimelineTask()..start('result_entry.$name');
    try {
      return await action();
    } finally {
      task.finish();
    }
  }

  static void trackNextFrame(String name) {
    if (!_enabled) return;
    final task = developer.TimelineTask()..start('result_entry.$name');
    WidgetsBinding.instance.addPostFrameCallback((_) => task.finish());
  }
}
