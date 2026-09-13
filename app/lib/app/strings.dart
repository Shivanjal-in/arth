// Interface strings. The dictionary content is always Hindi; this is the
// chrome around it. English is the default; Settings switches to Hindi.

enum UiLanguage { en, hi }

enum AppStrings {
  en(UiLanguage.en),
  hi(UiLanguage.hi);

  const AppStrings(this.lang);

  final UiLanguage lang;

  static AppStrings of(UiLanguage l) => l == UiLanguage.hi ? hi : en;

  bool get isHindi => lang == UiLanguage.hi;

  String _(String en, String hi) => isHindi ? hi : en;

  // ---- tabs & titles ----
  String get tabLibrary => _('Library', 'किताबें');
  String get tabDictionary => _('Dictionary', 'शब्दकोश');
  String get tabSaved => _('Saved', 'सहेजे');
  String get tabYou => _('You', 'आप');
  String get back => _('Back', 'पीछे');
  String get about => _('About Arth', 'Arth के बारे में');

  // ---- library ----
  String get libraryEmptyTitle => _('No books yet', 'अभी कोई किताब नहीं है');
  String get libraryEmptyBody => _(
        'Tap + to add an English PDF. While reading, tap any word for its Hindi meaning.',
        'नीचे + दबाकर कोई अंग्रेज़ी PDF जोड़ें। पढ़ते हुए किसी भी शब्द पर टैप करें।',
      );
  String get notStarted => _('Not started', 'अभी शुरू नहीं किया');
  String page(int n, int total) => _('Page $n of $total', 'पृष्ठ $n / $total');
  String get removeBook => _('Remove this book?', 'किताब हटाएँ?');
  String get no => _('No', 'नहीं');
  String get remove => _('Remove', 'हटाएँ');
  String get importFailed => _('Could not import that file.', 'यह फ़ाइल जोड़ी नहीं जा सकी।');

  // ---- reader ----
  String get readingSettings => _('Reading settings', 'पढ़ने की सेटिंग');
  String get noTextLayer => _(
        "This PDF has no selectable text (probably a scan), so words can't be looked up.",
        'इस PDF में चुनने लायक टेक्स्ट नहीं है (शायद स्कैन है), इसलिए शब्द नहीं देखे जा सकते।',
      );
  String get pdfOpenFailed => _(
        "This PDF couldn't be opened. The file may have been removed — add the book again.",
        'यह PDF खोली नहीं जा सकी। फ़ाइल हट गई हो सकती है — किताब को दोबारा जोड़ें।',
      );

  // ---- tooltip / entry ----
  String get inThisSentence => _('In this sentence', 'इस वाक्य में');
  String get translation => _('Translation', 'अनुवाद');
  String get simpleMeaning => _('In plain words', 'भावार्थ');
  String get difficultWords => _('Difficult words', 'कठिन शब्द');
  String get seeFullEntry => _('See full entry  ›', 'पूरा अर्थ देखें  ›');
  String moreSenses(int n) => _('+$n more', '+$n और अर्थ');
  String get phrase => _('Phrase', 'मुहावरा');
  String get meanings => _('Meanings', 'अर्थ');
  String get synonyms => _('Synonyms', 'समानार्थी');
  String get antonyms => _('Antonyms', 'विलोम');
  String get forms => _('Forms', 'रूप');
  String get listen => _('Listen', 'सुनें');
  String get save => _('Save', 'सहेजें');
  String get unsave => _('Remove', 'हटाएँ');
  String get didYouMean => _('Did you mean', 'क्या आपका मतलब था');
  String get attribution => _('Based on Wiktionary (CC BY-SA)', 'Wiktionary (CC BY-SA) के आधार पर');

  // ---- dictionary ----
  String get dictionaryTitle => _('Dictionary', 'शब्दकोश');
  String get searchHint => _('Any English word', 'कोई अंग्रेज़ी शब्द');
  String get recent => _('Recent', 'हाल के');
  String get wordOfTheDay => _('Word of the day', 'आज का शब्द');
  String get notOnDevice => _(
        'Not on this phone — press search to look it up online',
        'फ़ोन पर नहीं मिला — सर्च दबाकर ऑनलाइन देखें',
      );

  // ---- saved ----
  String get savedTitle => _('Saved words', 'सहेजे शब्द');
  String get savedEmpty => _(
        'Tap 🔖 next to a word to save it here.',
        'किसी शब्द के पास 🔖 दबाकर उसे यहाँ सहेजें।',
      );

