// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dio/dio.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';

/// Drives Flutter GenUI through [OpenRouter](https://openrouter.ai), which
/// exposes dozens of models behind one OpenAI-compatible API.
///
/// Reuses [OpenAiCompatibleAdapter] verbatim — only the [defaultBaseUrl] and
/// the optional OpenRouter usage-tracking headers differ.
///
/// ```dart
/// final adapter = OpenRouterGenUiAdapter(
///   apiKey: myKey,
///   model: 'anthropic/claude-sonnet-4-6',
///   systemPrompt: GenUiPrompt.fromCatalog(catalog),
///   referer: 'https://myapp.example.com', // optional
///   title: 'MyApp',                       // optional
/// );
/// ```
class OpenRouterGenUiAdapter extends OpenAiCompatibleAdapter {
  /// Creates an OpenRouter adapter.
  ///
  /// [referer] / [title] populate the `HTTP-Referer` and `X-Title` headers
  /// OpenRouter uses for ranking and usage attribution. Both are optional.
  OpenRouterGenUiAdapter({
    required String apiKey,
    required String model,
    required String systemPrompt,
    String? baseUrl,
    String? referer,
    String? title,
    double? temperature,
    int? maxTokens,
    Map<String, String> headers = const {},
    Dio? dio,
    super.healer,
  }) : super(
         defaultBaseUrl: 'https://openrouter.ai/api/v1',
         config: GenUiAdapterConfig(
           model: model,
           systemPrompt: systemPrompt,
           apiKey: apiKey,
           baseUrl: baseUrl,
           temperature: temperature,
           maxTokens: maxTokens,
           headers: {
             if (referer != null) 'HTTP-Referer': referer,
             if (title != null) 'X-Title': title,
             ...headers,
           },
           dio: dio,
         ),
       );
}
