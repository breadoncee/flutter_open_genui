// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:a2ui_agent/a2ui_agent.dart';
import 'package:a2ui_core/a2ui_core.dart';
import 'package:genai_primitives/genai_primitives.dart'
    show ChatMessage, DataPart;

import 'gen_ui_adapter_config.dart';
import 'gen_ui_request.dart';
import 'healing/a2ui_json_healer.dart';
import 'prompt.dart';

/// Base class every provider adapter extends.
///
/// It runs the streaming loop for each turn: assemble the request, call
/// [streamCompletion], pipe the chunks through the [A2uiJsonHealer], and read
/// them with an `a2ui_agent` response stream for the catalog in [config]. The
/// model's text arrives on [incomingText] and its A2UI messages on
/// [incomingMessages]. A new provider only needs to implement
/// [streamCompletion].
///
/// ```dart
/// final catalog = v0_9.basicCatalog();
/// final adapter = OpenAiGenUiAdapter(
///   apiKey: key,
///   model: 'gpt-5.4',
///   catalog: catalog,
///   systemPrompt: GenUiPrompt.fromCatalog(catalog),
/// );
/// final processor = MessageProcessor<ComponentImplementation>(
///   catalogs: [catalog],
///   validationConfig: ValidationConfig.relaxed,
///   reportErrorsOnly: true,
/// );
/// adapter.incomingMessages.listen(
///   (message) => processor.processMessages(
///     AgentToRendererMessagePayload.of(message),
///   ),
/// );
/// processor.model.onAction.subscribe(
///   (action) => adapter.sendInteraction(
///     ActionMessage(version: 'v0.9', action: action),
///   ),
/// );
/// await adapter.sendRequest(ChatMessage.user('Plan me a trip'));
/// ```
abstract class GenUiAdapter {
  /// Creates an adapter with the given [config]. A custom [healer] may be
  /// supplied (e.g. to observe repairs); the default repairs silently.
  GenUiAdapter({
    required this.config,
    A2uiJsonHealer healer = const A2uiJsonHealer(),
  }) : _healer = healer,
       _agent = createChatAgent(config.catalog);

  /// Shared configuration (model, key, endpoint, catalog, system prompt, ...).
  final GenUiAdapterConfig config;

  final A2uiJsonHealer _healer;
  final A2uiRequestProcessor _agent;
  final List<ChatMessage> _history = <ChatMessage>[];
  final StreamController<String> _text = StreamController.broadcast();
  final StreamController<AgentToRendererMessage> _messages =
      StreamController.broadcast();

  // The MIME type of genui's UiInteractionPart.
  static const String _interactionMimeType =
      'application/vnd.genui.interaction+json';

  /// The text the model writes outside A2UI blocks, as it streams.
  Stream<String> get incomingText => _text.stream;

  /// The A2UI messages the model writes, checked against the catalog, for a
  /// renderer such as `a2ui_core`'s `MessageProcessor`.
  ///
  /// A block the model wrote that cannot be read or is rejected is added to
  /// this stream as an [A2uiError], and the rest of the reply is still read.
  Stream<AgentToRendererMessage> get incomingMessages => _messages.stream;

  /// An unmodifiable view of the conversation history maintained internally.
  List<ChatMessage> get history => List.unmodifiable(_history);

  /// Calls the provider's streaming API and yields raw text chunks as they
  /// arrive. Implementations should not parse A2UI — the base class heals and
  /// forwards the stream. This is the one method a new provider must override.
  Stream<String> streamCompletion(GenUiRequest request);

  /// Adds [message] to the history, streams the model's reply to
  /// [incomingText] and [incomingMessages], and adds the reply to the history.
  ///
  /// Errors from [streamCompletion], such as HTTP failures, are rethrown.
  Future<void> sendRequest(ChatMessage message) async {
    _history.add(message);
    final request = GenUiRequest(
      systemPrompt: config.systemPrompt,
      history: List.unmodifiable(_history),
    );

    // Each reply may only create surfaces, so it is checked on its own.
    final ContinuingResponseStream reply = _agent.openContinuingStream();
    var replyEnded = false;
    // The reply reads past a block it rejects and returns an ErrorPart for
    // it; an error it throws ends the reply.
    void read(List<StreamPart> Function() step) {
      if (replyEnded) return;
      try {
        step().forEach(_deliver);
      } on A2uiError catch (error, stackTrace) {
        replyEnded = true;
        error.partialResults.forEach(_deliver);
        _messages.addError(error, stackTrace);
      }
    }

    final response = StringBuffer();
    await for (final chunk in _healer.bind(streamCompletion(request))) {
      response.write(chunk);
      read(() => reply.feed(chunk));
    }
    read(reply.close);

    if (response.isNotEmpty) {
      _history.add(ChatMessage.model(response.toString()));
    }
  }

  /// Sends [message], an action or error from the renderer, to the model as
  /// the next turn, as [sendRequest] does.
  ///
  /// The turn is a user message with no text and one part holding
  /// [message]'s JSON, which genui's `Conversation` sent for every action and
  /// error of its `SurfaceController`.
  Future<void> sendInteraction(RendererToAgentMessage message) => sendRequest(
    ChatMessage.user(
      '',
      parts: [
        DataPart(
          utf8.encode(
            jsonEncode({'interaction': jsonEncode(message.toJson())}),
          ),
          mimeType: _interactionMimeType,
        ),
      ],
    ),
  );

  void _deliver(StreamPart part) {
    switch (part) {
      case TextPart(:final text):
        _text.add(text);
      case A2uiPart(:final a2ui):
        a2ui.forEach(_messages.add);
      case ErrorPart(:final error):
        _messages.addError(error);
    }
  }

  /// Closes [incomingText] and [incomingMessages].
  void dispose() {
    unawaited(_text.close());
    unawaited(_messages.close());
  }
}
