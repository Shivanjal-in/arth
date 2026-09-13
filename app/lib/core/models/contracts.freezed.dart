// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'contracts.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DictionaryEntry {

 String get word; String get ipa; String get hindiPronunciation; List<Sense> get senses; List<BilingualPair> get synonyms; List<BilingualPair> get antonyms; List<WordForm> get forms; bool get isPhrase;
/// Create a copy of DictionaryEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DictionaryEntryCopyWith<DictionaryEntry> get copyWith => _$DictionaryEntryCopyWithImpl<DictionaryEntry>(this as DictionaryEntry, _$identity);

  /// Serializes this DictionaryEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DictionaryEntry&&(identical(other.word, word) || other.word == word)&&(identical(other.ipa, ipa) || other.ipa == ipa)&&(identical(other.hindiPronunciation, hindiPronunciation) || other.hindiPronunciation == hindiPronunciation)&&const DeepCollectionEquality().equals(other.senses, senses)&&const DeepCollectionEquality().equals(other.synonyms, synonyms)&&const DeepCollectionEquality().equals(other.antonyms, antonyms)&&const DeepCollectionEquality().equals(other.forms, forms)&&(identical(other.isPhrase, isPhrase) || other.isPhrase == isPhrase));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,word,ipa,hindiPronunciation,const DeepCollectionEquality().hash(senses),const DeepCollectionEquality().hash(synonyms),const DeepCollectionEquality().hash(antonyms),const DeepCollectionEquality().hash(forms),isPhrase);

@override
String toString() {
  return 'DictionaryEntry(word: $word, ipa: $ipa, hindiPronunciation: $hindiPronunciation, senses: $senses, synonyms: $synonyms, antonyms: $antonyms, forms: $forms, isPhrase: $isPhrase)';
}


}

/// @nodoc
abstract mixin class $DictionaryEntryCopyWith<$Res>  {
  factory $DictionaryEntryCopyWith(DictionaryEntry value, $Res Function(DictionaryEntry) _then) = _$DictionaryEntryCopyWithImpl;
@useResult
$Res call({
 String word, String ipa, String hindiPronunciation, List<Sense> senses, List<BilingualPair> synonyms, List<BilingualPair> antonyms, List<WordForm> forms, bool isPhrase
});




}
/// @nodoc
class _$DictionaryEntryCopyWithImpl<$Res>
    implements $DictionaryEntryCopyWith<$Res> {
  _$DictionaryEntryCopyWithImpl(this._self, this._then);

  final DictionaryEntry _self;
  final $Res Function(DictionaryEntry) _then;

/// Create a copy of DictionaryEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? word = null,Object? ipa = null,Object? hindiPronunciation = null,Object? senses = null,Object? synonyms = null,Object? antonyms = null,Object? forms = null,Object? isPhrase = null,}) {
  return _then(_self.copyWith(
word: null == word ? _self.word : word // ignore: cast_nullable_to_non_nullable
as String,ipa: null == ipa ? _self.ipa : ipa // ignore: cast_nullable_to_non_nullable
as String,hindiPronunciation: null == hindiPronunciation ? _self.hindiPronunciation : hindiPronunciation // ignore: cast_nullable_to_non_nullable
as String,senses: null == senses ? _self.senses : senses // ignore: cast_nullable_to_non_nullable
as List<Sense>,synonyms: null == synonyms ? _self.synonyms : synonyms // ignore: cast_nullable_to_non_nullable
as List<BilingualPair>,antonyms: null == antonyms ? _self.antonyms : antonyms // ignore: cast_nullable_to_non_nullable
as List<BilingualPair>,forms: null == forms ? _self.forms : forms // ignore: cast_nullable_to_non_nullable
as List<WordForm>,isPhrase: null == isPhrase ? _self.isPhrase : isPhrase // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DictionaryEntry].
extension DictionaryEntryPatterns on DictionaryEntry {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DictionaryEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DictionaryEntry() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DictionaryEntry value)  $default,){
final _that = this;
switch (_that) {
case _DictionaryEntry():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DictionaryEntry value)?  $default,){
final _that = this;
switch (_that) {
case _DictionaryEntry() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String word,  String ipa,  String hindiPronunciation,  List<Sense> senses,  List<BilingualPair> synonyms,  List<BilingualPair> antonyms,  List<WordForm> forms,  bool isPhrase)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DictionaryEntry() when $default != null:
return $default(_that.word,_that.ipa,_that.hindiPronunciation,_that.senses,_that.synonyms,_that.antonyms,_that.forms,_that.isPhrase);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String word,  String ipa,  String hindiPronunciation,  List<Sense> senses,  List<BilingualPair> synonyms,  List<BilingualPair> antonyms,  List<WordForm> forms,  bool isPhrase)  $default,) {final _that = this;
switch (_that) {
case _DictionaryEntry():
return $default(_that.word,_that.ipa,_that.hindiPronunciation,_that.senses,_that.synonyms,_that.antonyms,_that.forms,_that.isPhrase);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String word,  String ipa,  String hindiPronunciation,  List<Sense> senses,  List<BilingualPair> synonyms,  List<BilingualPair> antonyms,  List<WordForm> forms,  bool isPhrase)?  $default,) {final _that = this;
switch (_that) {
case _DictionaryEntry() when $default != null:
return $default(_that.word,_that.ipa,_that.hindiPronunciation,_that.senses,_that.synonyms,_that.antonyms,_that.forms,_that.isPhrase);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DictionaryEntry implements DictionaryEntry {
  const _DictionaryEntry({required this.word, required this.ipa, required this.hindiPronunciation, required final  List<Sense> senses, required final  List<BilingualPair> synonyms, required final  List<BilingualPair> antonyms, required final  List<WordForm> forms, required this.isPhrase}): _senses = senses,_synonyms = synonyms,_antonyms = antonyms,_forms = forms;
  factory _DictionaryEntry.fromJson(Map<String, dynamic> json) => _$DictionaryEntryFromJson(json);

@override final  String word;
@override final  String ipa;
@override final  String hindiPronunciation;
 final  List<Sense> _senses;
@override List<Sense> get senses {
  if (_senses is EqualUnmodifiableListView) return _senses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_senses);
}

 final  List<BilingualPair> _synonyms;
@override List<BilingualPair> get synonyms {
  if (_synonyms is EqualUnmodifiableListView) return _synonyms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_synonyms);
}

 final  List<BilingualPair> _antonyms;
@override List<BilingualPair> get antonyms {
  if (_antonyms is EqualUnmodifiableListView) return _antonyms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_antonyms);
}

 final  List<WordForm> _forms;
@override List<WordForm> get forms {
  if (_forms is EqualUnmodifiableListView) return _forms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_forms);
}

