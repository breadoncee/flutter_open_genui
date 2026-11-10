// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/v0_9/basic_catalog.dart' as v0_9;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';
import 'package:flutter_test/flutter_test.dart';

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

CatalogImplementation _catalog() =>
    v0_9.basicCatalog().derive(catalogId: 'test_catalog', components: ['Text']);

const createMsg =
    '{"version":"v0.9","createSurface":'
    '{"surfaceId":"s1","catalogId":"test_catalog","sendDataModel":true}}';
// Trailing comma in the array is malformed JSON — exercises healing.
const updateMsg =
    '{"version":"v0.9","updateComponents":{"surfaceId":"s1",'
    '"components":[{"id":"root","component":"Text",'
    '"text":"Hello GenUI"},]}}';

/// Feeds the adapter's messages to [processor] and collects its errors.
List<Object> _connect(
  GenUiAdapter adapter,
  MessageProcessor<ComponentImplementation> processor,
) {
  final errors = <Object>[];
  adapter.incomingMessages.listen(
    (message) =>
        processor.processMessages(AgentToRendererMessagePayload.of(message)),
    onError: errors.add,
  );
  processor.model.onError.subscribe(errors.add);
  return errors;
}

void main() {
  test('adapter path: SSE creates and populates a surface', () async {
    final catalog = _catalog();
    final fake = _FakeSse([
      _delta('Sure!\n<a2ui-json>\n[$createMsg,\n'),
      _delta('$updateMsg]\n</a2ui-json>'),
      'data: [DONE]',
    ]);
    final adapter = OpenAiGenUiAdapter(
      apiKey: 'test',
      model: 'gpt-5.4',
      catalog: catalog,
      systemPrompt: GenUiPrompt.fromCatalog(catalog),
      dio: Dio()..httpClientAdapter = fake,
    );
    final processor = MessageProcessor<ComponentImplementation>(
      catalogs: [catalog],
      validationConfig: ValidationConfig.relaxed,
      reportErrorsOnly: true,
    );
    final errors = _connect(adapter, processor);

    await adapter.sendRequest(ChatMessage.user('hi'));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(errors, isEmpty);
    expect(processor.model.getSurface('s1'), isNotNull);

    adapter.dispose();
    processor.dispose();
  });

  testWidgets(
    'OpenAI SSE → healer → adapter → processor renders an A2uiSurface',
    (tester) async {
      final catalog = _catalog();

      late final MessageProcessor<ComponentImplementation> processor;
      late final OpenAiGenUiAdapter adapter;
      late final List<Object> errors;

      // Construct AND drive everything inside runAsync so the adapter's stream
      // controllers bind to the real async zone (not the fake test clock);
      // otherwise the dio stream and parser callbacks never fire.
      await tester.runAsync(() async {
        final fake = _FakeSse([
          _delta('Sure!\n<a2ui-json>\n[$createMsg,\n'),
          _delta('$updateMsg]\n</a2ui-json>'),
          'data: [DONE]',
        ]);

        adapter = OpenAiGenUiAdapter(
          apiKey: 'test',
          model: 'gpt-5.4',
          catalog: catalog,
          systemPrompt: GenUiPrompt.fromCatalog(catalog),
          dio: Dio()..httpClientAdapter = fake,
        );
        processor = MessageProcessor<ComponentImplementation>(
          catalogs: [catalog],
          validationConfig: ValidationConfig.relaxed,
          reportErrorsOnly: true,
        );
        errors = _connect(adapter, processor);

        await adapter.sendRequest(ChatMessage.user('hi'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });

      // The adapter path completed: the surface exists and has components.
      expect(errors, isEmpty);
      final surface = processor.model.getSurface('s1');
      expect(surface, isNotNull);

      // Render the surface the AI just created and assert it shows the widget.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: A2uiSurface(surface: surface!)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(A2uiSurface), findsOneWidget);
      expect(
        find.textContaining('Hello GenUI', findRichText: true),
        findsOneWidget,
      );

      adapter.dispose();
      processor.dispose();
    },
  );
}
