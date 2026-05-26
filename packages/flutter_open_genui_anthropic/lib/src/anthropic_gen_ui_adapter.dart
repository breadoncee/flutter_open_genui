// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:genui/genui.dart' show ChatMessageRole;

/// Drives Flutter GenUI with Anthropic's Claude Messages API.
///
/// Cannot reuse the OpenAI-compatible base because Anthropic's wire format
/// differs in several ways:
///
/// - The system prompt is a top-level field, not a `system` message.
/// - Messages use only `user`/`assistant` roles.
/// - `max_tokens` is **required** (defaults to 4096 here when not set).
/// - Authentication is `x-api-key` + `anthropic-version`, not `Bearer`.
/// - The streamed SSE has named events (`content_block_delta`, etc.) and
///   text arrives in `delta.text_delta.text`, not `choices[0].delta.content`.
///
/// ```dart
/// final adapter = AnthropicGenUiAdapter(
///   apiKey: myKey,
///   model: 'claude-sonnet-4-6',
///   systemPrompt: GenUiPrompt.fromCatalog(catalog),
/// );
/// ```
class AnthropicGenUiAdapter extends GenUiAdapter {
  /// Creates an Anthropic adapter.
  AnthropicGenUiAdapter({
    required String apiKey,
    required String model,
    required String systemPrompt,
    String baseUrl = 'https://api.anthropic.com',
    String anthropicVersion = '2023-06-01',
    double? temperature,
    int maxTokens = 4096,
    Map<String, String> headers = const {},
    Dio? dio,
    super.healer,
  }) : super(
         config: GenUiAdapterConfig(
           model: model,
           systemPrompt: systemPrompt,
           apiKey: apiKey,
           baseUrl: baseUrl,
           temperature: temperature,
           maxTokens: maxTokens,
           headers: {'anthropic-version': anthropicVersion, ...headers},
           dio: dio,
         ),
       );

  String get _baseUrl => (config.baseUrl ?? 'https://api.anthropic.com')
      .replaceAll(RegExp(r'/+$'), '');

  @override
  Stream<String> streamCompletion(GenUiRequest request) async* {
    final dio = config.dio ?? Dio();

    final response = await dio.post<ResponseBody>(
      '$_baseUrl/v1/messages',
      data: <String, Object?>{
        'model': config.model,
        'system': request.systemPrompt,
        'messages': _buildMessages(request),
        'max_tokens': config.maxTokens ?? 4096,
        'stream': true,
        if (config.temperature != null) 'temperature': config.temperature,
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: <String, String>{
          'content-type': 'application/json',
          if (config.apiKey != null) 'x-api-key': config.apiKey!,
          ...config.headers,
        },
      ),
    );

    final lines = response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue; // skip `event:` and blanks
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;

      final Object? decoded;
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        continue;
      }
      final text = _textDelta(decoded);
      if (text != null && text.isNotEmpty) yield text;
    }
  }

  /// Anthropic disallows `system` messages in the array — the system prompt is
  /// a top-level field. Drop them here and map roles to `user` / `assistant`.
  List<Map<String, Object?>> _buildMessages(GenUiRequest request) {
    final result = <Map<String, Object?>>[];
    for (final message in request.history) {
      if (message.role == ChatMessageRole.system) continue;
      result.add(<String, Object?>{
        'role': message.role == ChatMessageRole.user ? 'user' : 'assistant',
        'content': message.text.isNotEmpty
            ? message.text
            : message.parts.map((p) => jsonEncode(p.toJson())).join(),
      });
    }
    return result;
  }

  /// Extracts the text from a `content_block_delta` event with a `text_delta`,
  /// or `null` for any other event (`message_start`, `ping`, tool_use, etc.).
  static String? _textDelta(Object? decoded) {
    if (decoded is! Map<String, Object?>) return null;
    if (decoded['type'] != 'content_block_delta') return null;
    final delta = decoded['delta'];
    if (delta is! Map<String, Object?>) return null;
    if (delta['type'] != 'text_delta') return null;
    final text = delta['text'];
    return text is String ? text : null;
  }
}
