// flutter_tts wrapper. Checks voice availability once at startup so the UI can
// hide the speaker button where a language is missing instead of failing on tap.

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService() : _tts = FlutterTts();

  final FlutterTts _tts;
  String? _english;
  bool _hindi = false;
  bool _ready = false;

  bool get hasEnglish => _english != null;
  bool get hasHindi => _hindi;

  Future<void> init() async {
    if (_ready) return;
    try {
      final langs = ((await _tts.getLanguages) as List<dynamic>? ?? const [])
          .map((l) => l.toString())
          .toList();
      String? pick(List<String> wanted) {
        for (final w in wanted) {
          final hit = langs.firstWhere(
            (l) => l.toLowerCase() == w.toLowerCase(),
            orElse: () => '',
          );
          if (hit.isNotEmpty) return hit;
        }
        return null;
      }

      _english = pick(['en-GB', 'en-IN', 'en-US']) ??
          langs.cast<String?>().firstWhere(
                (l) => l!.toLowerCase().startsWith('en'),
                orElse: () => null,
              );
      _hindi = pick(['hi-IN', 'hi']) != null;
      await _tts.setSpeechRate(0.45);
    } on Exception {
      _english = null;
      _hindi = false;
    }
    _ready = true;
  }

  Future<void> speakEnglish(String text) async {
    if (_english == null) return;
    await _tts.stop();
    await _tts.setLanguage(_english!);
    await _tts.speak(text);
  }

  Future<void> speakHindi(String text) async {
    if (!_hindi) return;
    await _tts.stop();
    await _tts.setLanguage('hi-IN');
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
