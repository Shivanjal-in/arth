// Debug-only VM-service extensions so the reader can be driven from a script
// on a simulator (which has no tap automation): navigate, tap a word by text,
// fake a selection. Compiled out of release builds by kDebugMode.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

typedef DevHandler = Future<Map<String, Object?>> Function(Map<String, String> params);

class DevHooks {
  DevHooks._();

  static final Map<String, DevHandler> _handlers = {};
  static bool _registered = false;

  /// Registers `ext.arth.<name>`; later registrations replace earlier ones
  /// (e.g. each ReaderScreen instance re-registers `tapWord`).
  static void on(String name, DevHandler handler) {
    if (!kDebugMode) return;
    _handlers[name] = handler;
    if (_registered) return;
    _registered = true;
    for (final n in ['nav', 'tapWord', 'select', 'dismiss', 'state', 'scan']) {
      dev.registerExtension('ext.arth.$n', (method, params) async {
        final h = _handlers[n];
        if (h == null) {
          return dev.ServiceExtensionResponse.error(
            dev.ServiceExtensionResponse.extensionError,
            'no handler for $n',
          );
        }
        try {
          return dev.ServiceExtensionResponse.result(jsonEncode(await h(params)));
        } on Object catch (e, st) {
          return dev.ServiceExtensionResponse.error(
            dev.ServiceExtensionResponse.extensionError,
            '$e\n$st',
          );
        }
      });
    }
  }

  static void off(String name) => _handlers.remove(name);
}
