// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contracts.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DictionaryEntry _$DictionaryEntryFromJson(Map<String, dynamic> json) =>
    _DictionaryEntry(
      word: json['word'] as String,
      ipa: json['ipa'] as String,
      hindiPronunciation: json['hindiPronunciation'] as String,
      senses: (json['senses'] as List<dynamic>)
          .map((e) => Sense.fromJson(e as Map<String, dynamic>))
          .toList(),
      synonyms: (json['synonyms'] as List<dynamic>)
          .map((e) => BilingualPair.fromJson(e as Map<String, dynamic>))
          .toList(),
      antonyms: (json['antonyms'] as List<dynamic>)
          .map((e) => BilingualPair.fromJson(e as Map<String, dynamic>))
          .toList(),
      forms: (json['forms'] as List<dynamic>)
          .map((e) => WordForm.fromJson(e as Map<String, dynamic>))
          .toList(),
      isPhrase: json['isPhrase'] as bool,
    );

Map<String, dynamic> _$DictionaryEntryToJson(_DictionaryEntry instance) =>
    <String, dynamic>{
      'word': instance.word,
      'ipa': instance.ipa,
      'hindiPronunciation': instance.hindiPronunciation,
      'senses': instance.senses,
      'synonyms': instance.synonyms,
      'antonyms': instance.antonyms,
      'forms': instance.forms,
      'isPhrase': instance.isPhrase,
    };

_Sense _$SenseFromJson(Map<String, dynamic> json) => _Sense(
  index: (json['index'] as num).toInt(),
  partOfSpeech: json['partOfSpeech'] as String,
  meaning: json['meaning'] as String,
  definition: json['definition'] as String,
  examples: (json['examples'] as List<dynamic>)
      .map((e) => BilingualPair.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SenseToJson(_Sense instance) => <String, dynamic>{
  'index': instance.index,
  'partOfSpeech': instance.partOfSpeech,
  'meaning': instance.meaning,
  'definition': instance.definition,
  'examples': instance.examples,
};

_BilingualPair _$BilingualPairFromJson(Map<String, dynamic> json) =>
    _BilingualPair(en: json['en'] as String, hi: json['hi'] as String);

Map<String, dynamic> _$BilingualPairToJson(_BilingualPair instance) =>
    <String, dynamic>{'en': instance.en, 'hi': instance.hi};

_WordForm _$WordFormFromJson(Map<String, dynamic> json) => _WordForm(
  en: json['en'] as String,
  label: json['label'] as String,
  hi: json['hi'] as String,
);

Map<String, dynamic> _$WordFormToJson(_WordForm instance) => <String, dynamic>{
  'en': instance.en,
  'label': instance.label,
  'hi': instance.hi,
};

_ContextResult _$ContextResultFromJson(Map<String, dynamic> json) =>
    _ContextResult(
      senseIndex: (json['senseIndex'] as num).toInt(),
      meaning: json['meaning'] as String,
      note: json['note'] as String,
    );

Map<String, dynamic> _$ContextResultToJson(_ContextResult instance) =>
    <String, dynamic>{
      'senseIndex': instance.senseIndex,
      'meaning': instance.meaning,
      'note': instance.note,
    };

_TranslationResult _$TranslationResultFromJson(Map<String, dynamic> json) =>
    _TranslationResult(
      source: json['source'] as String,
      hindi: json['hindi'] as String,
      simpleMeaning: json['simpleMeaning'] as String,
      difficultWords: (json['difficultWords'] as List<dynamic>)
          .map(
            (e) => TranslationResultDifficultWords.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
    );

Map<String, dynamic> _$TranslationResultToJson(_TranslationResult instance) =>
    <String, dynamic>{
      'source': instance.source,
      'hindi': instance.hindi,
      'simpleMeaning': instance.simpleMeaning,
      'difficultWords': instance.difficultWords,
    };

_TranslationResultDifficultWords _$TranslationResultDifficultWordsFromJson(
  Map<String, dynamic> json,
) => _TranslationResultDifficultWords(
  en: json['en'] as String,
  hi: json['hi'] as String,
);

Map<String, dynamic> _$TranslationResultDifficultWordsToJson(
  _TranslationResultDifficultWords instance,
) => <String, dynamic>{'en': instance.en, 'hi': instance.hi};

_PhraseMatch _$PhraseMatchFromJson(Map<String, dynamic> json) => _PhraseMatch(
  phrase: json['phrase'] as String,
  lemma: json['lemma'] as String,
  start: (json['start'] as num).toInt(),
  tokenCount: (json['tokenCount'] as num).toInt(),
);

Map<String, dynamic> _$PhraseMatchToJson(_PhraseMatch instance) =>
    <String, dynamic>{
      'phrase': instance.phrase,
      'lemma': instance.lemma,
      'start': instance.start,
      'tokenCount': instance.tokenCount,
    };

_ApiError _$ApiErrorFromJson(Map<String, dynamic> json) => _ApiError(
  code: $enumDecode(_$ApiErrorCodeEnumMap, json['code']),
  message: json['message'] as String,
  suggestions: (json['suggestions'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$ApiErrorToJson(_ApiError instance) => <String, dynamic>{
  'code': _$ApiErrorCodeEnumMap[instance.code]!,
  'message': instance.message,
  'suggestions': instance.suggestions,
};

const _$ApiErrorCodeEnumMap = {
  ApiErrorCode.notFound: 'NOT_FOUND',
  ApiErrorCode.badRequest: 'BAD_REQUEST',
  ApiErrorCode.rateLimited: 'RATE_LIMITED',
  ApiErrorCode.upstreamFailed: 'UPSTREAM_FAILED',
  ApiErrorCode.internal: 'INTERNAL',
};
