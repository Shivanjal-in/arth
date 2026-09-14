// flutter_tts wrapper.
//
// On iOS the synthesizer follows the ringer switch unless the audio session is
// the "playback" category, so a phone on silent produced nothing — the most
// common reason "TTS doesn't work". Voices are checked once at startup so the
// speaker button can be hidden where a language truly is missing, but a
// language the platform reports in any spelling (en_US, en-US) still counts.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService() : _tts = FlutterTts();

  final FlutterTts _tts;
  String? _english;
  String? _hindi;
  bool _ready = false;

  bool get hasEnglish => _english != null;
  bool get hasHindi => _hindi != null;

  Future<void> init() async {
    if (_ready) return;
    try {
      if (Platform.isIOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
        );
      }
      final langs = ((await _tts.getLanguages) as List<dynamic>? ?? const [])
          .map((l) => l.toString())
          .toList();
      String norm(String s) => s.toLowerCase().replaceAll('_', '-');
      String? pick(List<String> wanted, String prefix) {
        for (final w in wanted) {
          for (final l in langs) {
            if (norm(l) == norm(w)) return l;
          }
        }
        for (final l in langs) {
          if (norm(l).startsWith(prefix)) return l;
        }
        return null;
      }

      _english = pick(['en-IN', 'en-GB', 'en-US'], 'en');
      _hindi = pick(['hi-IN'], 'hi');
      // iOS ships Lekha (hi-IN) and several English voices; if the list came
      // back empty (some builds return [] until first use), assume both.
      if (langs.isEmpty && Platform.isIOS) {
        _english = 'en-US';
        _hindi = 'hi-IN';
      }
      await _tts.setSpeechRate(Platform.isIOS ? 0.48 : 0.45);
      await _tts.setVolume(1);
      await _tts.setPitch(1);
    } on Exception catch (e) {
      debugPrint('tts init failed: $e');
    }
    _ready = true;
  }

  Future<void> speakEnglish(String text) => _speak(_english ?? 'en-US', text);

  Future<void> speakHindi(String text) => _speak(_hindi ?? 'hi-IN', text);

  Future<void> _speak(String language, String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setLanguage(language);
      await _tts.speak(text);
    } on Exception catch (e) {
      debugPrint('tts speak failed: $e');
    }
  }

  Future<void> stop() => _tts.stop();
}
