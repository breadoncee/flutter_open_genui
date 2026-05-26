// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dio/dio.dart';

/// Configuration shared by every provider adapter.
///
/// [systemPrompt] is the A2UI instruction block (build it with
/// `GenUiPrompt.fromCatalog` or `PromptBuilder.chat(...).systemPromptJoined()`).
/// Set [baseUrl] to point an adapter at a local server (Ollama), an
/// OpenAI-compatible gateway (OpenRouter), or a backend proxy that holds the
/// real key — the recommended production path. Inject [dio] in tests.
class GenUiAdapterConfig {
  /// Creates a configuration.
  const GenUiAdapterConfig({
    required this.model,
    required this.systemPrompt,
    this.apiKey,
    this.baseUrl,
    this.temperature,
    this.maxTokens,
    this.headers = const {},
    this.dio,
  });

  /// The provider model identifier (e.g. `gpt-5.4`, `claude-sonnet-4-6`).
  final String model;

  /// The A2UI system instructions sent on every turn.
  final String systemPrompt;

  /// The provider API key. May be `null` for keyless providers (Ollama) or
  /// when [baseUrl] points at a proxy that injects the key.
  final String? apiKey;

  /// Overrides the provider's default endpoint. Useful for proxies, local
  /// servers, and OpenAI-compatible gateways.
  final String? baseUrl;

  /// Optional sampling temperature.
  final double? temperature;

  /// Optional cap on generated tokens.
  final int? maxTokens;

  /// Extra HTTP headers to attach to every request.
  final Map<String, String> headers;

  /// A custom [Dio] client. Injected by tests; adapters create their own when
  /// this is `null`.
  final Dio? dio;
}
