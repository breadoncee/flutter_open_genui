// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dio/dio.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';

/// Drives Flutter GenUI through a local [Ollama](https://ollama.com) server.
///
/// Talks to Ollama's OpenAI-compatible `/v1/chat/completions` endpoint, so it
/// reuses [OpenAiCompatibleAdapter] — only the default endpoint
/// (`http://localhost:11434/v1`) and the lack of an API key differ.
///
/// ```dart
/// final adapter = OllamaGenUiAdapter(
///   model: 'llama3.1',
///   systemPrompt: GenUiPrompt.fromCatalog(catalog),
/// );
/// ```
///
/// **Notes for local use:**
/// - The A2UI system prompt is large (typically 3,000–5,000+ tokens). Small
///   models with tight context windows may struggle — keep your catalog
///   minimal, or trim with `PromptBuilder`'s fragment options.
/// - Tool calling support varies by model; this adapter sticks to the
///   prompt-first path (model emits A2UI JSON in fenced blocks), which the
///   shared healer repairs and forwards.
class OllamaGenUiAdapter extends OpenAiCompatibleAdapter {
  /// Creates an Ollama adapter. [baseUrl] overrides the local default — useful
  /// if Ollama runs on a different host/port or behind a proxy.
  OllamaGenUiAdapter({
    required String model,
    required String systemPrompt,
    String? baseUrl,
    double? temperature,
    int? maxTokens,
    Map<String, String> headers = const {},
    Dio? dio,
    super.healer,
  }) : super(
         defaultBaseUrl: 'http://localhost:11434/v1',
         config: GenUiAdapterConfig(
           model: model,
           systemPrompt: systemPrompt,
           apiKey: null, // Ollama is keyless.
           baseUrl: baseUrl,
           temperature: temperature,
           maxTokens: maxTokens,
           headers: headers,
           dio: dio,
         ),
       );
}
