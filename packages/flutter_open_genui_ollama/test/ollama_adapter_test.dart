// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_ollama/flutter_open_genui_ollama.dart';
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
  group('OllamaGenUiAdapter', () {
    test('targets localhost:11434 with no Authorization header', () async {
      final fake = _FakeSseAdapter(['data: [DONE]']);
      final adapter = OllamaGenUiAdapter(
        model: 'llama3.1',
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
        'http://localhost:11434/v1/chat/completions',
      );
      expect(fake.captured!.headers.containsKey('authorization'), isFalse);
      final body = fake.captured!.data as Map<String, Object?>;
      expect(body['model'], 'llama3.1');
      expect(body['stream'], true);
    });

    test('honors a custom baseUrl (remote Ollama host)', () async {
      final fake = _FakeSseAdapter(['data: [DONE]']);
      final adapter = OllamaGenUiAdapter(
        model: 'qwen2.5',
        systemPrompt: 's',
        baseUrl: 'http://ollama.local:8080/v1',
        dio: Dio()..httpClientAdapter = fake,
      );

      await adapter
          .streamCompletion(
            GenUiRequest(systemPrompt: 's', history: [ChatMessage.user('hi')]),
          )
          .toList();

      expect(
        fake.captured!.uri.toString(),
        'http://ollama.local:8080/v1/chat/completions',
      );
    });
  });
}
