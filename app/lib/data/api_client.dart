// The only place the app talks to the API. No model calls happen here — the
// server holds the OpenAI key.

import 'dart:async';
import 'dart:convert';

import 'package:arth/core/models/contracts.dart';
import 'package:arth/data/account.dart';
import 'package:arth/data/community.dart';
import 'package:dio/dio.dart';

/// Base URL, set at build time:
///   flutter run --dart-define=ARTH_API_URL=http://192.168.1.10:3000
/// A physical phone cannot reach `localhost` on the Mac; use the LAN IP.
const String kApiBaseUrl = String.fromEnvironment(
  'ARTH_API_URL',
  defaultValue: 'http://localhost:3000',
);

/// Typed failure from the API or the network.
class ApiFailure implements Exception {
  const ApiFailure(this.code, this.message, {this.suggestions = const []});

  /// One of the contract's codes, or `OFFLINE` when the request never got out.
  final String code;

  /// Hindi, user-facing.
  final String message;
  final List<String> suggestions;

  bool get isOffline => code == 'OFFLINE';
  bool get isNotFound => code == 'NOT_FOUND';

  @override
  String toString() => 'ApiFailure($code: $message)';
}

/// One server-sent event from /translate.
class SseEvent {
  const SseEvent(this.event, this.data);

  final String event;
  final Map<String, dynamic> data;
}