  // ---- settings ----
  String get settingsTitle => _('You', 'आप');
  String get sectionReading => _('Reading', 'पढ़ना');
  String get sectionDictionary => _('Dictionary', 'शब्दकोश');
  String get sectionServer => _('Server', 'सर्वर');
  String get sectionInfo => _('Info', 'जानकारी');
  String get language => _('Interface language', 'इंटरफ़ेस की भाषा');
  String get theme => _('Appearance', 'रूप');
  String get themePaper => _('Light', 'हल्का');
  String get themeNight => _('Dark', 'गहरा');
  String get themeSystem => _('Phone', 'फ़ोन');
  String get languageSampleEn => 'Library, Dictionary, Saved';
  String get languageSampleHi => 'किताबें, शब्दकोश, सहेजे';
  String get hindiSizeSample => 'मतलब, आशय — जैसे इस वाक्य में';
  String get settingsIntro => _(
        'How Arth reads with you.',
        'Arth आपके साथ कैसे पढ़े।',
      );
  String get serverTitle => _('API server', 'API सर्वर');
  String get tooltipDetail => _('Tooltip', 'टूलटिप');
  String get tooltipCompact => _('Compact', 'छोटा');
  String get tooltipDetailed => _('Detailed', 'विस्तार से');
  String get hindiSize => _('Hindi text size', 'हिंदी का आकार');
  String get tts => _('Pronunciation (TTS)', 'उच्चारण सुनें (TTS)');
  String get prefetch => _('Prefetch meanings while reading', 'पढ़ते समय अर्थ पहले से लाएँ');
  String get prefetchHelp => _(
        'Resolves hard words on the next page in the background. Uses data.',
        'अगले पन्ने के कठिन शब्द पहले से तैयार रखता है। डेटा खर्च होता है।',
      );
  String wordsOnDevice(int n) => _(
        '${_group(n)} words on this phone, ready offline.',
        'फ़ोन पर ${_group(n)} शब्द, बिना इंटरनेट भी तैयार।',
      );

  static String _group(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
  String get updateDictionary => _('Update dictionary', 'शब्दकोश अपडेट करें');
  String get serverHelp => _(
        'Leave empty to use the build default',
        'खाली छोड़ें तो बिल्ड का डिफ़ॉल्ट इस्तेमाल होगा',
      );

  // ---- seed ----
  String get seedTitle => _('Preparing the dictionary', 'शब्दकोश तैयार हो रहा है');
  String get seedBody => _(
        'Once downloaded, common words work without internet.',
        'एक बार डाउनलोड होने के बाद आम शब्द बिना इंटरनेट भी मिलेंगे।',
      );
  String get connecting => _('Connecting…', 'जुड़ रहा है…');
  String get retry => _('Try again', 'फिर कोशिश करें');
  String get skipForNow => _('Skip for now', 'अभी छोड़ें');
  String get downloadFailed => _('Download failed.', 'डाउनलोड नहीं हो पाया।');

  // ---- errors (client-side codes; server messages are Hindi) ----
  String get offline => _(
        'Internet needed for more meanings',
        'और अर्थ देखने के लिए इंटरनेट चाहिए',
      );
  String get notFound => _('Not in the dictionary.', 'यह शब्द शब्दकोश में नहीं मिला।');
  String get rateLimited => _(
        'Too many requests. Wait a minute and try again.',
        'बहुत जल्दी-जल्दी अनुरोध हो रहे हैं। एक मिनट रुककर फिर कोशिश करें।',
      );
  String get somethingWrong => _('Something went wrong.', 'कुछ गड़बड़ हो गई।');
  String get translationFailed => _("Couldn't translate.", 'अनुवाद नहीं हो पाया।');

  /// Localized message for an API failure code; falls back to the server's
  /// (Hindi) message for codes we don't know.
  String errorFor(String code, String serverMessage) => switch (code) {
        'OFFLINE' => offline,
        'NOT_FOUND' => notFound,
        'RATE_LIMITED' => rateLimited,
        'INTERNAL' || 'UPSTREAM_FAILED' => isHindi ? serverMessage : somethingWrong,
        _ => serverMessage,
      };

  // ---- about ----
  String get aboutTagline => _(
        'Read English books and tap any word — its meaning, in this sentence, in plain Hindi.',
        'अंग्रेज़ी किताबें पढ़ते हुए किसी भी शब्द पर टैप करें — उसका मतलब, इसी वाक्य में, आसान हिंदी में।',
      );
}
