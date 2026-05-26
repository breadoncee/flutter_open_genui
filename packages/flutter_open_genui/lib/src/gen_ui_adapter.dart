// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:genui/genui.dart' show A2uiTransportAdapter, ChatMessage;

import 'gen_ui_adapter_config.dart';
import 'gen_ui_request.dart';
import 'healing/a2ui_json_healer.dart';

/// Base class every provider adapter extends.
///
/// It owns the official [A2uiTransportAdapter] and wires its `onSend` callback
/// to the streaming loop: assemble the request, call [streamCompletion], pipe
/// the chunks through the [A2uiJsonHealer], and feed them to the transport. A
/// new provider only needs to implement [streamCompletion].
///
/// ```dart
/// final adapter = OpenAiGenUiAdapter(
///   apiKey: key,
///   model: 'gpt-5.4',
///   systemPrompt: GenUiPrompt.fromCatalog(catalog),
/// );
/// final conversation = Conversation(
///   controller: SurfaceController(catalogs: [catalog]),
///   transport: adapter.transport,
/// );
/// await conversation.sendRequest(ChatMessage.user('Plan me a trip'));
/// ```
abstract class GenUiAdapter {
  /// Creates an adapter with the given [config]. A custom [healer] may be
  /// supplied (e.g. to observe repairs); the default repairs silently.
  GenUiAdapter({
    required this.config,
    A2uiJsonHealer healer = const A2uiJsonHealer(),
  }) : _healer = healer {
    _transport = A2uiTransportAdapter(onSend: _handleSend);
  }

  /// Shared configuration (model, key, endpoint, system prompt, ...).
  final GenUiAdapterConfig config;

  final A2uiJsonHealer _healer;
  late final A2uiTransportAdapter _transport;
  final List<ChatMessage> _history = <ChatMessage>[];

  /// The transport to hand to the official `Conversation`.
  A2uiTransportAdapter get transport => _transport;

  /// An unmodifiable view of the conversation history maintained internally.
  List<ChatMessage> get history => List.unmodifiable(_history);

  /// Calls the provider's streaming API and yields raw text chunks as they
  /// arrive. Implementations should not parse A2UI — the base class heals and
  /// forwards the stream. This is the one method a new provider must override.
  Stream<String> streamCompletion(GenUiRequest request);

  Future<void> _handleSend(ChatMessage message) async {
    _history.add(message);
    final request = GenUiRequest(
      systemPrompt: config.systemPrompt,
      history: List.unmodifiable(_history),
    );

    final response = StringBuffer();
    await for (final chunk in _healer.bind(streamCompletion(request))) {
      response.write(chunk);
      _transport.addChunk(chunk);
    }

    if (response.isNotEmpty) {
      _history.add(ChatMessage.model(response.toString()));
    }
  }

  /// Releases the transport's resources.
  void dispose() => _transport.dispose();
}