@override final  bool isPhrase;

/// Create a copy of DictionaryEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DictionaryEntryCopyWith<_DictionaryEntry> get copyWith => __$DictionaryEntryCopyWithImpl<_DictionaryEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DictionaryEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DictionaryEntry&&(identical(other.word, word) || other.word == word)&&(identical(other.ipa, ipa) || other.ipa == ipa)&&(identical(other.hindiPronunciation, hindiPronunciation) || other.hindiPronunciation == hindiPronunciation)&&const DeepCollectionEquality().equals(other._senses, _senses)&&const DeepCollectionEquality().equals(other._synonyms, _synonyms)&&const DeepCollectionEquality().equals(other._antonyms, _antonyms)&&const DeepCollectionEquality().equals(other._forms, _forms)&&(identical(other.isPhrase, isPhrase) || other.isPhrase == isPhrase));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,word,ipa,hindiPronunciation,const DeepCollectionEquality().hash(_senses),const DeepCollectionEquality().hash(_synonyms),const DeepCollectionEquality().hash(_antonyms),const DeepCollectionEquality().hash(_forms),isPhrase);

@override
String toString() {
  return 'DictionaryEntry(word: $word, ipa: $ipa, hindiPronunciation: $hindiPronunciation, senses: $senses, synonyms: $synonyms, antonyms: $antonyms, forms: $forms, isPhrase: $isPhrase)';
}


}

/// @nodoc
abstract mixin class _$DictionaryEntryCopyWith<$Res> implements $DictionaryEntryCopyWith<$Res> {
  factory _$DictionaryEntryCopyWith(_DictionaryEntry value, $Res Function(_DictionaryEntry) _then) = __$DictionaryEntryCopyWithImpl;
@override @useResult
$Res call({
 String word, String ipa, String hindiPronunciation, List<Sense> senses, List<BilingualPair> synonyms, List<BilingualPair> antonyms, List<WordForm> forms, bool isPhrase
});




}
/// @nodoc
class __$DictionaryEntryCopyWithImpl<$Res>
    implements _$DictionaryEntryCopyWith<$Res> {
  __$DictionaryEntryCopyWithImpl(this._self, this._then);

  final _DictionaryEntry _self;
  final $Res Function(_DictionaryEntry) _then;

/// Create a copy of DictionaryEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? word = null,Object? ipa = null,Object? hindiPronunciation = null,Object? senses = null,Object? synonyms = null,Object? antonyms = null,Object? forms = null,Object? isPhrase = null,}) {
  return _then(_DictionaryEntry(
word: null == word ? _self.word : word // ignore: cast_nullable_to_non_nullable
as String,ipa: null == ipa ? _self.ipa : ipa // ignore: cast_nullable_to_non_nullable
as String,hindiPronunciation: null == hindiPronunciation ? _self.hindiPronunciation : hindiPronunciation // ignore: cast_nullable_to_non_nullable
as String,senses: null == senses ? _self._senses : senses // ignore: cast_nullable_to_non_nullable
as List<Sense>,synonyms: null == synonyms ? _self._synonyms : synonyms // ignore: cast_nullable_to_non_nullable
as List<BilingualPair>,antonyms: null == antonyms ? _self._antonyms : antonyms // ignore: cast_nullable_to_non_nullable
as List<BilingualPair>,forms: null == forms ? _self._forms : forms // ignore: cast_nullable_to_non_nullable
as List<WordForm>,isPhrase: null == isPhrase ? _self.isPhrase : isPhrase // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$Sense {

 int get index; String get partOfSpeech; String get meaning; String get definition; List<BilingualPair> get examples;
/// Create a copy of Sense
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SenseCopyWith<Sense> get copyWith => _$SenseCopyWithImpl<Sense>(this as Sense, _$identity);

  /// Serializes this Sense to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Sense&&(identical(other.index, index) || other.index == index)&&(identical(other.partOfSpeech, partOfSpeech) || other.partOfSpeech == partOfSpeech)&&(identical(other.meaning, meaning) || other.meaning == meaning)&&(identical(other.definition, definition) || other.definition == definition)&&const DeepCollectionEquality().equals(other.examples, examples));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,index,partOfSpeech,meaning,definition,const DeepCollectionEquality().hash(examples));

@override
String toString() {
  return 'Sense(index: $index, partOfSpeech: $partOfSpeech, meaning: $meaning, definition: $definition, examples: $examples)';
}


}

/// @nodoc
abstract mixin class $SenseCopyWith<$Res>  {
  factory $SenseCopyWith(Sense value, $Res Function(Sense) _then) = _$SenseCopyWithImpl;
@useResult
$Res call({
 int index, String partOfSpeech, String meaning, String definition, List<BilingualPair> examples
});




}
/// @nodoc
class _$SenseCopyWithImpl<$Res>
    implements $SenseCopyWith<$Res> {
  _$SenseCopyWithImpl(this._self, this._then);

  final Sense _self;
  final $Res Function(Sense) _then;

/// Create a copy of Sense
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? partOfSpeech = null,Object? meaning = null,Object? definition = null,Object? examples = null,}) {
  return _then(_self.copyWith(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,partOfSpeech: null == partOfSpeech ? _self.partOfSpeech : partOfSpeech // ignore: cast_nullable_to_non_nullable
as String,meaning: null == meaning ? _self.meaning : meaning // ignore: cast_nullable_to_non_nullable
as String,definition: null == definition ? _self.definition : definition // ignore: cast_nullable_to_non_nullable
as String,examples: null == examples ? _self.examples : examples // ignore: cast_nullable_to_non_nullable
as List<BilingualPair>,
  ));
}

}


