// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:genui/genui.dart' show ChatMessage;

/// The assembled request a [GenUiAdapter] hands to a provider's streaming API.
///
/// The base class builds this on every turn: the A2UI [systemPrompt] plus the
/// running conversation [history] (the latest user/submit message is last).
class GenUiRequest {
  /// Creates a request.
  const GenUiRequest({required this.systemPrompt, required this.history});

  /// The A2UI system instructions (typically from `PromptBuilder.chat`).
  final String systemPrompt;

  /// The full conversation so far, oldest first. The last entry is the message
  /// that triggered this turn.
  final List<ChatMessage> history;

  /// The message that triggered this turn.
  ChatMessage get latestMessage => history.last;
}
