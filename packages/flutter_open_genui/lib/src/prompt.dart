// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:genui/genui.dart';

/// Convenience helpers for producing the A2UI system prompt that adapters send.
abstract final class GenUiPrompt {
  /// Builds the chat system prompt for [catalog], optionally prepending
  /// [fragments] (persona, rules, etc.).
  ///
  /// Wraps the official `PromptBuilder.chat`. Note this prompt is large
  /// (commonly 3,000–5,000+ tokens) because it embeds the full A2UI schema —
  /// relevant for small/local models with tight context windows.
  static String fromCatalog(
    Catalog catalog, {
    Iterable<String> fragments = const [],
  }) => PromptBuilder.chat(
    catalog: catalog,
    systemPromptFragments: fragments,
  ).systemPromptJoined();
}