class ApiClient {
  /// [idToken] supplies the signed-in user's Firebase ID token (null when
  /// signed out); every request carries it, so the server can count and
  /// attribute usage.
  ///
  /// [onUsage] hears the AI allowance each AI response reports.
  ApiClient({
    Dio? dio,
    String baseUrl = kApiBaseUrl,
    String? deviceId,
    Future<String?> Function()? idToken,
    void Function(Usage usage)? onUsage,
  })
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: '$baseUrl/v1',
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 20),
                headers: {
                  'accept': 'application/json',
                  'x-device-id': ?deviceId,
                },
              ),
            ) {
    if (onUsage != null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (res, handler) {
            final usage = Usage.fromHeaders(res.headers.value('x-ai-used'), res.headers.value('x-ai-limit'), res.headers.value('x-ai-period'));
            if (usage != null) onUsage(usage);
            handler.next(res);
          },
        ),
      );
    }
    if (idToken != null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            try {
              final token = await idToken();
              if (token != null) options.headers['authorization'] = 'Bearer $token';
            } on Exception {
              // No token (offline refresh failed): send the request signed out.
            }
            handler.next(options);
          },
        ),
      );
    }
  }

  final Dio _dio;

  // ---- account ----

  Future<Account> me() async {
    try {
      return Account.fromJson(_data(await _dio.get<Map<String, dynamic>>('/me')));
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  /// Changes the profile; pass [clearPhoto] to remove the photo.
  Future<Account> updateMe({String? displayName, String? bio, String? photoUrl, bool clearPhoto = false}) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/me',
        data: {
          'displayName': ?displayName,
          'bio': ?bio,
          if (photoUrl != null || clearPhoto) 'photoUrl': photoUrl,
        },
      );
      return Account.fromJson(_data(res));
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  /// Uploads a profile photo: the API signs the upload, the image goes
  /// straight to Cloudinary. Returns the image's https URL.
  Future<String> uploadAvatar(String filePath) async {
    final Map<String, dynamic> ticket;
    try {
      ticket = _data(await _dio.post<Map<String, dynamic>>('/me/avatar'));
    } on DioException catch (e) {
      throw _failure(e);
    }
    try {
      final res = await Dio(BaseOptions(sendTimeout: const Duration(minutes: 1), receiveTimeout: const Duration(minutes: 1))).post<Map<String, dynamic>>(
        ticket['uploadUrl'] as String,
        data: FormData.fromMap({
          ...(ticket['params'] as Map<String, dynamic>),
          'api_key': ticket['apiKey'],
          'timestamp': ticket['timestamp'],
          'signature': ticket['signature'],
          'file': await MultipartFile.fromFile(filePath),
        }),
      );
      final url = res.data?['secure_url'] as String?;
      if (url == null) throw const ApiFailure('UPSTREAM_FAILED', 'तस्वीर अपलोड नहीं हो पाई।');
      return url;
    } on DioException catch (e) {
      throw e.response == null ? _failure(e) : const ApiFailure('UPSTREAM_FAILED', 'तस्वीर अपलोड नहीं हो पाई।');
    }
  }

  Future<void> registerPushToken({required String token, required String platform, required String lang}) async {
    try {
      _data(await _dio.post<Map<String, dynamic>>('/me/push-token', data: {'token': token, 'platform': platform, 'lang': lang}));
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  Future<void> unregisterPushToken(String token) async {
    try {
      _data(await _dio.delete<Map<String, dynamic>>('/me/push-token', data: {'token': token}));
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  /// Sends a test notification to the signed-in reader's phones.
  Future<({int devices, int sent})> testPush() async {
    try {
      final d = _data(await _dio.post<Map<String, dynamic>>('/me/push-test'));
      return (devices: d['devices'] as int, sent: d['sent'] as int);
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  Future<Account> setReviewReminders({required bool on}) async {
    try {
      return Account.fromJson(_data(await _dio.patch<Map<String, dynamic>>('/me', data: {'reviewReminders': on})));
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  // ---- community ----

  Future<T> _call<T>(Future<Response<Map<String, dynamic>>> Function() request, T Function(Map<String, dynamic> data) parse) async {
    try {
      return parse(_data(await request()));
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  Future<DeckPage> communityDecks({String sort = 'recent', String? query, int page = 0, String? owner}) => _call(
        () => _dio.get('/community/decks', queryParameters: {'sort': sort, 'page': page, if (query != null && query.trim().isNotEmpty) 'q': query.trim(), 'owner': ?owner}),
        (d) => DeckPage(
          decks: [for (final x in d['decks'] as List<dynamic>) PublishedDeckSummary.fromJson(x as Map<String, dynamic>)],
          more: (d['more'] as bool?) ?? false,
          canPublish: (d['canPublish'] as bool?) ?? false,
        ),
      );

  Future<PublishedDeck> communityDeck(String id) => _call(() => _dio.get('/community/decks/$id'), PublishedDeck.fromJson);

  Future<String> publishDeck({required String bookTitle, required List<DeckCard> cards, String title = '', String blurb = '', String? bookKey}) => _call(
        () => _dio.post(
          '/community/decks',
          data: {'title': title, 'bookTitle': bookTitle, 'bookKey': bookKey, 'blurb': blurb, 'cards': [for (final c in cards) c.toJson()]},
        ),
        (d) => d['id'] as String,
      );

  Future<void> updatePublishedDeck(String id, {String? title, String? blurb, List<DeckCard>? cards}) => _call(
        () => _dio.patch('/community/decks/$id', data: {'title': ?title, 'blurb': ?blurb, if (cards != null) 'cards': [for (final c in cards) c.toJson()]}),
        (_) {},
      );

  Future<void> deletePublishedDeck(String id) => _call(() => _dio.delete('/community/decks/$id'), (_) {});

  Future<({bool liked, int likes})> toggleLike(String deckId) =>
      _call(() => _dio.post('/community/decks/$deckId/like'), (d) => (liked: d['liked'] as bool, likes: d['likes'] as int));

  Future<int> markSaved(String deckId) => _call(() => _dio.post('/community/decks/$deckId/save'), (d) => d['saves'] as int);

  Future<CommunityComment> addComment(String deckId, String text, {String? parentId}) =>
      _call(() => _dio.post('/community/decks/$deckId/comments', data: {'text': text, 'parentId': parentId}), CommunityComment.fromJson);

  Future<void> deleteComment(String id) => _call(() => _dio.delete('/community/comments/$id'), (_) {});

  /// Returns whether the item is now hidden for review.
  Future<bool> report({required String kind, required String targetId, String reason = ''}) =>
      _call(() => _dio.post('/community/reports', data: {'kind': kind, 'targetId': targetId, 'reason': reason}), (d) => (d['hidden'] as bool?) ?? false);

  // ---- admin ----

  Future<List<AdminReportItem>> adminReports() =>
      _call(() => _dio.get('/admin/reports'), (d) => [for (final x in d['items'] as List<dynamic>) AdminReportItem.fromJson(x as Map<String, dynamic>)]);

  Future<void> moderate({required String kind, required String targetId, required bool remove}) =>
      _call(() => _dio.post('/admin/moderate', data: {'kind': kind, 'targetId': targetId, 'action': remove ? 'remove' : 'dismiss'}), (_) {});

  Future<List<AdminUser>> adminUsers(String query) =>
      _call(() => _dio.get('/admin/users', queryParameters: {'q': query}), (d) => [for (final x in d['users'] as List<dynamic>) AdminUser.fromJson(x as Map<String, dynamic>)]);

  Future<AdminUser> adminUpdateUser(String uid, {String? tier, bool? banned}) =>
      _call(() => _dio.patch('/admin/users/$uid', data: {'tier': ?tier, 'banned': ?banned}), AdminUser.fromJson);

  Future<({int readers, int sent})> broadcast({required String title, required String body, String? tier}) => _call(
        () => _dio.post('/admin/broadcast', data: {'title': title, 'body': body, 'tier': ?tier}),
        (d) => (readers: d['readers'] as int, sent: d['sent'] as int),
      );

  /// One sync round: send local changes, get the server's since [cursor].
  Future<SyncPage> sync({required int cursor, required List<Map<String, Object?>> cards, required List<Map<String, Object?>> bookmarks}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/sync',
        data: {'cursor': cursor, 'cards': cards, 'bookmarks': bookmarks},
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return SyncPage.fromJson(_data(res));
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  /// Entry, or null with the server's suggestions (morphological bases the
  /// reader can open) on a miss. Throws [ApiFailure] for anything else.
  Future<({DictionaryEntry? entry, List<String> suggestions})> lookup(String word) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/lookup',
        queryParameters: {'word': word},
        // A first-time lookup may generate the entry live (a few seconds).
        options: Options(receiveTimeout: const Duration(seconds: 45)),
      );
      return (entry: DictionaryEntry.fromJson(_data(res)), suggestions: const <String>[]);
    } on ApiFailure catch (e) {
      if (e.isNotFound) return (entry: null, suggestions: e.suggestions);
      rethrow;
    } on DioException catch (e) {
      final f = _failure(e);
      if (f.isNotFound) return (entry: null, suggestions: f.suggestions);
      throw f;
    }
  }

  Future<ContextResult> context({
    required String word,
    required String sentence,
    bool prefetch = false,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/context',
        data: {'word': word, 'sentence': sentence},
        // Background prefetch is rate-limited in its own bucket server-side.
        options: prefetch ? Options(headers: {'x-prefetch': '1'}) : null,
      );
      return ContextResult.fromJson(_data(res));
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  Future<PhraseMatch?> matchPhrase({
    required List<String> tokens,
    required int index,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/phrases/match',
        data: {'tokens': tokens, 'index': index},
      );
      final body = res.data;
      if (body == null || body['ok'] != true || body['data'] == null) {
        return null;
      }
      return PhraseMatch.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  /// Streams /translate as server-sent events: `hindi`, `simpleMeaning`,
  /// `difficultWords`, then `done` (full TranslationResult) or `error`.
  Stream<SseEvent> translate({
    required String text,
    String? context,
  }) async* {
    Response<ResponseBody> res;
    try {
      res = await _dio.post<ResponseBody>(
        '/translate',
        data: {'text': text, 'context': ?context},
        options: Options(
          responseType: ResponseType.stream,
          headers: {'accept': 'text/event-stream'},
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
    } on DioException catch (e) {
      throw _failure(e);
    }
    yield* _parseSse(res.data!.stream.cast<List<int>>());
  }

  /// Raw NDJSON lines from /seed. The seed loader parses them.
  Future<Stream<String>> seedLines({DateTime? since}) async {
    try {
      final res = await _dio.get<ResponseBody>(
        '/seed',
        queryParameters: {if (since != null) 'since': since.toIso8601String()},
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
      return res.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  // ---- helpers ----

  Map<String, dynamic> _data(Response<Map<String, dynamic>> res) {
    final body = res.data;
    if (body == null) throw const ApiFailure('INTERNAL', 'खाली जवाब मिला।');
    if (body['ok'] == true) return body['data'] as Map<String, dynamic>;
    throw _fromErrorBody(body);
  }

  static ApiFailure _fromErrorBody(Map<String, dynamic> body) {
    final err = body['error'];
    if (err is Map<String, dynamic>) {
      return ApiFailure(
        (err['code'] as String?) ?? 'INTERNAL',
        (err['message'] as String?) ?? 'कुछ गड़बड़ हो गई।',
        suggestions: ((err['suggestions'] as List<dynamic>?) ?? const [])
            .cast<String>(),
      );
    }
    return const ApiFailure('INTERNAL', 'कुछ गड़बड़ हो गई।');
  }

  static ApiFailure _failure(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) return _fromErrorBody(data);
    if (data is String && data.startsWith('{')) {
      try {
        return _fromErrorBody(jsonDecode(data) as Map<String, dynamic>);
      } on FormatException {
        // fall through
      }
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return const ApiFailure(
          'OFFLINE',
          'और अर्थ देखने के लिए इंटरनेट चाहिए।',
        );
      case DioExceptionType.badResponse:
        if (e.response?.statusCode == 401) return const ApiFailure('UNAUTHORIZED', 'इसके लिए साइन इन करें।');
        if (e.response?.statusCode == 402) return const ApiFailure('QUOTA_EXCEEDED', 'आपके AI उपयोग खत्म हो गए हैं।');
        if (e.response?.statusCode == 403) return const ApiFailure('FORBIDDEN', 'इसकी अनुमति नहीं है।');
        if (e.response?.statusCode == 404) return const ApiFailure('NOT_FOUND', 'यह अब उपलब्ध नहीं है।');
        if (e.response?.statusCode == 429) {
          return const ApiFailure(
            'RATE_LIMITED',
            'बहुत जल्दी-जल्दी अनुरोध हो रहे हैं। एक मिनट रुककर फिर कोशिश करें।',
          );
        }
        return const ApiFailure('INTERNAL', 'कुछ गड़बड़ हो गई।');
      case DioExceptionType.transformTimeout:
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
        return const ApiFailure('INTERNAL', 'कुछ गड़बड़ हो गई।');
    }
  }
}

/// Minimal SSE parser: `event:` / `data:` lines, blank line ends an event.
Stream<SseEvent> _parseSse(Stream<List<int>> bytes) async* {
  var event = 'message';
  final data = StringBuffer();
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        final raw = data.toString();
        data.clear();
        final parsed = jsonDecode(raw);
        yield SseEvent(
          event,
          parsed is Map<String, dynamic> ? parsed : {'value': parsed},
        );
      }
      event = 'message';
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        if (data.isNotEmpty) data.write('\n');
        data.write(value);
      default:
        break;
    }
  }
}
