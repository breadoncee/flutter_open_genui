// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openrouter/flutter_open_genui_openrouter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart' show ChatMessage;

class _FakeSseAdapter implements HttpClientAdapter {
  _FakeSseAdapter(this.sseLines);

  final List<String> sseLines;
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    final body = sseLines.map((l) => '$l\n\n').join();
    return ResponseBody(
      Stream<Uint8List>.value(Uint8List.fromList(utf8.encode(body))),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('OpenRouterGenUiAdapter', () {
    test('targets openrouter.ai by default with Bearer auth', () async {
      final fake = _FakeSseAdapter(['data: [DONE]']);
      final adapter = OpenRouterGenUiAdapter(
        apiKey: 'or-key',
        model: 'anthropic/claude-sonnet-4-6',
        systemPrompt: 'SYSTEM',
        dio: Dio()..httpClientAdapter = fake,
      );

      await adapter
          .streamCompletion(
            GenUiRequest(
              systemPrompt: 'SYSTEM',
              history: [ChatMessage.user('hi')],
            ),
          )
          .toList();

      expect(
        fake.captured!.uri.toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
      expect(fake.captured!.headers['authorization'], 'Bearer or-key');
      final body = fake.captured!.data as Map<String, Object?>;
      expect(body['model'], 'anthropic/claude-sonnet-4-6');
      expect(body['stream'], true);
    });

    test('forwards optional HTTP-Referer and X-Title headers', () async {
      final fake = _FakeSseAdapter(['data: [DONE]']);
      final adapter = OpenRouterGenUiAdapter(
        apiKey: 'k',
        model: 'm',
        systemPrompt: 's',
        referer: 'https://app.example.com',
        title: 'MyApp',
        dio: Dio()..httpClientAdapter = fake,
      );

      await adapter
          .streamCompletion(
            GenUiRequest(systemPrompt: 's', history: [ChatMessage.user('hi')]),
          )
          .toList();

      expect(fake.captured!.headers['http-referer'], 'https://app.example.com');
      expect(fake.captured!.headers['x-title'], 'MyApp');
    });
  });
}
