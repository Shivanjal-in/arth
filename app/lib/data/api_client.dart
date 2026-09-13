// The only place the app talks to the API. No model calls happen here — the
// server holds the OpenAI key.

import 'dart:async';
import 'dart:convert';

import 'package:arth/core/models/contracts.dart';
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
  ApiClient({Dio? dio, String baseUrl = kApiBaseUrl, String? deviceId})
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
            );

  final Dio _dio;

  Future<DictionaryEntry?> lookup(String word) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/lookup',
        queryParameters: {'word': word},
      );
      return DictionaryEntry.fromJson(_data(res));
    } on ApiFailure catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    } on DioException catch (e) {
      final f = _failure(e);
      if (f.isNotFound) return null;
      throw f;
    }
  }

  Future<ContextResult> context({
    required String word,
    required String sentence,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/context',
        data: {'word': word, 'sentence': sentence},
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