/// Adds pattern-matching-related methods to [Sense].
extension SensePatterns on Sense {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Sense value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Sense() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Sense value)  $default,){
final _that = this;
switch (_that) {
case _Sense():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Sense value)?  $default,){
final _that = this;
switch (_that) {
case _Sense() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int index,  String partOfSpeech,  String meaning,  String definition,  List<BilingualPair> examples)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Sense() when $default != null:
return $default(_that.index,_that.partOfSpeech,_that.meaning,_that.definition,_that.examples);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int index,  String partOfSpeech,  String meaning,  String definition,  List<BilingualPair> examples)  $default,) {final _that = this;
switch (_that) {
case _Sense():
return $default(_that.index,_that.partOfSpeech,_that.meaning,_that.definition,_that.examples);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int index,  String partOfSpeech,  String meaning,  String definition,  List<BilingualPair> examples)?  $default,) {final _that = this;
switch (_that) {
case _Sense() when $default != null:
return $default(_that.index,_that.partOfSpeech,_that.meaning,_that.definition,_that.examples);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Sense implements Sense {
  const _Sense({required this.index, required this.partOfSpeech, required this.meaning, required this.definition, required final  List<BilingualPair> examples}): _examples = examples;
  factory _Sense.fromJson(Map<String, dynamic> json) => _$SenseFromJson(json);

@override final  int index;
@override final  String partOfSpeech;
@override final  String meaning;
@override final  String definition;
 final  List<BilingualPair> _examples;
@override List<BilingualPair> get examples {
  if (_examples is EqualUnmodifiableListView) return _examples;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_examples);
}


/// Create a copy of Sense
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SenseCopyWith<_Sense> get copyWith => __$SenseCopyWithImpl<_Sense>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SenseToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Sense&&(identical(other.index, index) || other.index == index)&&(identical(other.partOfSpeech, partOfSpeech) || other.partOfSpeech == partOfSpeech)&&(identical(other.meaning, meaning) || other.meaning == meaning)&&(identical(other.definition, definition) || other.definition == definition)&&const DeepCollectionEquality().equals(other._examples, _examples));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,index,partOfSpeech,meaning,definition,const DeepCollectionEquality().hash(_examples));

@override
String toString() {
  return 'Sense(index: $index, partOfSpeech: $partOfSpeech, meaning: $meaning, definition: $definition, examples: $examples)';
}


}

/// @nodoc
abstract mixin class _$SenseCopyWith<$Res> implements $SenseCopyWith<$Res> {
  factory _$SenseCopyWith(_Sense value, $Res Function(_Sense) _then) = __$SenseCopyWithImpl;
@override @useResult
$Res call({
 int index, String partOfSpeech, String meaning, String definition, List<BilingualPair> examples
});




}
/// @nodoc
class __$SenseCopyWithImpl<$Res>
    implements _$SenseCopyWith<$Res> {
  __$SenseCopyWithImpl(this._self, this._then);

  final _Sense _self;
  final $Res Function(_Sense) _then;

/// Create a copy of Sense
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? partOfSpeech = null,Object? meaning = null,Object? definition = null,Object? examples = null,}) {
  return _then(_Sense(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,partOfSpeech: null == partOfSpeech ? _self.partOfSpeech : partOfSpeech // ignore: cast_nullable_to_non_nullable
as String,meaning: null == meaning ? _self.meaning : meaning // ignore: cast_nullable_to_non_nullable
as String,definition: null == definition ? _self.definition : definition // ignore: cast_nullable_to_non_nullable
as String,examples: null == examples ? _self._examples : examples // ignore: cast_nullable_to_non_nullable
as List<BilingualPair>,
  ));
}


}


/// @nodoc
mixin _$BilingualPair {

 String get en; String get hi;
/// Create a copy of BilingualPair
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BilingualPairCopyWith<BilingualPair> get copyWith => _$BilingualPairCopyWithImpl<BilingualPair>(this as BilingualPair, _$identity);

  /// Serializes this BilingualPair to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BilingualPair&&(identical(other.en, en) || other.en == en)&&(identical(other.hi, hi) || other.hi == hi));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,en,hi);

@override
String toString() {
  return 'BilingualPair(en: $en, hi: $hi)';
}


}

