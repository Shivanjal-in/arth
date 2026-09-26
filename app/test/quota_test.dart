import 'dart:convert';
import 'dart:typed_data';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/data/account.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/features/plans/plans_screen.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with [status] and [body], counting them.
class _Canned implements HttpClientAdapter {
  _Canned(this.status, this.body, {this.headers = const {}});

  final int status;
  final Map<String, Object?> body;
  final Map<String, List<String>> headers;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(HttpClientAdapter adapter, {void Function(Usage)? onUsage}) =>
    ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://fake/v1'))..httpClientAdapter = adapter, onUsage: onUsage);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('usage', () {
    test('from headers; left and exhausted', () {
      final u = Usage.fromHeaders('37', '100', 'lifetime')!;
      expect(u.left, 63);
      expect(u.exhausted, isFalse);
      expect(Usage.fromHeaders('100', '100', 'lifetime')!.exhausted, isTrue);
      final unlimited = Usage.fromHeaders('5000', 'none', 'none')!;
      expect(unlimited.limit, isNull);
      expect(unlimited.exhausted, isFalse);
      expect(Usage.fromHeaders(null, null, null), isNull);
    });

    test('the line the account card shows', () {
      const t = AppStrings.en;
      expect(usageLine(const Usage(used: 37, limit: 100, monthly: false), t), '63 of 100 AI answers left');
      expect(usageLine(const Usage(used: 188, limit: 1000, monthly: true), t), '812 of 1000 AI answers left this month');
      expect(usageLine(const Usage(used: 9, limit: null, monthly: false), t), 'Unlimited AI answers');
    });

    test('an AI response reports usage; a 402 is QUOTA_EXCEEDED', () async {
      Usage? heard;
      final ok = _Canned(
        200,
        {'ok': true, 'data': {'senseIndex': 0, 'meaning': 'x', 'note': ''}},
        headers: {'x-ai-used': ['3'], 'x-ai-limit': ['100'], 'x-ai-period': ['lifetime']},
      );
      await _client(ok, onUsage: (u) => heard = u).context(word: 'single', sentence: 'A single man.');
      expect(heard?.used, 3);

      final over = _Canned(402, {
        'ok': false,
        'error': {'code': 'QUOTA_EXCEEDED', 'message': 'x', 'usage': {'used': 100, 'limit': 100, 'period': 'lifetime', 'resetsAt': null}},
      });
      await expectLater(
        _client(over).context(word: 'single', sentence: 'A single man.'),
        throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'QUOTA_EXCEEDED')),
      );
    });
  });

  group('AI access', () {
    ProviderContainer container({required bool firebase, String? uid, Usage? usage}) {
      final c = ProviderContainer(
        overrides: [
          firebaseReadyProvider.overrideWithValue(firebase),
          signedInUidProvider.overrideWithValue(uid),
          usageProvider.overrideWith(() => _FixedUsage(usage)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('open without accounts; signed out, allowed, exhausted with them', () {
      expect(container(firebase: false).read(aiAccessProvider), AiAccess.open);
      expect(container(firebase: true).read(aiAccessProvider), AiAccess.signedOut);
      expect(
        container(firebase: true, uid: 'u', usage: const Usage(used: 5, limit: 100, monthly: false)).read(aiAccessProvider),
        AiAccess.allowed,
      );
      expect(
        container(firebase: true, uid: 'u', usage: const Usage(used: 100, limit: 100, monthly: false)).read(aiAccessProvider),
        AiAccess.exhausted,
      );
    });

    test('a signed-out reader’s translation says “sign in” without calling the API', () {
      final adapter = _Canned(200, {'ok': true, 'data': {}});
      final c = ProviderContainer(
        overrides: [
          firebaseReadyProvider.overrideWithValue(true),
          signedInUidProvider.overrideWithValue(null),
          apiClientProvider.overrideWithValue(_client(adapter)),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(readerControllerProvider, (_, _) {});
      addTearDown(sub.close);
      c.read(readerControllerProvider.notifier).showSentence(text: 'It is a truth.', anchor: Rect.zero, page: 1);
      final s = c.read(readerControllerProvider)! as SentenceTooltipState;
      expect(s.errorCode, 'UNAUTHORIZED');
      expect(s.done, isTrue);
      expect(adapter.calls, 0);
    });
  });
}

class _FixedUsage extends UsageNotifier {
  _FixedUsage(this.usage);

  final Usage? usage;

  @override
  Usage? build() => usage;
}
