// Reading settings, persisted in the kv table.

import 'package:arth/data/local_store.dart';
import 'package:flutter/material.dart';

enum TooltipDetail { compact, detailed }

enum HindiSize { small, medium, large }

class Settings {
  const Settings({
    this.themeMode = ThemeMode.system,
    this.tooltipDetail = TooltipDetail.compact,
    this.hindiSize = HindiSize.medium,
    this.ttsEnabled = true,
    this.apiBaseUrl,
  });

  final ThemeMode themeMode;
  final TooltipDetail tooltipDetail;
  final HindiSize hindiSize;
  final bool ttsEnabled;

  /// Runtime override of the API base URL (Settings → सर्वर), for testing on a
  /// phone without rebuilding with --dart-define.
  final String? apiBaseUrl;

  double get hindiScale => switch (hindiSize) {
        HindiSize.small => 0.9,
        HindiSize.medium => 1.0,
        HindiSize.large => 1.15,
      };

  Settings copyWith({
    ThemeMode? themeMode,
    TooltipDetail? tooltipDetail,
    HindiSize? hindiSize,
    bool? ttsEnabled,
    String? Function()? apiBaseUrl,
  }) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        tooltipDetail: tooltipDetail ?? this.tooltipDetail,
        hindiSize: hindiSize ?? this.hindiSize,
        ttsEnabled: ttsEnabled ?? this.ttsEnabled,
        apiBaseUrl: apiBaseUrl == null ? this.apiBaseUrl : apiBaseUrl(),
      );

  static Future<Settings> load(LocalStore store) async => Settings(
        themeMode: ThemeMode.values.byName(await store.get('theme') ?? 'system'),
        tooltipDetail: TooltipDetail.values.byName(
          await store.get('tooltip_detail') ?? 'compact',
        ),
        hindiSize: HindiSize.values.byName(await store.get('hindi_size') ?? 'medium'),
        ttsEnabled: (await store.get('tts') ?? 'true') == 'true',
        apiBaseUrl: await store.get('api_base_url'),
      );

  Future<void> save(LocalStore store) async {
    await store.set('theme', themeMode.name);
    await store.set('tooltip_detail', tooltipDetail.name);
    await store.set('hindi_size', hindiSize.name);
    await store.set('tts', ttsEnabled.toString());
    await store.set('api_base_url', apiBaseUrl);
  }
}
