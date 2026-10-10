// Reading settings, persisted in the kv table.

import 'package:arth/app/strings.dart';
import 'package:arth/data/card_reminders.dart';
import 'package:arth/data/local_store.dart';
import 'package:flutter/material.dart';

enum TooltipDetail { compact, detailed }

enum HindiSize { small, medium, large }

/// The typeface of a card's own words (the interface stays Montserrat).
/// Travels with what's shared: the PDF export, and published recaps.
enum CardFont { montserrat, quintessential, bricolage }

class Settings {
  const Settings({
    this.themeMode = ThemeMode.light,
    this.tooltipDetail = TooltipDetail.compact,
    this.hindiSize = HindiSize.medium,
    this.ttsEnabled = true,
    this.aiLookup = true,
    this.prefetch = true,
    this.haptics = true,
    this.language = UiLanguage.en,
    this.cardReminders = true,
    this.reminderHours = defaultReminderHours,
    this.cardFont = CardFont.montserrat,
    this.bookPages = true,
    this.usageStats = true,
  });

  final ThemeMode themeMode;
  final TooltipDetail tooltipDetail;
  final HindiSize hindiSize;
  final bool ttsEnabled;

  /// Ask the model while reading: a selected sentence is translated, and a
  /// rare word's sense is picked on tap. Off, a selection only highlights.
  final bool aiLookup;

  /// Resolve hard words on the current and next page in the background.
  final bool prefetch;



  /// Vibration feedback on taps (see app/feel.dart).
  final bool haptics;

  /// Interface language. Dictionary content is always Hindi.
  final UiLanguage language;


  /// Remind the reader to review new cards (see card_reminders.dart).
  final bool cardReminders;

  /// Hours after a card is made to remind, ascending.
  final List<int> reminderHours;

  final CardFont cardFont;

  /// Reading mode: books show a page at a time with a page-turn curl. Off,
  /// scrolling mode: a book scrolls like an ordinary PDF reader.
  final bool bookPages;

  /// Share anonymous usage stats (see data/analytics.dart).
  final bool usageStats;

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
    bool? aiLookup,
    bool? prefetch,
    bool? haptics,
    UiLanguage? language,
    bool? cardReminders,
    List<int>? reminderHours,
    CardFont? cardFont,
    bool? bookPages,
    bool? usageStats,
  }) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        tooltipDetail: tooltipDetail ?? this.tooltipDetail,
        hindiSize: hindiSize ?? this.hindiSize,
        ttsEnabled: ttsEnabled ?? this.ttsEnabled,
        aiLookup: aiLookup ?? this.aiLookup,
        prefetch: prefetch ?? this.prefetch,
        haptics: haptics ?? this.haptics,
        language: language ?? this.language,
        cardReminders: cardReminders ?? this.cardReminders,
        reminderHours: reminderHours ?? this.reminderHours,
        cardFont: cardFont ?? this.cardFont,
        bookPages: bookPages ?? this.bookPages,
        usageStats: usageStats ?? this.usageStats,
      );

  static Future<Settings> load(LocalStore store) async => Settings(
        themeMode: ThemeMode.values.byName(await store.get('theme') ?? 'light'),
        tooltipDetail: TooltipDetail.values.byName(
          await store.get('tooltip_detail') ?? 'compact',
        ),
        hindiSize: HindiSize.values.byName(await store.get('hindi_size') ?? 'medium'),
        ttsEnabled: (await store.get('tts') ?? 'true') == 'true',
        aiLookup: (await store.get('ai_lookup') ?? 'true') == 'true',
        prefetch: (await store.get('prefetch') ?? 'true') == 'true',
        haptics: (await store.get('haptics') ?? 'true') == 'true',
        language: UiLanguage.values.byName(await store.get('language') ?? 'en'),
        cardReminders: (await store.get('card_reminders') ?? 'true') == 'true',
        reminderHours: _hours(await store.get('reminder_hours')),
        cardFont: CardFont.values.asNameMap()[await store.get('card_font')] ?? CardFont.montserrat,
        bookPages: (await store.get('book_pages') ?? 'true') == 'true',
        usageStats: (await store.get('usage_stats') ?? 'true') == 'true',
      );

  static List<int> _hours(String? stored) {
    final hours = [for (final h in (stored ?? '').split(',')) ?int.tryParse(h)];
    return hours.isEmpty ? defaultReminderHours : (hours..sort());
  }

  Future<void> save(LocalStore store) async {
    await store.set('theme', themeMode.name);
    await store.set('tooltip_detail', tooltipDetail.name);
    await store.set('hindi_size', hindiSize.name);
    await store.set('tts', ttsEnabled.toString());
    await store.set('ai_lookup', aiLookup.toString());
    await store.set('prefetch', prefetch.toString());
    await store.set('haptics', haptics.toString());
    await store.set('language', language.name);
    await store.set('card_reminders', cardReminders.toString());
    await store.set('reminder_hours', reminderHours.join(','));
    await store.set('card_font', cardFont.name);
    await store.set('book_pages', bookPages.toString());
    await store.set('usage_stats', usageStats.toString());
  }
}
