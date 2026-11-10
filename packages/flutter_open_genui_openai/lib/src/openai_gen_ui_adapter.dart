// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:a2ui_core/a2ui_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';

import 'openai_compatible_adapter.dart';

/// Drives Flutter GenUI with OpenAI's Chat Completions API.
///
/// ```dart
/// final adapter = OpenAiGenUiAdapter(
///   apiKey: myKey,
///   model: 'gpt-5.4',
///   catalog: catalog,
///   systemPrompt: GenUiPrompt.fromCatalog(catalog),
/// );
/// adapter.incomingMessages.listen(
///   (message) => processor.processMessages(
///     AgentToRendererMessagePayload.of(message),
///   ),
/// );
/// await adapter.sendRequest(ChatMessage.user('Plan me a trip'));
/// ```
///
/// Point [baseUrl] at a backend proxy to keep the key off the client (the
/// recommended production setup).
class OpenAiGenUiAdapter extends OpenAiCompatibleAdapter {
  /// Creates an OpenAI adapter.
  OpenAiGenUiAdapter({
    required String apiKey,
    required String model,
    required CatalogApi catalog,
    required String systemPrompt,
    String? baseUrl,
    double? temperature,
    int? maxTokens,
    Map<String, String> headers = const {},
    Dio? dio,
    super.healer,
  }) : super(
         defaultBaseUrl: 'https://api.openai.com/v1',
         config: GenUiAdapterConfig(
           model: model,
           catalog: catalog,
           systemPrompt: systemPrompt,
           apiKey: apiKey,
           baseUrl: baseUrl,
           temperature: temperature,
           maxTokens: maxTokens,
           headers: headers,
           dio: dio,
         ),
       );
}
