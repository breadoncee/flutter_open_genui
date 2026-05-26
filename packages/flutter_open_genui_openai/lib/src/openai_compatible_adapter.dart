// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:genui/genui.dart' show ChatMessage, ChatMessageRole;

/// Adapter for any service that speaks the OpenAI Chat Completions API.
///
/// OpenAI, OpenRouter, and Ollama's `/v1` endpoint all share this wire format
/// (SSE stream of `chat.completion.chunk` objects), so they reuse this class
/// with only a different default endpoint and headers. It streams the model's
/// raw text; A2UI parsing/healing happens in the [GenUiAdapter] base class.
class OpenAiCompatibleAdapter extends GenUiAdapter {
  /// Creates an OpenAI-compatible adapter. [defaultBaseUrl] is used when
  /// [GenUiAdapterConfig.baseUrl] is not set.
  OpenAiCompatibleAdapter({
    required super.config,
    required this.defaultBaseUrl,
    super.healer,
  });

  /// The endpoint used when the config does not override `baseUrl`.
  final String defaultBaseUrl;

  String get _baseUrl =>
      (config.baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r'/+$'), '');

  @override
  Stream<String> streamCompletion(GenUiRequest request) async* {
    final dio = config.dio ?? Dio();

    final response = await dio.post<ResponseBody>(
      '$_baseUrl/chat/completions',
      data: <String, Object?>{
        'model': config.model,
        'stream': true,
        'messages': _buildMessages(request),
        if (config.temperature != null) 'temperature': config.temperature,
        if (config.maxTokens != null) 'max_tokens': config.maxTokens,
      },
      options: Options(responseType: ResponseType.stream, headers: _headers()),
    );

    final lines = response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue; // skip SSE comments/blanks
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') break;

      final Object? decoded;
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        continue;
      }
      final content = _contentDelta(decoded);
      if (content != null && content.isNotEmpty) yield content;
    }
  }

  Map<String, String> _headers() => <String, String>{
    'content-type': 'application/json',
    if (config.apiKey != null) 'authorization': 'Bearer ${config.apiKey}',
    ...config.headers,
  };

  List<Map<String, Object?>> _buildMessages(GenUiRequest request) =>
      <Map<String, Object?>>[
        <String, Object?>{'role': 'system', 'content': request.systemPrompt},
        for (final message in request.history)
          <String, Object?>{
            'role': _role(message.role),
            'content': _content(message),
          },
      ];

  static String _role(ChatMessageRole role) => switch (role) {
    ChatMessageRole.system => 'system',
    ChatMessageRole.user => 'user',
    ChatMessageRole.model => 'assistant',
  };

  /// Uses the message's text; falls back to encoding non-text parts (e.g. a UI
  /// interaction or validation error sent back by the controller) as JSON so
  /// the model still sees them.
  static String _content(ChatMessage message) => message.text.isNotEmpty
      ? message.text
      : message.parts.map((p) => jsonEncode(p.toJson())).join();

  static String? _contentDelta(Object? decoded) {
    if (decoded is! Map<String, Object?>) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map<String, Object?>) return null;
    final delta = first['delta'];
    if (delta is! Map<String, Object?>) return null;
    final content = delta['content'];
    return content is String ? content : null;
  }
}
