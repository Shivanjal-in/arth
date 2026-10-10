// Interface strings. The dictionary content is always Hindi; this is the
// chrome around it. English is the default; Settings switches to Hindi.

enum UiLanguage { en, hi }

/// Card kinds by name, so strings needn't import the data layer.
enum CardKindName { idea, quote, word }

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
  String get tabYou => _('You', 'आप');
  String get back => _('Back', 'पीछे');
  String get about => _('About Arth', 'Arth के बारे में');

  // ---- library ----
  String get libraryEmptyTitle => _('No books yet', 'अभी कोई किताब नहीं है');
  String get libraryEmptyBody => _(
        'Tap + to add an English book: PDF, EPUB, TXT, Word, ODT, FB2, RTF or HTML. While reading, tap any word for its Hindi meaning.',
        'नीचे + दबाकर कोई अंग्रेज़ी किताब जोड़ें: PDF, EPUB, TXT, Word, ODT, FB2, RTF या HTML। पढ़ते हुए किसी भी शब्द पर टैप करें।',
      );
  String get notStarted => _('Not started', 'अभी शुरू नहीं किया');
  String page(int n, int total) => _('Page $n of $total', 'पृष्ठ $n / $total');
  String get goToPage => _('Go to page', 'पृष्ठ पर जाएँ');
  String get go => _('Go', 'जाएँ');
  String pageRange(int total) => _('1 to $total', '1 से $total तक');
  String pageLabel(int n) => _('Page $n', 'पृष्ठ $n');
  String get removeBook => _('Remove this book?', 'किताब हटाएँ?');
  String get no => _('No', 'नहीं');
  String get remove => _('Remove', 'हटाएँ');
  String get category => _('Category', 'श्रेणी');
  String get fiction => _('Fiction', 'कथा');
  String get nonfiction => _('Nonfiction', 'गैर-कथा');
  String get noCategory => _('No category', 'कोई श्रेणी नहीं');
  String get allCategories => _('All', 'सभी');
  String get archive => _('Archive', 'संग्रह');
  String get moveToArchive => _('Move to archive', 'संग्रह में भेजें');
  String get movedToArchive => _('Moved to archive', 'संग्रह में भेज दिया');
  String get putBack => _('Put back on the shelf', 'शेल्फ पर वापस लाएँ');
  String get archiveEmptyTitle => _('Nothing in the archive', 'संग्रह खाली है');
  String get archiveEmptyBody => _(
        'Books you move here leave the shelf. Open one, or put it back.',
        'जो किताबें आप यहाँ भेजेंगे, वे शेल्फ से हट जाएँगी। खोलें, या वापस लाएँ।',
      );
  String get shelfClearTitle => _('The shelf is clear', 'शेल्फ खाली है');
  String get shelfClearBody => _(
        'Your books are in the archive. Open it from the top.',
        'आपकी किताबें संग्रह में हैं। ऊपर से खोलें।',
      );
  String get importFailed => _('Could not import that file.', 'यह फ़ाइल जोड़ी नहीं जा सकी।');
  String get unsupportedFile => _(
        'Arth reads PDF, EPUB, TXT, Word (.docx), ODT, FB2, RTF and HTML files.',
        'अर्थ PDF, EPUB, TXT, Word (.docx), ODT, FB2, RTF और HTML फ़ाइलें पढ़ता है।',
      );

  // ---- scans ----
  String get addPdf => _('Add a book or document', 'किताब या दस्तावेज़ जोड़ें');
  String get takePhoto => _('Take a photo of a page', 'पन्ने की फ़ोटो लें');
  String get chooseFromGallery => _('Choose a photo from gallery', 'गैलरी से फ़ोटो चुनें');
  String get addPage => _('Add a page', 'पन्ना जोड़ें');
  String get scanTitle => _('Scanned pages', 'स्कैन किए पन्ने');
  String get scanEmpty => _('No pages yet. Add a photo of a page.', 'अभी कोई पन्ना नहीं। पन्ने की फ़ोटो जोड़ें।');
  String get ocrFailed => _("Couldn't read this photo.", 'यह फ़ोटो पढ़ी नहीं जा सकी।');
  String get ocrEmpty => _(
        'No text found in this photo. Try better light, a flatter page, or a closer shot.',
        'इस फ़ोटो में टेक्स्ट नहीं मिला। बेहतर रोशनी, सीधा पन्ना या पास से फ़ोटो लें।',
      );
  String get pages => _('pages', 'पन्ने');

  // ---- reader ----
  String get readingSettings => _('Reading settings', 'पढ़ने की सेटिंग');
  String get noTextLayer => _(
        'This PDF is scanned images, not text, so words can’t be tapped. A text-based PDF of the same book will work.',
        'यह PDF स्कैन की हुई तस्वीरें हैं, टेक्स्ट नहीं — इसलिए शब्दों पर टैप नहीं हो सकता। इसी किताब की टेक्स्ट वाली PDF काम करेगी।',
      );
  String get noTextOnPage => _(
        'No selectable text on this page (it’s an image). Other pages work as usual.',
        'इस पन्ने पर चुनने लायक टेक्स्ट नहीं है (यह तस्वीर है)। बाकी पन्ने ठीक चलेंगे।',
      );
  String get dismiss => _('OK', 'ठीक है');
  // ---- highlights ----
  String get highlight => _('Highlight', 'हाइलाइट');
  String get highlights => _('Highlights', 'हाइलाइट');
  String get removeHighlight => _('Remove highlight', 'हाइलाइट हटाएँ');
  String get highlightsEmpty => _(
        'No highlights yet. Press and hold a word and drag to highlight.',
        'अभी कोई हाइलाइट नहीं। किसी शब्द को दबाकर रखें और खींचें।',
      );
  String get highlightsEmptyPdf => _(
        'No highlights yet. Select some text, then pick a colour.',
        'अभी कोई हाइलाइट नहीं। कुछ टेक्स्ट चुनें, फिर रंग चुनें।',
      );

  // ---- epub ----
  String get contents => _('Contents', 'विषय-सूची');
  String section(int n) => _('Section $n', 'भाग $n');
  String chapter(int n, int total) => _('Chapter $n of $total', 'अध्याय $n / $total');
  String get epubOpenFailed => _(
        "This book couldn't be opened. The file may be damaged or removed — add the book again.",
        'यह किताब खोली नहीं जा सकी। फ़ाइल ख़राब या हट गई हो सकती है — किताब को दोबारा जोड़ें।',
      );
  String get epubChapterFailed => _("This chapter couldn't be read.", 'यह अध्याय पढ़ा नहीं जा सका।');
  String get epubChapterEmpty => _('Nothing to read in this section (it may be a cover or an image).', 'इस भाग में पढ़ने को कुछ नहीं है (शायद कवर या तस्वीर हो)।');
  String get pdfOpenFailed => _(
        "This PDF couldn't be opened. The file may have been removed — add the book again.",
        'यह PDF खोली नहीं जा सकी। फ़ाइल हट गई हो सकती है — किताब को दोबारा जोड़ें।',
      );

  // ---- tooltip / entry ----
  String get explainInSentence => _('Which meaning fits here?', 'यहाँ कौन-सा अर्थ बैठता है?');
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
  String get save => _('Save word', 'शब्द सहेजें');
  String get saved => _('Saved', 'सहेजा गया');
  String get unsave => _('Remove from saved', 'सहेजे से हटाएँ');
  String get didYouMean => _('Did you mean', 'क्या आपका मतलब था');
  String get attribution => _('Based on Wiktionary (CC BY-SA)', 'Wiktionary (CC BY-SA) के आधार पर');

  // ---- dictionary ----
  String get dictionaryTitle => _('Dictionary', 'शब्दकोश');
  String get searchHint => _('Any English word', 'कोई अंग्रेज़ी शब्द');
  String get recent => _('Recent', 'हाल के');
  String get removeRecent => _('Remove from recent', 'हाल की खोज से हटाएँ');
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
  String get languageSampleEn => 'Library, Dictionary, Cards';
  String get languageSampleHi => 'किताबें, शब्दकोश, कार्ड';
  String get hindiSizeSample => 'मतलब, आशय — जैसे इस वाक्य में';
  String get settingsIntro => _(
        'How Arth reads with you.',
        'Arth आपके साथ कैसे पढ़े।',
      );
  String get tooltipDetail => _('Tooltip', 'टूलटिप');
  String get tooltipCompact => _('Compact', 'छोटा');
  String get tooltipDetailed => _('Detailed', 'विस्तार से');
  String get hindiSize => _('Hindi text size', 'हिंदी का आकार');
  String get tts => _('Pronunciation (TTS)', 'उच्चारण सुनें (TTS)');
  String get haptics => _('Vibration on touch', 'छूने पर हल्का कंपन');
  String get cardFont => _('Card font', 'कार्ड का फ़ॉन्ट');
  String get cardFontHelp => _(
        'How your cards look, here and when you share them: the PDF and the community use it too.',
        'आपके कार्ड कैसे दिखें — यहाँ भी, और साझा करते समय PDF और समुदाय में भी।',
      );
  String get cardReminders => _('Card review reminders', 'कार्ड दोहराने की याद');
  String get cardRemindersHelp => _(
        'After you make a card, a reminder to look at it again. Never between 10 pm and 9 am.',
        'कार्ड बनाने के बाद उसे फिर देखने की याद। रात 10 से सुबह 9 बजे के बीच कभी नहीं।',
      );
  String reminderNumber(int n) => _(
        switch (n) { 1 => 'First reminder', 2 => 'Second reminder', _ => 'Third reminder' },
        switch (n) { 1 => 'पहली याद', 2 => 'दूसरी याद', _ => 'तीसरी याद' },
      );
  String afterHours(int h) => h % 168 == 0
      ? _(h == 168 ? 'After 1 week' : 'After ${h ~/ 168} weeks', '${h ~/ 168} हफ़्ते बाद')
      : h % 24 == 0 && h >= 48
          ? _('After ${h ~/ 24} days', '${h ~/ 24} दिन बाद')
          : h == 24
              ? _('After 1 day', '1 दिन बाद')
              : _('After $h hours', '$h घंटे बाद');
  String get remindersBlocked => _(
        'Notifications are off for Arth. Turn them on in your phone’s settings to get reminders.',
        'Arth की सूचनाएँ बंद हैं। याद पाने के लिए फ़ोन की सेटिंग में इन्हें चालू करें।',
      );
  String get reminderTitle => _('Time to look at your cards', 'कार्ड दोहराने का समय');
  String reminderBody(int cards, String? book, int otherBooks) {
    final what = cardCount(cards);
    if (book == null) return _('$what are ready for a quick review.', '$what एक झलक के लिए तैयार हैं।');
    if (otherBooks == 0) return _('$what from $book are ready for a quick review.', '$book के $what एक झलक के लिए तैयार हैं।');
    return _(
      '$what from $book and ${otherBooks == 1 ? '1 more book' : '$otherBooks more books'} are ready for a quick review.',
      '$book और $otherBooks और किताबों के $what एक झलक के लिए तैयार हैं।',
    );
  }
  String get guideTitle => _('How to read here', 'यहाँ पढ़ने का तरीका');
  String get guideSwipe => _('Swipe sideways to turn the page. A tap on the edge of the page turns it too.', 'पन्ना पलटने के लिए साइड में स्वाइप करें। पन्ने के किनारे पर टैप करने से भी पन्ना पलटता है।');
  String get guideTap => _('Tap a word for its Hindi meaning and how it is used in this sentence.', 'किसी शब्द पर टैप करें, उसका हिंदी अर्थ और इस वाक्य में प्रयोग दिखेगा।');
  String get guideHold => _('Press and hold a word, then drag to select a sentence. Highlight it, translate it or save it as a card.', 'किसी शब्द को दबाकर रखें, फिर खींचकर वाक्य चुनें। उसे हाइलाइट करें, अनुवाद करें या कार्ड बनाएँ।');
  String get guideBookmark => _('Tap the ribbon at the top to bookmark a page. Find it again in the ⋮ menu.', 'पन्ना सहेजने के लिए ऊपर रिबन पर टैप करें। उसे ⋮ मेन्यू में फिर पाएँ।');
  String get guideGotIt => _('Got it', 'समझ गया');
  String get showGuideAgain => _('Show the reading guide again', 'पढ़ने का गाइड फिर दिखाएँ');
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

  // ---- seed ----
  String get seedTitle => _('Preparing the dictionary', 'शब्दकोश तैयार हो रहा है');
  String get seedBody => _(
        'Once downloaded, common words work without internet.',
        'एक बार डाउनलोड होने के बाद आम शब्द बिना इंटरनेट भी मिलेंगे।',
      );
  String get connecting => _('Connecting…', 'जुड़ रहा है…');
  String get retry => _('Try again', 'फिर कोशिश करें');
  String get skipForNow => _('Skip for now', 'अभी छोड़ें');
  String get seedKeepsGoing => _(
        'You can start reading now — the download carries on in the background.',
        'आप अभी पढ़ना शुरू कर सकते हैं — डाउनलोड पीछे चलता रहेगा।',
      );
  String get downloadFailed => _('Download failed.', 'डाउनलोड नहीं हो पाया।');

  // ---- errors (client-side codes; server messages are Hindi) ----
  String get offline => _(
        'Internet needed for more meanings',
        'और अर्थ देखने के लिए इंटरनेट चाहिए',
      );
  String get notFound => _('Not in the dictionary.', 'यह शब्द शब्दकोश में नहीं मिला।');
  String get lookingUp => _('Looking this up…', 'अर्थ ढूँढ रहे हैं…');
  // ---- reading habit ----
  String get readingHabit => _('Reading habit', 'पढ़ने की आदत');
  String get readToday => _('Read today', 'आज पढ़ा');
  String ofGoal(int min) => _('of your $min min goal', '$min मिनट के लक्ष्य में से');
  String dayStreak(int n) => _(n == 1 ? '1 day streak' : '$n day streak', n == 1 ? '1 दिन लगातार' : '$n दिन लगातार');
  String bestStreak(int n) => _('Best: $n days', 'सबसे लंबा: $n दिन');
  String get dailyGoal => _('Daily goal', 'रोज़ का लक्ष्य');
  String get minShort => _('min', 'मिनट');
  String get thisWeek => _('This week', 'इस हफ़्ते');
  String get perPage => _('per page', 'हर पन्ने पर');
  String get totalReading => _('reading time', 'पढ़ने का समय');
  String get pagesRead => _('pages read', 'पन्ने पढ़े');
  String get yourBooks => _('Your books', 'आपकी किताबें');
  String get habitEmpty => _(
        'Open a book and read for a few seconds. Your pace per page, and how long each book takes, will show up here.',
        'कोई किताब खोलकर कुछ देर पढ़ें। हर पन्ने पर आपकी रफ़्तार और किताब पूरी होने का समय यहाँ दिखेगा।',
      );
  String get tipGoalMet => _('Goal met today. Well done!', 'आज का लक्ष्य पूरा हुआ। शाबाश!');
  String tipKeepStreak(int n) => _('Read for a minute today to keep your $n-day streak going.', 'अपनी $n दिन की लकीर बनाए रखने के लिए आज एक मिनट पढ़ें।');
  String tipToGo(String left) => _('$left more to reach today’s goal.', 'आज के लक्ष्य के लिए $left और पढ़ें।');
  String tipBestHour(String hour) => _('You read most around $hour. Make it your daily reading slot.', 'आप सबसे ज़्यादा $hour के आसपास पढ़ते हैं। इसे अपना रोज़ का पढ़ने का समय बनाएँ।');
  String pacePerPage(String d) => _('$d per page', 'हर पन्ने पर $d');
  String timeAndDays(String d, int days) => _('$d over ${days == 1 ? '1 day' : '$days days'}', '$days दिन में $d');
  String finishedIn(int days, String d) => _('Finished in ${days == 1 ? '1 day' : '$days days'} ($d of reading)', '${days == 1 ? '1 दिन' : '$days दिन'} में पूरी ($d पढ़ना)');
  String timeLeft(String d) => _('About $d left at your pace', 'आपकी रफ़्तार से लगभग $d बाकी');
  String get readingMode => _('Reading mode', 'पढ़ने का मोड');
  String get scrollingMode => _('Scrolling mode', 'स्क्रॉल मोड');
  String get zoomIn => _('Zoom in', 'ज़ूम बढ़ाएँ');
  String get zoomOut => _('Zoom out', 'ज़ूम घटाएँ');
  String get meaning => _('Meaning', 'अर्थ');
  String get copy => _('Copy', 'कॉपी करें');
  String get copied => _('Copied', 'कॉपी हो गया');
  String get search => _('Search', 'खोजें');
  String get searchInBook => _('Search in this book', 'इस किताब में खोजें');
  String get searchHelp => _('Type a word or phrase to find it in the book.', 'किताब में ढूँढने के लिए कोई शब्द या वाक्यांश लिखें।');
  String get noMatches => _('No matches found.', 'कोई मेल नहीं मिला।');
  String get searchTruncated => _('Showing the first 300 matches. Try a longer phrase.', 'पहले 300 नतीजे दिखा रहे हैं। थोड़ा लंबा वाक्यांश आज़माएँ।');
  String get translateSentence => _('Translate this sentence', 'यह वाक्य अनुवाद करें');
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
        'UNAVAILABLE' => _('This isn’t available yet. Try again later.', 'यह अभी उपलब्ध नहीं है। बाद में कोशिश करें।'),
        'INTERNAL' || 'UPSTREAM_FAILED' => isHindi ? serverMessage : somethingWrong,
        _ => serverMessage,
      };

  // ---- flashcards ----
  String get tabCards => _('Cards', 'कार्ड');
  String get cardsTitle => _('Cards', 'कार्ड');
  String get decks => _('Books', 'किताबें');
  String get words => _('Words', 'शब्द');
  String get kindIdea => _('Idea', 'विचार');
  String get kindQuote => _('Quote', 'उद्धरण');
  String get kindWord => _('Word', 'शब्द');
  String get makeCard => _('Make card', 'कार्ड बनाएँ');
  String get newCard => _('New card', 'नया कार्ड');
  String get editCard => _('Edit card', 'कार्ड बदलें');
  String get addNote => _('Add a note card', 'नोट कार्ड जोड़ें');
  String get cardFront => _('Front', 'सामने');
  String get cardBack => _('Back', 'पीछे');
  String get cardNote => _('Your note', 'आपका नोट');
  String get frontHintIdea => _('A question, a character, a turning point…', 'कोई सवाल, कोई पात्र, कोई मोड़…');
  String get backHintIdea => _('What you want to remember', 'जो आप याद रखना चाहते हैं');
  String get frontHintQuote => _('The line from the book', 'किताब की पंक्ति');
  String get backHintQuote => _('Its meaning', 'इसका अर्थ');
  String get frontHintWord => _('The word', 'शब्द');
  String get backHintWord => _('Its meaning', 'इसका अर्थ');
  String get noteHint => _('Why it matters to you (optional)', 'यह आपके लिए क्यों ज़रूरी है (वैकल्पिक)');
  String get saveCard => _('Save card', 'कार्ड सहेजें');
  String get cardSaved => _('Card saved', 'कार्ड सहेजा गया');
  String get deleteCard => _('Delete card', 'कार्ड हटाएँ');
  String get cardDeleted => _('Card deleted', 'कार्ड हटाया गया');
  String get undo => _('Undo', 'वापस लें');
  String get fromTheBook => _('From the book', 'किताब से');
  String get emptyBack => _('Nothing on the back yet. Edit the card from the recap to add an answer.', 'पीछे अभी कुछ नहीं लिखा। सार में कार्ड बदलकर जवाब जोड़ें।');
  String kindCount(CardKindName kind, int n) => switch (kind) {
        CardKindName.idea => _(n == 1 ? '1 idea' : '$n ideas', '$n विचार'),
        CardKindName.quote => _(n == 1 ? '1 quote' : '$n quotes', '$n उद्धरण'),
        CardKindName.word => _(n == 1 ? '1 word' : '$n words', '$n शब्द'),
      };
  String get cardsEmptyTitle => _('No cards yet', 'अभी कोई कार्ड नहीं');
  String get cardsEmptyBody => _(
        'While reading, tap “Make card” on a word or translation, or use the note button to write down an idea. Your cards become a recap of each book.',
        'पढ़ते हुए किसी शब्द या अनुवाद पर “कार्ड बनाएँ” दबाएँ, या नोट बटन से कोई विचार लिखें। आपके कार्ड हर किताब का सार बन जाते हैं।',
      );
  String cardCount(int n) => _(n == 1 ? '1 card' : '$n cards', '$n कार्ड');
  String dueCount(int n) => _('$n to review', '$n दोहराने हैं');
  String get recap => _('Recap', 'सार');
  String get replayInOrder => _('Replay the book', 'किताब दोबारा देखें');
  String get replayInOrderHint => _('Every card, in reading order', 'सारे कार्ड, पढ़ने के क्रम में');
  String get practice => _('Practice', 'अभ्यास');
  String get practiceHint => _('Due cards first, flip and rate', 'पहले ज़रूरी कार्ड, पलटें और बताएँ');
  String get tapToFlip => _('Tap to flip', 'पलटने के लिए टैप करें');
  String get again => _('Again', 'फिर से');
  String get gotIt => _('Got it', 'याद है');
  String get next => _('Next', 'आगे');
  String get reviewDone => _('Done for now', 'अभी के लिए बस');
  String reviewSummary(int known, int total) => _('You knew $known of $total.', '$total में से $known याद थे।');
  String get reviewAgain => _('Go again', 'फिर से करें');
  String get finish => _('Finish', 'ख़त्म करें');
  String get openInBook => _('Open in book', 'किताब में खोलें');
  String get all => _('All', 'सब');
  String get bookRemoved => _('Book removed from library', 'किताब लाइब्रेरी से हटा दी गई');
  String readPercent(int p) => _('$p% read', '$p% पढ़ा');
  String get finishedReading => _('Finished', 'पूरी पढ़ी');
  String get markAsRead => _('Mark as read', 'पढ़ी हुई मानें');
  String get markAsUnread => _('Mark as unread', 'बिना पढ़ी मानें');
  String get readFilter => _('Read', 'पढ़ी हुई');
  String get unreadFilter => _('Unread', 'बाकी');
  String readOn(DateTime d) {
    const en = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const hi = ['जन', 'फ़र', 'मार्च', 'अप्रै', 'मई', 'जून', 'जुला', 'अग', 'सित', 'अक्टू', 'नव', 'दिस'];
    final month = (isHindi ? hi : en)[d.month - 1];
    final year = d.year == DateTime.now().year ? '' : ' ${d.year}';
    return _('Read · ${d.day} $month$year', 'पढ़ी · ${d.day} $month$year');
  }
  String finishedTitle(String book) => _('You finished $book!', 'आपने $book पूरी पढ़ ली!');
  String finishedBody(int cards) => cards == 0
      ? _('Write down a few ideas while it’s fresh — they’ll be your recap of this book.', 'अभी याद ताज़ा है — कुछ विचार लिख लें, यही इस किताब का सार बनेंगे।')
      : _('You made ${cardCount(cards)} along the way. Flip through ${cards == 1 ? 'it' : 'them'} while the story is fresh.', 'पढ़ते हुए आपने $cards कार्ड बनाए। कहानी ताज़ा है, एक बार पलटकर देख लें।');
  String get seeRecap => _('See the recap', 'सार देखें');
  String get later => _('Later', 'बाद में');

  // ---- bookmarks & progress ----
  String get bookmarks => _('Bookmarks', 'बुकमार्क');
  String get addBookmark => _('Bookmark this page', 'यह पन्ना बुकमार्क करें');
  String get removeBookmark => _('Remove bookmark', 'बुकमार्क हटाएँ');
  String get bookmarkAdded => _('Bookmarked', 'बुकमार्क किया गया');
  String get bookmarksEmpty => _('No bookmarks yet. Tap the ribbon at the top to mark a place.', 'अभी कोई बुकमार्क नहीं। ऊपर रिबन दबाकर जगह चिह्नित करें।');
  String get more => _('More', 'और');
  String get aiLookup => _('AI lookup', 'AI अर्थ');
  String get aiLookupHelp => _(
        'For every book. On, selecting text asks for a translation. Off, it only highlights.',
        'हर किताब में। चालू होने पर टेक्स्ट चुनने से अनुवाद माँगा जाता है। बंद होने पर सिर्फ़ हाइलाइट।',
      );
  String get aiLookupSignIn => _(
        'Sign in to turn on AI lookup. Your first 100 AI answers are free.',
        'AI अर्थ चालू करने के लिए साइन इन करें। पहले 100 AI जवाब मुफ़्त हैं।',
      );
  String get usageStats => _('Share usage stats', 'उपयोग के आँकड़े भेजें');
  String get usageStatsHelp => _(
        'Which screens and features you use, to help us improve Arth. Never your books or the words you look up.',
        'आप कौन-सी स्क्रीन और सुविधाएँ इस्तेमाल करते हैं, ताकि हम Arth बेहतर बना सकें। आपकी किताबें या खोजे गए शब्द कभी नहीं।',
      );
  String get continueReading => _('Continue reading', 'पढ़ना जारी रखें');
  // ---- vocabulary ----
  String get vocabulary => _('Vocabulary', 'शब्द भंडार');
  String get wordsFromBook => _('Saved words from this book', 'इस किताब के सहेजे शब्द');
  String get exportWordsPdf => _('Export words as PDF', 'शब्दों का PDF बनाएँ');
  String wordCount(int n) => _(n == 1 ? '1 word' : '$n words', '$n शब्द');
  String pdfWordsSubject(String book) => _('My words from $book', '$book से मेरे शब्द');
  String firstSavedIn(String book) => _('First saved in $book', 'पहली बार सहेजा: $book');
  String lifetimeWords(int words, int books) => _(
        '${words == 1 ? '1 word' : '$words words'} from ${books == 1 ? '1 book' : '$books books'}',
        '$books किताबों से $words शब्द',
      );
  String bookWordsSummary(int all, int fresh) => _(
        'You saved ${all == 1 ? '1 word' : '$all words'} in this book; ${fresh == all ? (all == 1 ? 'it is' : 'all are') : '$fresh'} new to you.',
        'इस किताब में आपने $all शब्द सहेजे; इनमें से $fresh आपके लिए नए हैं।',
      );
  String newToYou(int n) => _('New to you  $n', 'नए  $n');
  String allWords(int n) => _('All  $n', 'सभी  $n');
  String get metBefore => _('Met in an earlier book', 'पहले किसी किताब में मिला');
  String firstMetIn(String book) => _('First met in $book', 'पहली बार: $book');
  String lookedUpTimes(int n) => _(n == 1 ? 'looked up once' : 'looked up $n times', '$n बार देखा');
  String inBooks(int n) => _('in $n books', '$n किताबों में');
  String get sortAz => _('A–Z', 'अ–ज़');
  String get searchWords => _('Search your words', 'अपने शब्द खोजें');
  String get removeFromVocabulary => _('Remove from vocabulary', 'शब्द भंडार से हटाएँ');
  String get vocabularyEmpty => _(
        'Words you save while reading gather here by themselves, with the book you saved them in.',
        'पढ़ते समय जो शब्द आप सहेजते हैं, वे अपने-आप उस किताब के नाम के साथ यहाँ जमा होते हैं।',
      );
  String get bookVocabularyEmpty => _(
        'No words saved from this book yet. Tap a word while reading, then tap 🔖 on its card to save it here.',
        'इस किताब से अभी कोई शब्द नहीं सहेजा। पढ़ते समय किसी शब्द पर टैप करें, फिर उसके कार्ड पर 🔖 दबाकर यहाँ सहेजें।',
      );
  String get seeAllWords => _('All your words', 'आपके सारे शब्द');

  String get cardsForBook => _('Cards for this book', 'इस किताब के कार्ड');

  // ---- account ----
  String get signIn => _('Sign in', 'साइन इन करें');
  String get signInPitch => _('Keep your cards and bookmarks safe, and on every phone you read on.', 'अपने कार्ड और बुकमार्क सुरक्षित रखें, हर उस फ़ोन पर जिस पर आप पढ़ते हैं।');
  String get signInTitle => _('Sign in to Arth', 'Arth में साइन इन करें');
  String get continueWithGoogle => _('Continue with Google', 'Google से जारी रखें');
  String get orPhone => _('or with your phone number', 'या अपने फ़ोन नंबर से');
  String get phoneNumber => _('Phone number', 'फ़ोन नंबर');
  String get sendCode => _('Send code', 'कोड भेजें');
  String codeSentTo(String phone) => _('Enter the 6-digit code sent to $phone', '$phone पर भेजा गया 6 अंकों का कोड डालें');
  String get verify => _('Verify', 'पुष्टि करें');
  String get changeNumber => _('Change number', 'नंबर बदलें');
  String get resendCode => _('Resend code', 'कोड दोबारा भेजें');
  String resendIn(int s) => _('Resend in ${s}s', '$s सेकंड में दोबारा भेजें');
  String get signInPrivacy => _('Your books stay on your phone. Only your cards, bookmarks and profile are stored with your account.', 'आपकी किताबें आपके फ़ोन पर ही रहती हैं। खाते में सिर्फ़ आपके कार्ड, बुकमार्क और प्रोफ़ाइल रखे जाते हैं।');
  String authError(String code) => switch (code) {
        'cancelled' => _('Sign-in didn’t finish. Make sure a Google account is added on this phone, then try again.', 'साइन इन पूरा नहीं हुआ। देखें कि इस फ़ोन में Google खाता जुड़ा है, फिर कोशिश करें।'),
        'network' => offline,
        'invalidPhone' => _('That phone number doesn’t look right.', 'यह फ़ोन नंबर सही नहीं लग रहा।'),
        'invalidCode' => _('That code isn’t right. Check the SMS and try again.', 'कोड सही नहीं है। SMS देखकर फिर कोशिश करें।'),
        'codeExpired' => _('The code expired. Send a new one.', 'कोड की अवधि खत्म हो गई। नया कोड भेजें।'),
        'tooManyRequests' => _('Too many tries. Wait a while and try again.', 'बहुत बार कोशिश हुई। थोड़ी देर बाद फिर करें।'),
        _ => _('Couldn’t sign in. Please try again.', 'साइन इन नहीं हो पाया। फिर कोशिश करें।'),
      };
  String get profile => _('Profile', 'प्रोफ़ाइल');
  String get editProfile => _('Edit profile', 'प्रोफ़ाइल बदलें');
  String get displayName => _('Name', 'नाम');
  String get bio => _('About you', 'आपके बारे में');
  String get bioHint => _('What you like to read (optional)', 'आपको क्या पढ़ना पसंद है (वैकल्पिक)');
  String get changePhoto => _('Change photo', 'फ़ोटो बदलें');
  String get removePhoto => _('Remove photo', 'फ़ोटो हटाएँ');
  String get saveProfile => _('Save', 'सहेजें');
  String get profileSaved => _('Profile saved', 'प्रोफ़ाइल सहेजी गई');
  String get photoFailed => _('Couldn’t upload the photo. Try again.', 'फ़ोटो अपलोड नहीं हो पाई। फिर कोशिश करें।');
  String get signOut => _('Sign out', 'साइन आउट');
  String get reviewReminders => _('Review reminders', 'दोहराने की याद');
  String get reviewRemindersHelp => _('A notification when your cards are ready to review, at most once a day.', 'जब आपके कार्ड दोहराने के लिए तैयार हों, दिन में ज़्यादा से ज़्यादा एक बार सूचना।');
  String get testNotification => _('Send a test notification', 'परीक्षण सूचना भेजें');
  String testNotificationSent(int n) => n == 0
      ? _('No phone is set up for notifications yet. Allow notifications for Arth and try again.', 'अभी किसी फ़ोन पर सूचनाएँ चालू नहीं हैं। Arth के लिए सूचनाएँ चालू करके फिर कोशिश करें।')
      : _('Sent. It should arrive in a few seconds.', 'भेज दी गई। कुछ सेकंड में आ जाएगी।');
  String get signOutConfirm => _('Sign out? Your cards stay on this phone and in your account.', 'साइन आउट करें? आपके कार्ड इस फ़ोन पर और आपके खाते में रहेंगे।');
  String get cancel => _('Cancel', 'रद्द करें');
  String get syncNow => _('Sync now', 'अभी सिंक करें');
  String get syncing => _('Syncing…', 'सिंक हो रहा है…');
  String get syncFailed => _('Couldn’t sync. Will try again.', 'सिंक नहीं हो पाया। फिर कोशिश होगी।');
  String syncedAgo(Duration d) => d.inMinutes < 1
      ? _('Synced just now', 'अभी सिंक हुआ')
      : d.inHours < 1
          ? _('Synced ${d.inMinutes} min ago', '${d.inMinutes} मिनट पहले सिंक हुआ')
          : _('Synced ${d.inHours} h ago', '${d.inHours} घंटे पहले सिंक हुआ');
  String get notSyncedYet => _('Not synced yet', 'अभी सिंक नहीं हुआ');
  String get tierFree => _('Free', 'फ़्री');
  String get tierPro => _('Pro', 'प्रो');
  String get tierSuper => _('Super', 'सुपर');
  String get admin => _('Admin', 'एडमिन');

  // ---- AI allowance & plans ----
  String get aiSignInContext => _('Sign in to see what it means in this sentence. Your first 100 AI answers are free.', 'इस वाक्य में इसका मतलब देखने के लिए साइन इन करें। पहले 100 AI जवाब मुफ़्त हैं।');
  String get aiSignInTranslate => _('Sign in to translate sentences. Your first 100 AI answers are free.', 'वाक्यों का अनुवाद देखने के लिए साइन इन करें। पहले 100 AI जवाब मुफ़्त हैं।');
  String get aiSignInRareWord => _('This word isn’t in the offline dictionary. Sign in to look it up with AI.', 'यह शब्द ऑफ़लाइन शब्दकोश में नहीं है। AI से देखने के लिए साइन इन करें।');
  String get aiQuotaUsed => _('You’ve used all your AI answers. The offline dictionary still works.', 'आपके सारे AI जवाब इस्तेमाल हो चुके हैं। ऑफ़लाइन शब्दकोश चलता रहेगा।');
  String get aiQuotaPhone => _(
        'This phone has already used its free AI answers, on this or another account. A plan brings them back; the offline dictionary still works.',
        'इस फ़ोन के मुफ़्त AI जवाब इस या किसी दूसरे खाते से इस्तेमाल हो चुके हैं। प्लान लेकर फिर पाएँ; ऑफ़लाइन शब्दकोश चलता रहेगा।',
      );
  String aiQuotaResets(String date) => _('You’ve used this month’s AI answers. More on $date; the offline dictionary still works.', 'इस महीने के AI जवाब खत्म हो गए। $date से फिर मिलेंगे; ऑफ़लाइन शब्दकोश चलता रहेगा।');
  String get seePlans => _('See plans', 'प्लान देखें');
  String get plans => _('Plans', 'प्लान');
  String get plansIntro => _('The dictionary on your phone is always free. AI answers — the meaning in this sentence, sentence translations, rare words — depend on your plan.', 'फ़ोन का शब्दकोश हमेशा मुफ़्त है। AI जवाब — इस वाक्य में मतलब, वाक्य का अनुवाद, दुर्लभ शब्द — आपके प्लान पर निर्भर हैं।');
  String get planFreeAi => _('100 AI answers, to try it out', 'आज़माने के लिए 100 AI जवाब');
  String get planProAi => _('500 AI answers every month', 'हर महीने 500 AI जवाब');
  String get planSuperAi => _('5,000 AI answers every month', 'हर महीने 5,000 AI जवाब');
  String get yearly => _('Yearly', 'सालाना');
  String get monthly => _('Monthly', 'मासिक');
  String saveUpTo(int pct) => _('Save $pct%', '$pct% बचत');
  String perYear(String price) => _('$price a year', '$price प्रति वर्ष');
  String perMonth(String price) => _('$price a month', '$price प्रति माह');
  String aboutPerMonth(String price) => _('about $price a month', 'लगभग $price प्रति माह');
  String daysFree(int n) => _('$n days free', '$n दिन मुफ़्त');
  String introOffer(String price, int months, String then) => _(
        '$price a month for your first $months months, then $then',
        'पहले $months महीने $price प्रति माह, फिर $then',
      );
  String startTrial(int n) => _('Start $n-day free trial', '$n दिन का मुफ़्त ट्रायल शुरू करें');
  String subscribeTo(String plan) => _('Get $plan', '$plan लें');
  String get manageSubscription => _('Manage subscription', 'सदस्यता बदलें या रद्द करें');
  String get deleteAccount => _('Delete account', 'खाता हटाएँ');
  String get deleteAccountTitle => _('Delete your account?', 'अपना खाता हटाएँ?');
  String get deleteAccountBody => _(
        'This permanently deletes your account, profile and photo, your synced cards and bookmarks, and the recaps, comments and likes you shared. It can’t be undone.',
        'इससे आपका खाता, प्रोफ़ाइल और फ़ोटो, सिंक किए कार्ड और बुकमार्क, और आपके साझा किए सार, टिप्पणियाँ और पसंद हमेशा के लिए हट जाएँगे। इसे वापस नहीं किया जा सकता।',
      );
  String get deleteAccountLocal => _(
        'Cards and bookmarks already on this phone stay here.',
        'इस फ़ोन पर पहले से मौजूद कार्ड और बुकमार्क यहीं रहेंगे।',
      );
  String deleteAccountSubscription(String store) => _(
        'Deleting your account doesn’t cancel a subscription. If you subscribed, cancel it in $store first, or you’ll keep being charged.',
        'खाता हटाने से सदस्यता रद्द नहीं होती। अगर आपने सदस्यता ली है, तो पहले $store में रद्द करें, वरना पैसे कटते रहेंगे।',
      );
  String get deleteForever => _('Delete forever', 'हमेशा के लिए हटाएँ');
  String get accountDeleted => _('Your account has been deleted.', 'आपका खाता हटा दिया गया है।');
  String get termsOfUse => _('Terms of Use', 'उपयोग की शर्तें');
  String get privacyPolicy => _('Privacy Policy', 'निजता नीति');
  String get restorePurchases => _('Restore purchases', 'पिछली ख़रीद वापस लाएँ');
  String get restored => _('Purchases restored.', 'ख़रीद वापस आ गई।');
  String renewNote(String store) => _(
        'Subscriptions renew automatically until cancelled. Cancel anytime in $store, at least a day before renewal. A free trial becomes a paid subscription unless you cancel before it ends.',
        'सदस्यता रद्द करने तक अपने-आप नवीनीकृत होती है। $store में कभी भी रद्द करें, नवीनीकरण से कम से कम एक दिन पहले। मुफ़्त ट्रायल ख़त्म होने से पहले रद्द न करने पर सशुल्क सदस्यता शुरू हो जाती है।',
      );
  String welcomeTo(String plan) => _('Welcome to $plan!', '$plan में आपका स्वागत है!');
  String get purchaseFailed => _('The purchase didn’t go through. You haven’t been charged; try again.', 'ख़रीद पूरी नहीं हुई। आपसे पैसे नहीं लिए गए; फिर कोशिश करें।');
  String get signInToBuy => _('Sign in first, so your plan stays with your account on every phone.', 'पहले साइन इन करें, ताकि आपका प्लान हर फ़ोन पर आपके खाते के साथ रहे।');
  String get plansUnavailable => _('Plans can’t be loaded right now. Check your connection and try again.', 'प्लान अभी लोड नहीं हो पा रहे। इंटरनेट देखें और फिर कोशिश करें।');
  String get planOfflineDictionary => _('Offline dictionary, flashcards, sync', 'ऑफ़लाइन शब्दकोश, फ़्लैशकार्ड, सिंक');
  String get planAds => _('Ads outside the reader', 'रीडर के बाहर विज्ञापन');
  String get planNoAds => _('No ads', 'कोई विज्ञापन नहीं');
  String get currentPlan => _('Your plan', 'आपका प्लान');
  String get requestUpgrade => _('Ask for an upgrade', 'अपग्रेड का अनुरोध करें');
  String get upgradeNote => _('Paid plans aren’t in the app yet. Write to us and we’ll upgrade your account.', 'पेड प्लान अभी ऐप में नहीं हैं। हमें लिखें, हम आपका खाता अपग्रेड कर देंगे।');
  String aiLeft(int left, int limit) => _('$left of $limit AI answers left', '$limit में से $left AI जवाब बाकी');
  String aiLeftMonth(int left, int limit) => _('$left of $limit AI answers left this month', 'इस महीने $limit में से $left AI जवाब बाकी');
  String get aiUnlimited => _('Unlimited AI answers', 'असीमित AI जवाब');

  // ---- community ----
  String get tabCommunity => _('Community', 'समुदाय');
  String get communityTitle => _('Community', 'समुदाय');
  String get communityIntro => _('Recaps other readers made of their books. Save one to review it as your own cards.', 'दूसरे पाठकों ने अपनी किताबों के जो सार बनाए। किसी को सहेजें और अपने कार्ड की तरह दोहराएँ।');
  String get searchBooks => _('Search by book', 'किताब से खोजें');
  String get sortRecent => _('Recent', 'नए');
  String get sortPopular => _('Popular', 'लोकप्रिय');
  String get communityEmpty => _('No recaps yet. When readers share their cards for a book, they appear here.', 'अभी कोई सार नहीं। जब पाठक किसी किताब के अपने कार्ड साझा करेंगे, वे यहाँ दिखेंगे।');
  String get communityNoMatches => _('No recaps for that book yet.', 'इस किताब का अभी कोई सार नहीं।');
  String byAuthor(String name) => _('by $name', '$name का');
  String likesCount(int n) => _(n == 1 ? '1 like' : '$n likes', '$n पसंद');
  String savesCount(int n) => _(n == 1 ? '1 save' : '$n saves', '$n ने सहेजा');
  String commentsCount(int n) => _(n == 1 ? '1 comment' : '$n comments', '$n टिप्पणियाँ');
  String get like => _('Like', 'पसंद');
  String get saveToMyCards => _('Save to my cards', 'मेरे कार्ड में सहेजें');
  String savedCards(int n) => _('Saved ${cardCount(n)} to your Cards.', '$n कार्ड आपके कार्ड में सहेजे गए।');
  String get openMyCopy => _('Open', 'खोलें');
  String get comments => _('Comments', 'टिप्पणियाँ');
  String get noComments => _('No comments yet. Say what you thought of this recap.', 'अभी कोई टिप्पणी नहीं। बताइए यह सार आपको कैसा लगा।');
  String get writeComment => _('Add a comment…', 'टिप्पणी लिखें…');
  String replyingTo(String name) => _('Replying to $name', '$name को जवाब');
  String get reply => _('Reply', 'जवाब दें');
  String get send => _('Send', 'भेजें');
  String get signInToJoin => _('Sign in to like, save and comment.', 'पसंद करने, सहेजने और टिप्पणी के लिए साइन इन करें।');
  String get report => _('Report', 'रिपोर्ट करें');
  String get reportTitle => _('Report this?', 'इसकी रिपोर्ट करें?');
  String get reportHint => _('What’s wrong? (optional)', 'क्या गलत है? (वैकल्पिक)');
  String get reported => _('Thanks. An admin will take a look.', 'धन्यवाद। एडमिन इसे देखेंगे।');
  String get delete => _('Delete', 'हटाएँ');
  String get deleteDeckConfirm => _('Take this recap down from the community? Your own cards stay.', 'यह सार समुदाय से हटाएँ? आपके अपने कार्ड रहेंगे।');
  String get deleted => _('Deleted', 'हटाया गया');
  String get heldForReview => _('Held for review after reports. Only you can see it until an admin decides.', 'रिपोर्ट के बाद समीक्षा के लिए रोका गया। एडमिन के फ़ैसले तक सिर्फ़ आप इसे देख सकते हैं।');
  String get shareToCommunity => _('Share to community', 'समुदाय में साझा करें');
  String get shareTitle => _('Share your recap', 'अपना सार साझा करें');
  String get share => _('Share', 'साझा करें');
  String get exportPdf => _('Export as PDF', 'PDF बनाएँ');
  String get exportPdfHint => _(
        'Every card, to send to anyone or print. No account needed.',
        'सारे कार्ड, किसी को भेजने या छापने के लिए। खाते की ज़रूरत नहीं।',
      );
  String get shareToCommunityHint => _(
        'Publish your cards for other Arth readers.',
        'अपने कार्ड Arth के दूसरे पाठकों के लिए प्रकाशित करें।',
      );
  String get preparingPdf => _('Making the PDF…', 'PDF बन रहा है…');
  String get pdfFailed => _('Couldn’t make the PDF. Try again.', 'PDF नहीं बन पाया। फिर कोशिश करें।');
  String pdfSubject(String book) => _('My cards from $book', '$book से मेरे कार्ड');
  String get shareIntro => _('Other readers will see the cards you choose, with your name and photo.', 'दूसरे पाठक आपके चुने कार्ड आपके नाम और फ़ोटो के साथ देखेंगे।');
  String get recapTitleHint => _('A title (optional), e.g. “What stayed with me”', 'शीर्षक (वैकल्पिक), जैसे “जो मन में रह गया”');
  String get blurbHint => _('A line about the book or your cards (optional)', 'किताब या कार्ड के बारे में एक पंक्ति (वैकल्पिक)');
  String cardsChosen(int n, int total) => _('$n of $total cards', '$total में से $n कार्ड');
  String get selectAll => _('All', 'सभी');
  String get selectNone => _('None', 'कोई नहीं');
  String get publish => _('Publish', 'प्रकाशित करें');
  String get published => _('Published to the community', 'समुदाय में प्रकाशित हुआ');
  String get communityLockedTitle => _('Community is part of Pro and Super', 'समुदाय Pro और Super में है');
  String get communityLockedBody => _(
        'Readers share recaps of the books they finish: the ideas, quotes and words that stayed with them.',
        'पाठक अपनी पढ़ी किताबों के सार साझा करते हैं: वे विचार, उद्धरण और शब्द जो उनके साथ रह गए।',
      );
  String get communityPerkBrowse => _('Browse recaps of books you’re reading or about to', 'जो किताबें आप पढ़ रहे हैं या पढ़ेंगे, उनके सार देखें');
  String get communityPerkSave => _('Save any recap as your own cards to practise', 'कोई भी सार अपने कार्ड के रूप में सहेजें और दोहराएँ');
  String get communityPerkTalk => _('Like and comment, and hear when someone replies', 'पसंद करें, टिप्पणी करें, और जवाब आने पर सूचना पाएँ');
  String get communityPerkShare => _('Publish your own recaps, in your card font', 'अपने सार अपने कार्ड फ़ॉन्ट में प्रकाशित करें');
  String get publishNeedsPlan => _('Sharing recaps is part of Pro and Super. Anyone can browse, save and comment.', 'सार साझा करना Pro और Super में है। ब्राउज़, सहेजना और टिप्पणी सभी कर सकते हैं।');
  String get scanTitlePaid => _('Scan printed pages', 'छपे पन्ने स्कैन करें');
  String get scanNeedsPlan => _(
        'Photographing a page and reading it word by word is part of Pro and Super. Scans you already have stay readable.',
        'पन्ने की फ़ोटो लेकर उसे शब्द-दर-शब्द पढ़ना Pro और Super में है। पहले से स्कैन किए पन्ने पढ़े जा सकते हैं।',
      );
  String get planScanShare => _('Scan printed pages, share recaps', 'छपे पन्ने स्कैन करें, सार साझा करें');
  String get signInToShare => _('Sign in to share your recap.', 'सार साझा करने के लिए साइन इन करें।');
  String get bannedNotice => _('Your account can’t post in the community right now.', 'आपका खाता अभी समुदाय में लिख नहीं सकता।');
  String get justNow => _('just now', 'अभी');
  String minutesAgo(int n) => _('${n}m', '$n मि');
  String hoursAgo(int n) => _('${n}h', '$n घं');
  String daysAgo(int n) => _('${n}d', '$n दिन');

  // ---- admin ----
  String get adminTitle => _('Admin', 'एडमिन');
  String get adminReports => _('Reports', 'रिपोर्ट');
  String get adminReaders => _('Readers', 'पाठक');
  String get adminBroadcast => _('Broadcast', 'सबको सूचना');
  String get adminOpen => _('Community reports, readers, broadcasts', 'समुदाय रिपोर्ट, पाठक, सबको सूचना');
  String get noReports => _('Nothing reported. All clear.', 'कोई रिपोर्ट नहीं। सब ठीक है।');
  String reportsCount(int n) => _(n == 1 ? '1 report' : '$n reports', '$n रिपोर्ट');
  String get hiddenBadge => _('Hidden', 'छिपा');
  String get removeIt => _('Remove', 'हटाएँ');
  String get keepIt => _('Keep', 'रहने दें');
  String get kindDeck => _('Recap', 'सार');
  String get kindComment => _('Comment', 'टिप्पणी');
  String get searchReaders => _('Name, email, phone or id', 'नाम, ईमेल, फ़ोन या id');
  String get ban => _('Ban', 'प्रतिबंधित करें');
  String get unban => _('Unban', 'प्रतिबंध हटाएँ');
  String get bannedBadge => _('Banned', 'प्रतिबंधित');
  String get setPlan => _('Plan', 'प्लान');
  String get broadcastTitle => _('Title', 'शीर्षक');
  String get broadcastBody => _('Message', 'संदेश');
  String get broadcastTo => _('Send to', 'किसे भेजें');
  String get everyone => _('Everyone', 'सभी');
  String broadcastConfirm(String who) => _('Send this notification to $who?', 'यह सूचना $who को भेजें?');
  String broadcastSent(int readers) => _('Sent to $readers readers.', '$readers पाठकों को भेजी गई।');

  // ---- about ----
  String get madeWith => _('Made with', 'से बनाया');
  String get love => _('love', 'प्यार');
  String get madeBy => _('by', '');
  String get chatOnWhatsApp => _('Chat with Developer on WhatsApp', 'WhatsApp पर डेवलपर से बात करें');
  String get whatsAppHello => _('Hi! I’m writing about Arth.', 'नमस्ते! मैं Arth के बारे में लिख रहा/रही हूँ।');
  String get linkFailed => _('Couldn’t open the link.', 'लिंक नहीं खुल सका।');
  String get aboutTagline => _(
        'Read English books and tap any word — its meaning, in this sentence, in plain Hindi.',
        'अंग्रेज़ी किताबें पढ़ते हुए किसी भी शब्द पर टैप करें — उसका मतलब, इसी वाक्य में, आसान हिंदी में।',
      );
}
