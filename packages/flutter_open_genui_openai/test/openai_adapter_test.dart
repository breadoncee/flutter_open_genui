// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart' show ChatMessage;

/// A [HttpClientAdapter] that captures the outgoing request and replays a canned
/// SSE body — no network, no live LLM (CI-safe).
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

OpenAiGenUiAdapter _buildAdapter(_FakeSseAdapter fake) {
  final dio = Dio()..httpClientAdapter = fake;
  return OpenAiGenUiAdapter(
    apiKey: 'test-key',
    model: 'gpt-5.4',
    systemPrompt: 'SYSTEM PROMPT',
    dio: dio,
  );
}

void main() {
  group('OpenAiGenUiAdapter.streamCompletion', () {
    test('parses content deltas from the SSE stream', () async {
      final fake = _FakeSseAdapter([
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '```json\n'},
            },
          ],
        })}',
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '{"version":"v0.9"}'},
            },
          ],
        })}',
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '\n```'},
            },
          ],
        })}',
        'data: [DONE]',
      ]);
      final adapter = _buildAdapter(fake);

      final chunks = await adapter
          .streamCompletion(
            GenUiRequest(
              systemPrompt: 'SYSTEM PROMPT',
              history: [ChatMessage.user('hello')],
            ),
          )
          .toList();

      expect(chunks.join(), '```json\n{"version":"v0.9"}\n```');
    });

    test('builds the correct request envelope', () async {
      final fake = _FakeSseAdapter(['data: [DONE]']);
      final adapter = _buildAdapter(fake);

      await adapter
          .streamCompletion(
            GenUiRequest(
              systemPrompt: 'SYSTEM PROMPT',
              history: [ChatMessage.user('Plan me a trip')],
            ),
          )
          .toList();

      final options = fake.captured!;
      expect(
        options.uri.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(options.headers['authorization'], 'Bearer test-key');

      final body = options.data as Map<String, Object?>;
      expect(body['model'], 'gpt-5.4');
      expect(body['stream'], true);

      final messages = body['messages']! as List;
      expect(messages.first, {'role': 'system', 'content': 'SYSTEM PROMPT'});
      expect(messages.last, {'role': 'user', 'content': 'Plan me a trip'});
    });

    test('respects a custom baseUrl (proxy/OpenRouter/Ollama)', () async {
      final fake = _FakeSseAdapter(['data: [DONE]']);
      final dio = Dio()..httpClientAdapter = fake;
      final adapter = OpenAiGenUiAdapter(
        apiKey: 'k',
        model: 'm',
        systemPrompt: 's',
        baseUrl: 'https://proxy.example.com/v1/',
        dio: dio,
      );

      await adapter
          .streamCompletion(
            GenUiRequest(systemPrompt: 's', history: [ChatMessage.user('hi')]),
          )
          .toList();

      // Trailing slash trimmed; single /chat/completions appended.
      expect(
        fake.captured!.uri.toString(),
        'https://proxy.example.com/v1/chat/completions',
      );
    });
  });
}
