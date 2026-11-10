// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genai_primitives/genai_primitives.dart' show DataPart;

/// Replays canned chunks as the model's reply and records each request.
class _FakeAdapter extends GenUiAdapter {
  _FakeAdapter(this.chunks)
    : super(
        config: GenUiAdapterConfig(
          model: 'fake',
          catalog: BasicCatalog.v0_9(),
          systemPrompt: 'SYSTEM',
        ),
      );

  final List<String> chunks;
  final List<GenUiRequest> requests = [];

  @override
  Stream<String> streamCompletion(GenUiRequest request) {
    requests.add(request);
    return Stream.fromIterable(chunks);
  }
}

const String _create =
    '{"version":"v0.9","createSurface":'
    '{"surfaceId":"s1","catalogId":"${BasicCatalog.v0_9Id}"}}';
const String _update =
    '{"version":"v0.9","updateComponents":{"surfaceId":"s1",'
    '"components":[{"id":"root","component":"Text","text":"Hello"}]}}';

void main() {
  test('streams text and A2UI messages and records the reply', () async {
    final adapter = _FakeAdapter([
      'Sure! <a2ui-json>[$_create,',
      // Trailing comma: healed before the parser reads it.
      '$_update,]</a2ui-json>',
    ]);
    final texts = <String>[];
    final messages = <AgentToRendererMessage>[];
    final errors = <Object>[];
    adapter.incomingText.listen(texts.add);
    adapter.incomingMessages.listen(messages.add, onError: errors.add);

    await adapter.sendRequest(ChatMessage.user('hi'));
    await pumpEventQueue();

    expect(texts.join(), 'Sure!');
    expect(messages.map((m) => m.runtimeType), [
      CreateSurfaceMessage,
      UpdateComponentsMessage,
    ]);
    expect(errors, isEmpty);
    expect(adapter.requests.single.systemPrompt, 'SYSTEM');
    expect(adapter.history.map((m) => m.role), [
      ChatMessageRole.user,
      ChatMessageRole.model,
    ]);
    adapter.dispose();
  });

  test('reports a rejected block as an error and keeps reading', () async {
    final adapter = _FakeAdapter([
      '<a2ui-json>[{"version":"v0.9","createSurface":'
          '{"surfaceId":"s1","catalogId":"unknown"}}]</a2ui-json>',
      'Then: <a2ui-json>[$_create, $_update]</a2ui-json>',
    ]);
    final messages = <AgentToRendererMessage>[];
    final errors = <Object>[];
    adapter.incomingMessages.listen(messages.add, onError: errors.add);

    await adapter.sendRequest(ChatMessage.user('hi'));
    await pumpEventQueue();

    expect(errors.single, isA<A2uiError>());
    expect(messages, hasLength(2));
    adapter.dispose();
  });

  test('sendInteraction sends the message as genui framed it', () async {
    final adapter = _FakeAdapter(const []);
    final action = A2uiRendererAction(
      name: 'submit',
      surfaceId: 's1',
      sourceComponentId: 'button',
      timestamp: DateTime.utc(2026),
      context: const {'x': 1},
    );

    await adapter.sendInteraction(
      ActionMessage(version: 'v0.9', action: action),
    );

    final message = adapter.history.single;
    expect(message.role, ChatMessageRole.user);
    expect(message.text, isEmpty);
    final part = message.parts.single as DataPart;
    expect(part.mimeType, 'application/vnd.genui.interaction+json');
    final interaction =
        (jsonDecode(utf8.decode(part.bytes)) as Map)['interaction'] as String;
    expect(jsonDecode(interaction), {
      'version': 'v0.9',
      'action': action.toJson(),
    });
    adapter.dispose();
  });
}
