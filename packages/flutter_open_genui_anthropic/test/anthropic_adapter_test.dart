// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_anthropic/flutter_open_genui_anthropic.dart';
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

String _event(String type, Map<String, Object?> body) =>
    'event: $type\ndata: ${jsonEncode({'type': type, ...body})}';

void main() {
  group('AnthropicGenUiAdapter', () {
    test('parses text_delta events from the Messages SSE stream', () async {
      final fake = _FakeSseAdapter([
        _event('message_start', {'message': <String, Object?>{}}),
        _event('content_block_start', {
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        }),
        _event('content_block_delta', {
          'index': 0,
          'delta': {'type': 'text_delta', 'text': '```json\n'},
        }),
        _event('content_block_delta', {
          'index': 0,
          'delta': {'type': 'text_delta', 'text': '{"version":"v0.9"}'},
        }),
        _event('content_block_delta', {
          'index': 0,
          'delta': {'type': 'text_delta', 'text': '\n```'},
        }),
        _event('content_block_stop', {'index': 0}),
        _event('message_stop', <String, Object?>{}),
      ]);
      final adapter = AnthropicGenUiAdapter(
        apiKey: 'k',
        model: 'claude-sonnet-4-6',
        systemPrompt: 'SYSTEM',
        dio: Dio()..httpClientAdapter = fake,
      );

      final chunks = await adapter
          .streamCompletion(
            GenUiRequest(
              systemPrompt: 'SYSTEM',
              history: [ChatMessage.user('hi')],
            ),
          )
          .toList();

      expect(chunks.join(), '```json\n{"version":"v0.9"}\n```');
    });

    test('ignores ping, message_start, and tool_use deltas', () async {
      final fake = _FakeSseAdapter([
        'event: ping\ndata: {"type":"ping"}',
        _event('message_start', {'message': <String, Object?>{}}),
        _event('content_block_delta', {
          'index': 0,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"foo":'},
        }),
        _event('content_block_delta', {
          'index': 1,
          'delta': {'type': 'text_delta', 'text': 'real text'},
        }),
      ]);
      final adapter = AnthropicGenUiAdapter(
        apiKey: 'k',
        model: 'claude-sonnet-4-6',
        systemPrompt: 's',
        dio: Dio()..httpClientAdapter = fake,
      );

      final chunks = await adapter
          .streamCompletion(
            GenUiRequest(systemPrompt: 's', history: [ChatMessage.user('hi')]),
          )
          .toList();
      expect(chunks.join(), 'real text');
    });

    test('builds the correct Messages API request envelope', () async {
      final fake = _FakeSseAdapter([_event('message_stop', {})]);
      final adapter = AnthropicGenUiAdapter(
        apiKey: 'sk-ant-x',
        model: 'claude-sonnet-4-6',
        systemPrompt: 'SYSTEM',
        maxTokens: 2048,
        dio: Dio()..httpClientAdapter = fake,
      );

      await adapter
          .streamCompletion(
            GenUiRequest(
              systemPrompt: 'SYSTEM',
              history: [ChatMessage.user('Plan me a trip')],
            ),
          )
          .toList();

      final options = fake.captured!;
      expect(options.uri.toString(), 'https://api.anthropic.com/v1/messages');
      expect(options.headers['x-api-key'], 'sk-ant-x');
      expect(options.headers['anthropic-version'], '2023-06-01');

      final body = options.data as Map<String, Object?>;
      expect(body['model'], 'claude-sonnet-4-6');
      expect(body['system'], 'SYSTEM'); // top-level, not in messages
      expect(body['stream'], true);
      expect(body['max_tokens'], 2048);

      final messages = body['messages']! as List;
      expect(messages, hasLength(1));
      expect(messages.first, {'role': 'user', 'content': 'Plan me a trip'});
    });
  });
}
