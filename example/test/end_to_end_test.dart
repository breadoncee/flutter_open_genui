// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';

/// Replays canned OpenAI SSE chunks — no network, CI-safe.
class _FakeSse implements HttpClientAdapter {
  _FakeSse(this.lines);
  final List<String> lines;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = lines.map((l) => '$l\n\n').join();
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

String _delta(String content) =>
    'data: ${jsonEncode({
      'choices': [
        {
          'delta': {'content': content},
        },
      ],
    })}';

void main() {
  test('transport path: SSE creates and populates a surface', () async {
    final catalog = Catalog([
      BasicCatalogItems.text,
    ], catalogId: 'test_catalog');

    const createMsg =
        '{"version":"v0.9","createSurface":'
        '{"surfaceId":"s1","catalogId":"test_catalog","sendDataModel":true}}';
    const updateMsg =
        '{"version":"v0.9","updateComponents":{"surfaceId":"s1",'
        '"components":[{"id":"root","component":"Text",'
        '"text":"Hello GenUI"},]}}';

    final fake = _FakeSse([
      _delta('Sure!\n```json\n$createMsg\n```\n'),
      _delta('```json\n$updateMsg\n```'),
      'data: [DONE]',
    ]);
    final adapter = OpenAiGenUiAdapter(
      apiKey: 'test',
      model: 'gpt-5.4',
      systemPrompt: GenUiPrompt.fromCatalog(catalog),
      dio: Dio()..httpClientAdapter = fake,
    );
    final controller = SurfaceController(catalogs: [catalog]);
    final conversation = Conversation(
      controller: controller,
      transport: adapter.transport,
    );
    final events = <ConversationEvent>[];
    conversation.events.listen(events.add);

    await conversation.sendRequest(ChatMessage.user('hi'));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      events.whereType<ConversationError>().map((e) => '${e.error}').toList(),
      isEmpty,
    );
    expect(controller.activeSurfaceIds, contains('s1'));

    conversation.dispose();
    adapter.dispose();
    controller.dispose();
  });

  testWidgets(
    'OpenAI SSE → healer → transport → controller renders a Surface',
    (tester) async {
      final catalog = Catalog([
        BasicCatalogItems.text,
      ], catalogId: 'test_catalog');

      late final SurfaceController controller;
      late final Conversation conversation;
      late final OpenAiGenUiAdapter adapter;

      // Construct AND drive everything inside runAsync so the genui stream
      // controllers bind to the real async zone (not the fake test clock);
      // otherwise the dio stream and parser callbacks never fire.
      await tester.runAsync(() async {
        const createMsg =
            '{"version":"v0.9","createSurface":'
            '{"surfaceId":"s1","catalogId":"test_catalog",'
            '"sendDataModel":true}}';
        // Trailing comma in the array is malformed JSON — exercises healing.
        const updateMsg =
            '{"version":"v0.9","updateComponents":{"surfaceId":"s1",'
            '"components":[{"id":"root","component":"Text",'
            '"text":"Hello GenUI"},]}}';

        final fake = _FakeSse([
          _delta('Sure!\n```json\n$createMsg\n```\n'),
          _delta('```json\n$updateMsg\n```'),
          'data: [DONE]',
        ]);

        adapter = OpenAiGenUiAdapter(
          apiKey: 'test',
          model: 'gpt-5.4',
          systemPrompt: GenUiPrompt.fromCatalog(catalog),
          dio: Dio()..httpClientAdapter = fake,
        );
        controller = SurfaceController(catalogs: [catalog]);
        conversation = Conversation(
          controller: controller,
          transport: adapter.transport,
        );

        await conversation.sendRequest(ChatMessage.user('hi'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });

      // The transport path completed: the surface exists and has components.
      expect(controller.activeSurfaceIds, contains('s1'));

      // Render the surface the AI just created and assert it shows the widget.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Surface(surfaceContext: controller.contextFor('s1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Surface), findsOneWidget);
      // The basic Text item renders Markdown (RichText), so match rich text.
      expect(
        find.textContaining('Hello GenUI', findRichText: true),
        findsOneWidget,
      );

      conversation.dispose();
      adapter.dispose();
      controller.dispose();
    },
  );
}