/// @nodoc
abstract mixin class $BilingualPairCopyWith<$Res>  {
  factory $BilingualPairCopyWith(BilingualPair value, $Res Function(BilingualPair) _then) = _$BilingualPairCopyWithImpl;
@useResult
$Res call({
 String en, String hi
});




}
/// @nodoc
class _$BilingualPairCopyWithImpl<$Res>
    implements $BilingualPairCopyWith<$Res> {
  _$BilingualPairCopyWithImpl(this._self, this._then);

  final BilingualPair _self;
  final $Res Function(BilingualPair) _then;

/// Create a copy of BilingualPair
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? en = null,Object? hi = null,}) {
  return _then(_self.copyWith(
en: null == en ? _self.en : en // ignore: cast_nullable_to_non_nullable
as String,hi: null == hi ? _self.hi : hi // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BilingualPair].
extension BilingualPairPatterns on BilingualPair {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BilingualPair value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BilingualPair() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BilingualPair value)  $default,){
final _that = this;
switch (_that) {
case _BilingualPair():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BilingualPair value)?  $default,){
final _that = this;
switch (_that) {
case _BilingualPair() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String en,  String hi)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BilingualPair() when $default != null:
return $default(_that.en,_that.hi);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String en,  String hi)  $default,) {final _that = this;
switch (_that) {
case _BilingualPair():
return $default(_that.en,_that.hi);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String en,  String hi)?  $default,) {final _that = this;
switch (_that) {
case _BilingualPair() when $default != null:
return $default(_that.en,_that.hi);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BilingualPair implements BilingualPair {
  const _BilingualPair({required this.en, required this.hi});
  factory _BilingualPair.fromJson(Map<String, dynamic> json) => _$BilingualPairFromJson(json);

@override final  String en;
@override final  String hi;

/// Create a copy of BilingualPair
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BilingualPairCopyWith<_BilingualPair> get copyWith => __$BilingualPairCopyWithImpl<_BilingualPair>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BilingualPairToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BilingualPair&&(identical(other.en, en) || other.en == en)&&(identical(other.hi, hi) || other.hi == hi));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,en,hi);

@override
String toString() {
  return 'BilingualPair(en: $en, hi: $hi)';
}


}

/// @nodoc
abstract mixin class _$BilingualPairCopyWith<$Res> implements $BilingualPairCopyWith<$Res> {
  factory _$BilingualPairCopyWith(_BilingualPair value, $Res Function(_BilingualPair) _then) = __$BilingualPairCopyWithImpl;
@override @useResult
$Res call({
 String en, String hi
});




}
/// @nodoc
class __$BilingualPairCopyWithImpl<$Res>
    implements _$BilingualPairCopyWith<$Res> {
  __$BilingualPairCopyWithImpl(this._self, this._then);

  final _BilingualPair _self;
  final $Res Function(_BilingualPair) _then;

/// Create a copy of BilingualPair
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? en = null,Object? hi = null,}) {
  return _then(_BilingualPair(
en: null == en ? _self.en : en // ignore: cast_nullable_to_non_nullable
as String,hi: null == hi ? _self.hi : hi // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$WordForm {

 String get en; String get label; String get hi;
/// Create a copy of WordForm
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WordFormCopyWith<WordForm> get copyWith => _$WordFormCopyWithImpl<WordForm>(this as WordForm, _$identity);

  /// Serializes this WordForm to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WordForm&&(identical(other.en, en) || other.en == en)&&(identical(other.label, label) || other.label == label)&&(identical(other.hi, hi) || other.hi == hi));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,en,label,hi);

@override
String toString() {
  return 'WordForm(en: $en, label: $label, hi: $hi)';
}


}

/// @nodoc
abstract mixin class $WordFormCopyWith<$Res>  {
  factory $WordFormCopyWith(WordForm value, $Res Function(WordForm) _then) = _$WordFormCopyWithImpl;
@useResult
$Res call({
 String en, String label, String hi
});




}
/// @nodoc
class _$WordFormCopyWithImpl<$Res>
    implements $WordFormCopyWith<$Res> {
  _$WordFormCopyWithImpl(this._self, this._then);

  final WordForm _self;
  final $Res Function(WordForm) _then;

/// Create a copy of WordForm
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? en = null,Object? label = null,Object? hi = null,}) {
  return _then(_self.copyWith(
en: null == en ? _self.en : en // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,hi: null == hi ? _self.hi : hi // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [WordForm].
extension WordFormPatterns on WordForm {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WordForm value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WordForm() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WordForm value)  $default,){
final _that = this;
switch (_that) {
case _WordForm():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WordForm value)?  $default,){
final _that = this;
switch (_that) {
case _WordForm() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String en,  String label,  String hi)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WordForm() when $default != null:
return $default(_that.en,_that.label,_that.hi);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String en,  String label,  String hi)  $default,) {final _that = this;
switch (_that) {
case _WordForm():
return $default(_that.en,_that.label,_that.hi);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String en,  String label,  String hi)?  $default,) {final _that = this;
switch (_that) {
case _WordForm() when $default != null:
return $default(_that.en,_that.label,_that.hi);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WordForm implements WordForm {
  const _WordForm({required this.en, required this.label, required this.hi});
  factory _WordForm.fromJson(Map<String, dynamic> json) => _$WordFormFromJson(json);

@override final  String en;
@override final  String label;
@override final  String hi;

/// Create a copy of WordForm
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WordFormCopyWith<_WordForm> get copyWith => __$WordFormCopyWithImpl<_WordForm>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WordFormToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WordForm&&(identical(other.en, en) || other.en == en)&&(identical(other.label, label) || other.label == label)&&(identical(other.hi, hi) || other.hi == hi));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,en,label,hi);

@override
String toString() {
  return 'WordForm(en: $en, label: $label, hi: $hi)';
}


}

/// @nodoc
abstract mixin class _$WordFormCopyWith<$Res> implements $WordFormCopyWith<$Res> {
  factory _$WordFormCopyWith(_WordForm value, $Res Function(_WordForm) _then) = __$WordFormCopyWithImpl;
@override @useResult
$Res call({
 String en, String label, String hi
});




}
/// @nodoc
class __$WordFormCopyWithImpl<$Res>
    implements _$WordFormCopyWith<$Res> {
  __$WordFormCopyWithImpl(this._self, this._then);

  final _WordForm _self;
  final $Res Function(_WordForm) _then;

/// Create a copy of WordForm
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? en = null,Object? label = null,Object? hi = null,}) {
  return _then(_WordForm(
en: null == en ? _self.en : en // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,hi: null == hi ? _self.hi : hi // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ContextResult {

 int get senseIndex; String get meaning; String get note;
/// Create a copy of ContextResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContextResultCopyWith<ContextResult> get copyWith => _$ContextResultCopyWithImpl<ContextResult>(this as ContextResult, _$identity);

  /// Serializes this ContextResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContextResult&&(identical(other.senseIndex, senseIndex) || other.senseIndex == senseIndex)&&(identical(other.meaning, meaning) || other.meaning == meaning)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,senseIndex,meaning,note);

@override
String toString() {
  return 'ContextResult(senseIndex: $senseIndex, meaning: $meaning, note: $note)';
}


}

/// @nodoc
abstract mixin class $ContextResultCopyWith<$Res>  {
  factory $ContextResultCopyWith(ContextResult value, $Res Function(ContextResult) _then) = _$ContextResultCopyWithImpl;
@useResult
$Res call({
 int senseIndex, String meaning, String note
});




}
/// @nodoc
class _$ContextResultCopyWithImpl<$Res>
    implements $ContextResultCopyWith<$Res> {
  _$ContextResultCopyWithImpl(this._self, this._then);

  final ContextResult _self;
  final $Res Function(ContextResult) _then;

/// Create a copy of ContextResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? senseIndex = null,Object? meaning = null,Object? note = null,}) {
  return _then(_self.copyWith(
senseIndex: null == senseIndex ? _self.senseIndex : senseIndex // ignore: cast_nullable_to_non_nullable
as int,meaning: null == meaning ? _self.meaning : meaning // ignore: cast_nullable_to_non_nullable
as String,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ContextResult].
extension ContextResultPatterns on ContextResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContextResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContextResult() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContextResult value)  $default,){
final _that = this;
switch (_that) {
case _ContextResult():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContextResult value)?  $default,){
final _that = this;
switch (_that) {
case _ContextResult() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int senseIndex,  String meaning,  String note)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContextResult() when $default != null:
return $default(_that.senseIndex,_that.meaning,_that.note);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int senseIndex,  String meaning,  String note)  $default,) {final _that = this;
switch (_that) {
case _ContextResult():
return $default(_that.senseIndex,_that.meaning,_that.note);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int senseIndex,  String meaning,  String note)?  $default,) {final _that = this;
switch (_that) {
case _ContextResult() when $default != null:
return $default(_that.senseIndex,_that.meaning,_that.note);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ContextResult implements ContextResult {
  const _ContextResult({required this.senseIndex, required this.meaning, required this.note});
  factory _ContextResult.fromJson(Map<String, dynamic> json) => _$ContextResultFromJson(json);

@override final  int senseIndex;
@override final  String meaning;
@override final  String note;

/// Create a copy of ContextResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContextResultCopyWith<_ContextResult> get copyWith => __$ContextResultCopyWithImpl<_ContextResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ContextResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContextResult&&(identical(other.senseIndex, senseIndex) || other.senseIndex == senseIndex)&&(identical(other.meaning, meaning) || other.meaning == meaning)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,senseIndex,meaning,note);

@override
String toString() {
  return 'ContextResult(senseIndex: $senseIndex, meaning: $meaning, note: $note)';
}


}

/// @nodoc
abstract mixin class _$ContextResultCopyWith<$Res> implements $ContextResultCopyWith<$Res> {
  factory _$ContextResultCopyWith(_ContextResult value, $Res Function(_ContextResult) _then) = __$ContextResultCopyWithImpl;
@override @useResult
$Res call({
 int senseIndex, String meaning, String note
});




}
/// @nodoc
class __$ContextResultCopyWithImpl<$Res>
    implements _$ContextResultCopyWith<$Res> {
  __$ContextResultCopyWithImpl(this._self, this._then);

  final _ContextResult _self;
  final $Res Function(_ContextResult) _then;

/// Create a copy of ContextResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? senseIndex = null,Object? meaning = null,Object? note = null,}) {
  return _then(_ContextResult(
senseIndex: null == senseIndex ? _self.senseIndex : senseIndex // ignore: cast_nullable_to_non_nullable
as int,meaning: null == meaning ? _self.meaning : meaning // ignore: cast_nullable_to_non_nullable
as String,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$TranslationResult {

 String get source; String get hindi; String get simpleMeaning; List<TranslationResultDifficultWords> get difficultWords;
/// Create a copy of TranslationResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslationResultCopyWith<TranslationResult> get copyWith => _$TranslationResultCopyWithImpl<TranslationResult>(this as TranslationResult, _$identity);

  /// Serializes this TranslationResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslationResult&&(identical(other.source, source) || other.source == source)&&(identical(other.hindi, hindi) || other.hindi == hindi)&&(identical(other.simpleMeaning, simpleMeaning) || other.simpleMeaning == simpleMeaning)&&const DeepCollectionEquality().equals(other.difficultWords, difficultWords));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,source,hindi,simpleMeaning,const DeepCollectionEquality().hash(difficultWords));

@override
String toString() {
  return 'TranslationResult(source: $source, hindi: $hindi, simpleMeaning: $simpleMeaning, difficultWords: $difficultWords)';
}


}

/// @nodoc
abstract mixin class $TranslationResultCopyWith<$Res>  {
  factory $TranslationResultCopyWith(TranslationResult value, $Res Function(TranslationResult) _then) = _$TranslationResultCopyWithImpl;
@useResult
$Res call({
 String source, String hindi, String simpleMeaning, List<TranslationResultDifficultWords> difficultWords
});




}
/// @nodoc
class _$TranslationResultCopyWithImpl<$Res>
    implements $TranslationResultCopyWith<$Res> {
  _$TranslationResultCopyWithImpl(this._self, this._then);

  final TranslationResult _self;
  final $Res Function(TranslationResult) _then;

/// Create a copy of TranslationResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? hindi = null,Object? simpleMeaning = null,Object? difficultWords = null,}) {
  return _then(_self.copyWith(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,hindi: null == hindi ? _self.hindi : hindi // ignore: cast_nullable_to_non_nullable
as String,simpleMeaning: null == simpleMeaning ? _self.simpleMeaning : simpleMeaning // ignore: cast_nullable_to_non_nullable
as String,difficultWords: null == difficultWords ? _self.difficultWords : difficultWords // ignore: cast_nullable_to_non_nullable
as List<TranslationResultDifficultWords>,
  ));
}

}


/// Adds pattern-matching-related methods to [TranslationResult].
extension TranslationResultPatterns on TranslationResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TranslationResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TranslationResult() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TranslationResult value)  $default,){
final _that = this;
switch (_that) {
case _TranslationResult():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TranslationResult value)?  $default,){
final _that = this;
switch (_that) {
case _TranslationResult() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String source,  String hindi,  String simpleMeaning,  List<TranslationResultDifficultWords> difficultWords)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TranslationResult() when $default != null:
return $default(_that.source,_that.hindi,_that.simpleMeaning,_that.difficultWords);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String source,  String hindi,  String simpleMeaning,  List<TranslationResultDifficultWords> difficultWords)  $default,) {final _that = this;
switch (_that) {
case _TranslationResult():
return $default(_that.source,_that.hindi,_that.simpleMeaning,_that.difficultWords);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String source,  String hindi,  String simpleMeaning,  List<TranslationResultDifficultWords> difficultWords)?  $default,) {final _that = this;
switch (_that) {
case _TranslationResult() when $default != null:
return $default(_that.source,_that.hindi,_that.simpleMeaning,_that.difficultWords);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TranslationResult implements TranslationResult {
  const _TranslationResult({required this.source, required this.hindi, required this.simpleMeaning, required final  List<TranslationResultDifficultWords> difficultWords}): _difficultWords = difficultWords;
  factory _TranslationResult.fromJson(Map<String, dynamic> json) => _$TranslationResultFromJson(json);

@override final  String source;
@override final  String hindi;
@override final  String simpleMeaning;
 final  List<TranslationResultDifficultWords> _difficultWords;
@override List<TranslationResultDifficultWords> get difficultWords {
  if (_difficultWords is EqualUnmodifiableListView) return _difficultWords;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_difficultWords);
}


/// Create a copy of TranslationResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TranslationResultCopyWith<_TranslationResult> get copyWith => __$TranslationResultCopyWithImpl<_TranslationResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TranslationResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TranslationResult&&(identical(other.source, source) || other.source == source)&&(identical(other.hindi, hindi) || other.hindi == hindi)&&(identical(other.simpleMeaning, simpleMeaning) || other.simpleMeaning == simpleMeaning)&&const DeepCollectionEquality().equals(other._difficultWords, _difficultWords));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,source,hindi,simpleMeaning,const DeepCollectionEquality().hash(_difficultWords));

@override
String toString() {
  return 'TranslationResult(source: $source, hindi: $hindi, simpleMeaning: $simpleMeaning, difficultWords: $difficultWords)';
}


}

/// @nodoc
abstract mixin class _$TranslationResultCopyWith<$Res> implements $TranslationResultCopyWith<$Res> {
  factory _$TranslationResultCopyWith(_TranslationResult value, $Res Function(_TranslationResult) _then) = __$TranslationResultCopyWithImpl;
@override @useResult
$Res call({
 String source, String hindi, String simpleMeaning, List<TranslationResultDifficultWords> difficultWords
});




}
/// @nodoc
class __$TranslationResultCopyWithImpl<$Res>
    implements _$TranslationResultCopyWith<$Res> {
  __$TranslationResultCopyWithImpl(this._self, this._then);

  final _TranslationResult _self;
  final $Res Function(_TranslationResult) _then;

/// Create a copy of TranslationResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? hindi = null,Object? simpleMeaning = null,Object? difficultWords = null,}) {
  return _then(_TranslationResult(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,hindi: null == hindi ? _self.hindi : hindi // ignore: cast_nullable_to_non_nullable
as String,simpleMeaning: null == simpleMeaning ? _self.simpleMeaning : simpleMeaning // ignore: cast_nullable_to_non_nullable
as String,difficultWords: null == difficultWords ? _self._difficultWords : difficultWords // ignore: cast_nullable_to_non_nullable
as List<TranslationResultDifficultWords>,
  ));
}


}


/// @nodoc
mixin _$TranslationResultDifficultWords {

 String get en; String get hi;
/// Create a copy of TranslationResultDifficultWords
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslationResultDifficultWordsCopyWith<TranslationResultDifficultWords> get copyWith => _$TranslationResultDifficultWordsCopyWithImpl<TranslationResultDifficultWords>(this as TranslationResultDifficultWords, _$identity);

  /// Serializes this TranslationResultDifficultWords to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslationResultDifficultWords&&(identical(other.en, en) || other.en == en)&&(identical(other.hi, hi) || other.hi == hi));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,en,hi);

@override
String toString() {
  return 'TranslationResultDifficultWords(en: $en, hi: $hi)';
}


}

/// @nodoc
abstract mixin class $TranslationResultDifficultWordsCopyWith<$Res>  {
  factory $TranslationResultDifficultWordsCopyWith(TranslationResultDifficultWords value, $Res Function(TranslationResultDifficultWords) _then) = _$TranslationResultDifficultWordsCopyWithImpl;
@useResult
$Res call({
 String en, String hi
});




}
/// @nodoc
class _$TranslationResultDifficultWordsCopyWithImpl<$Res>
    implements $TranslationResultDifficultWordsCopyWith<$Res> {
  _$TranslationResultDifficultWordsCopyWithImpl(this._self, this._then);

  final TranslationResultDifficultWords _self;
  final $Res Function(TranslationResultDifficultWords) _then;

/// Create a copy of TranslationResultDifficultWords
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? en = null,Object? hi = null,}) {
  return _then(_self.copyWith(
en: null == en ? _self.en : en // ignore: cast_nullable_to_non_nullable
as String,hi: null == hi ? _self.hi : hi // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TranslationResultDifficultWords].
extension TranslationResultDifficultWordsPatterns on TranslationResultDifficultWords {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TranslationResultDifficultWords value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TranslationResultDifficultWords() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TranslationResultDifficultWords value)  $default,){
final _that = this;
switch (_that) {
case _TranslationResultDifficultWords():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TranslationResultDifficultWords value)?  $default,){
final _that = this;
switch (_that) {
case _TranslationResultDifficultWords() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String en,  String hi)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TranslationResultDifficultWords() when $default != null:
return $default(_that.en,_that.hi);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String en,  String hi)  $default,) {final _that = this;
switch (_that) {
case _TranslationResultDifficultWords():
return $default(_that.en,_that.hi);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String en,  String hi)?  $default,) {final _that = this;
switch (_that) {
case _TranslationResultDifficultWords() when $default != null:
return $default(_that.en,_that.hi);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TranslationResultDifficultWords implements TranslationResultDifficultWords {
  const _TranslationResultDifficultWords({required this.en, required this.hi});
  factory _TranslationResultDifficultWords.fromJson(Map<String, dynamic> json) => _$TranslationResultDifficultWordsFromJson(json);

@override final  String en;
@override final  String hi;

/// Create a copy of TranslationResultDifficultWords
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TranslationResultDifficultWordsCopyWith<_TranslationResultDifficultWords> get copyWith => __$TranslationResultDifficultWordsCopyWithImpl<_TranslationResultDifficultWords>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TranslationResultDifficultWordsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TranslationResultDifficultWords&&(identical(other.en, en) || other.en == en)&&(identical(other.hi, hi) || other.hi == hi));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,en,hi);

@override
String toString() {
  return 'TranslationResultDifficultWords(en: $en, hi: $hi)';
}


}

/// @nodoc
abstract mixin class _$TranslationResultDifficultWordsCopyWith<$Res> implements $TranslationResultDifficultWordsCopyWith<$Res> {
  factory _$TranslationResultDifficultWordsCopyWith(_TranslationResultDifficultWords value, $Res Function(_TranslationResultDifficultWords) _then) = __$TranslationResultDifficultWordsCopyWithImpl;
@override @useResult
$Res call({
 String en, String hi
});




}
/// @nodoc
class __$TranslationResultDifficultWordsCopyWithImpl<$Res>
    implements _$TranslationResultDifficultWordsCopyWith<$Res> {
  __$TranslationResultDifficultWordsCopyWithImpl(this._self, this._then);

  final _TranslationResultDifficultWords _self;
  final $Res Function(_TranslationResultDifficultWords) _then;

/// Create a copy of TranslationResultDifficultWords
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? en = null,Object? hi = null,}) {
  return _then(_TranslationResultDifficultWords(
en: null == en ? _self.en : en // ignore: cast_nullable_to_non_nullable
as String,hi: null == hi ? _self.hi : hi // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$PhraseMatch {

 String get phrase; String get lemma; int get start; int get tokenCount;
/// Create a copy of PhraseMatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PhraseMatchCopyWith<PhraseMatch> get copyWith => _$PhraseMatchCopyWithImpl<PhraseMatch>(this as PhraseMatch, _$identity);

  /// Serializes this PhraseMatch to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PhraseMatch&&(identical(other.phrase, phrase) || other.phrase == phrase)&&(identical(other.lemma, lemma) || other.lemma == lemma)&&(identical(other.start, start) || other.start == start)&&(identical(other.tokenCount, tokenCount) || other.tokenCount == tokenCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,phrase,lemma,start,tokenCount);

@override
String toString() {
  return 'PhraseMatch(phrase: $phrase, lemma: $lemma, start: $start, tokenCount: $tokenCount)';
}


}

/// @nodoc
abstract mixin class $PhraseMatchCopyWith<$Res>  {
  factory $PhraseMatchCopyWith(PhraseMatch value, $Res Function(PhraseMatch) _then) = _$PhraseMatchCopyWithImpl;
@useResult
$Res call({
 String phrase, String lemma, int start, int tokenCount
});




}
/// @nodoc
class _$PhraseMatchCopyWithImpl<$Res>
    implements $PhraseMatchCopyWith<$Res> {
  _$PhraseMatchCopyWithImpl(this._self, this._then);

  final PhraseMatch _self;
  final $Res Function(PhraseMatch) _then;

/// Create a copy of PhraseMatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phrase = null,Object? lemma = null,Object? start = null,Object? tokenCount = null,}) {
  return _then(_self.copyWith(
phrase: null == phrase ? _self.phrase : phrase // ignore: cast_nullable_to_non_nullable
as String,lemma: null == lemma ? _self.lemma : lemma // ignore: cast_nullable_to_non_nullable
as String,start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as int,tokenCount: null == tokenCount ? _self.tokenCount : tokenCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PhraseMatch].
extension PhraseMatchPatterns on PhraseMatch {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PhraseMatch value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PhraseMatch() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PhraseMatch value)  $default,){
final _that = this;
switch (_that) {
case _PhraseMatch():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PhraseMatch value)?  $default,){
final _that = this;
switch (_that) {
case _PhraseMatch() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String phrase,  String lemma,  int start,  int tokenCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PhraseMatch() when $default != null:
return $default(_that.phrase,_that.lemma,_that.start,_that.tokenCount);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String phrase,  String lemma,  int start,  int tokenCount)  $default,) {final _that = this;
switch (_that) {
case _PhraseMatch():
return $default(_that.phrase,_that.lemma,_that.start,_that.tokenCount);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String phrase,  String lemma,  int start,  int tokenCount)?  $default,) {final _that = this;
switch (_that) {
case _PhraseMatch() when $default != null:
return $default(_that.phrase,_that.lemma,_that.start,_that.tokenCount);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PhraseMatch implements PhraseMatch {
  const _PhraseMatch({required this.phrase, required this.lemma, required this.start, required this.tokenCount});
  factory _PhraseMatch.fromJson(Map<String, dynamic> json) => _$PhraseMatchFromJson(json);

@override final  String phrase;
@override final  String lemma;
@override final  int start;
@override final  int tokenCount;

/// Create a copy of PhraseMatch
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PhraseMatchCopyWith<_PhraseMatch> get copyWith => __$PhraseMatchCopyWithImpl<_PhraseMatch>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PhraseMatchToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PhraseMatch&&(identical(other.phrase, phrase) || other.phrase == phrase)&&(identical(other.lemma, lemma) || other.lemma == lemma)&&(identical(other.start, start) || other.start == start)&&(identical(other.tokenCount, tokenCount) || other.tokenCount == tokenCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,phrase,lemma,start,tokenCount);

@override
String toString() {
  return 'PhraseMatch(phrase: $phrase, lemma: $lemma, start: $start, tokenCount: $tokenCount)';
}


}

/// @nodoc
abstract mixin class _$PhraseMatchCopyWith<$Res> implements $PhraseMatchCopyWith<$Res> {
  factory _$PhraseMatchCopyWith(_PhraseMatch value, $Res Function(_PhraseMatch) _then) = __$PhraseMatchCopyWithImpl;
@override @useResult
$Res call({
 String phrase, String lemma, int start, int tokenCount
});




}
/// @nodoc
class __$PhraseMatchCopyWithImpl<$Res>
    implements _$PhraseMatchCopyWith<$Res> {
  __$PhraseMatchCopyWithImpl(this._self, this._then);

  final _PhraseMatch _self;
  final $Res Function(_PhraseMatch) _then;

/// Create a copy of PhraseMatch
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phrase = null,Object? lemma = null,Object? start = null,Object? tokenCount = null,}) {
  return _then(_PhraseMatch(
phrase: null == phrase ? _self.phrase : phrase // ignore: cast_nullable_to_non_nullable
as String,lemma: null == lemma ? _self.lemma : lemma // ignore: cast_nullable_to_non_nullable
as String,start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as int,tokenCount: null == tokenCount ? _self.tokenCount : tokenCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$ApiError {

 ApiErrorCode get code; String get message; List<String>? get suggestions;
/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApiErrorCopyWith<ApiError> get copyWith => _$ApiErrorCopyWithImpl<ApiError>(this as ApiError, _$identity);

  /// Serializes this ApiError to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other.suggestions, suggestions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,code,message,const DeepCollectionEquality().hash(suggestions));

@override
String toString() {
  return 'ApiError(code: $code, message: $message, suggestions: $suggestions)';
}


}

/// @nodoc
abstract mixin class $ApiErrorCopyWith<$Res>  {
  factory $ApiErrorCopyWith(ApiError value, $Res Function(ApiError) _then) = _$ApiErrorCopyWithImpl;
@useResult
$Res call({
 ApiErrorCode code, String message, List<String>? suggestions
});




}
/// @nodoc
class _$ApiErrorCopyWithImpl<$Res>
    implements $ApiErrorCopyWith<$Res> {
  _$ApiErrorCopyWithImpl(this._self, this._then);

  final ApiError _self;
  final $Res Function(ApiError) _then;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? message = null,Object? suggestions = freezed,}) {
  return _then(_self.copyWith(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ApiErrorCode,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,suggestions: freezed == suggestions ? _self.suggestions : suggestions // ignore: cast_nullable_to_non_nullable
as List<String>?,
  ));
}

}


/// Adds pattern-matching-related methods to [ApiError].
extension ApiErrorPatterns on ApiError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ApiError value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ApiError() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ApiError value)  $default,){
final _that = this;
switch (_that) {
case _ApiError():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ApiError value)?  $default,){
final _that = this;
switch (_that) {
case _ApiError() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ApiErrorCode code,  String message,  List<String>? suggestions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ApiError() when $default != null:
return $default(_that.code,_that.message,_that.suggestions);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ApiErrorCode code,  String message,  List<String>? suggestions)  $default,) {final _that = this;
switch (_that) {
case _ApiError():
return $default(_that.code,_that.message,_that.suggestions);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ApiErrorCode code,  String message,  List<String>? suggestions)?  $default,) {final _that = this;
switch (_that) {
case _ApiError() when $default != null:
return $default(_that.code,_that.message,_that.suggestions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ApiError implements ApiError {
  const _ApiError({required this.code, required this.message, final  List<String>? suggestions}): _suggestions = suggestions;
  factory _ApiError.fromJson(Map<String, dynamic> json) => _$ApiErrorFromJson(json);

@override final  ApiErrorCode code;
@override final  String message;
 final  List<String>? _suggestions;
@override List<String>? get suggestions {
  final value = _suggestions;
  if (value == null) return null;
  if (_suggestions is EqualUnmodifiableListView) return _suggestions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ApiErrorCopyWith<_ApiError> get copyWith => __$ApiErrorCopyWithImpl<_ApiError>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ApiErrorToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ApiError&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other._suggestions, _suggestions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,code,message,const DeepCollectionEquality().hash(_suggestions));

@override
String toString() {
  return 'ApiError(code: $code, message: $message, suggestions: $suggestions)';
}


}

/// @nodoc
abstract mixin class _$ApiErrorCopyWith<$Res> implements $ApiErrorCopyWith<$Res> {
  factory _$ApiErrorCopyWith(_ApiError value, $Res Function(_ApiError) _then) = __$ApiErrorCopyWithImpl;
@override @useResult
$Res call({
 ApiErrorCode code, String message, List<String>? suggestions
});




}
/// @nodoc
class __$ApiErrorCopyWithImpl<$Res>
    implements _$ApiErrorCopyWith<$Res> {
  __$ApiErrorCopyWithImpl(this._self, this._then);

  final _ApiError _self;
  final $Res Function(_ApiError) _then;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,Object? suggestions = freezed,}) {
  return _then(_ApiError(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ApiErrorCode,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,suggestions: freezed == suggestions ? _self._suggestions : suggestions // ignore: cast_nullable_to_non_nullable
as List<String>?,
  ));
}


}

// dart format on
