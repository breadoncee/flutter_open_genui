// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:a2ui_agent/a2ui_agent.dart';
import 'package:a2ui_core/a2ui_core.dart';

/// Convenience helpers for producing the A2UI system prompt that adapters send.
abstract final class GenUiPrompt {
  /// Builds the chat system prompt for [catalog], optionally prepending
  /// [fragments] (persona, rules, etc.).
  ///
  /// The A2UI part comes from `a2ui_agent`'s direct JSON format, which asks
  /// the model for a JSON array of A2UI messages in `<a2ui-json>` tags. As
  /// with genui's `PromptBuilder.chat`, each reply may only create new
  /// surfaces. Adapters read replies in this format, so give the adapter the
  /// same [catalog]. Note this prompt is large (commonly 3,000–5,000+ tokens)
  /// because it embeds the full A2UI schema — relevant for small/local models
  /// with tight context windows.
  static String fromCatalog(
    CatalogApi catalog, {
    Iterable<String> fragments = const [],
  }) => [
    ...fragments,
    ..._chatRules,
    createChatAgent(catalog).promptSnippet,
  ].map((fragment) => fragment.trim()).join('\n\n');

  // The rules genui's PromptBuilder.chat added around the A2UI schema.
  static const List<String> _chatRules = [
    'IMPORTANT: You do not have the ability to execute code. If you need to '
        'perform calculations, do them yourself.',
    'IMPORTANT: You do not have the ability to use tools for UI generation.',
    'IMPORTANT: You do not have the ability to use function calls for UI '
        'generation.',
    'IMPORTANT: DO NOT update or modify surfaces created in previous turns. '
        'If the UI needs to change, you MUST create a NEW surface with a new '
        'unique `surfaceId`. You may only use `updateComponents` to populate '
        'the components of a freshly created surface.',
  ];
}

/// Creates the `a2ui_agent` processor that writes the A2UI part of
/// [GenUiPrompt.fromCatalog] for [catalog] and reads the replies to it.
A2uiRequestProcessor createChatAgent(CatalogApi catalog) =>
    A2uiGenerator(
      catalogs: [CatalogConfig(catalog)],
      inferenceFormatFactory: const DirectJsonFormatFactory(
        // Each reply creates new surfaces, as genui's PromptBuilder.chat
        // allowed.
        allowedMessages: ['createSurface', 'updateComponents'],
        // Emit whole components, as genui's parser did.
        bufferIncompleteComponents: true,
      ),
    ).createProcessor(
      A2uiRendererCapabilities.forCatalogIds([
        catalog.id,
      ], version: catalog.protocolVersion ?? A2uiProtocolVersion.v0_9),
    );
