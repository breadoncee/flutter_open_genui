// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_anthropic/flutter_open_genui_anthropic.dart';
import 'package:flutter_open_genui_ollama/flutter_open_genui_ollama.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';
import 'package:flutter_open_genui_openrouter/flutter_open_genui_openrouter.dart';
import 'package:genui/genui.dart';

/// Provide keys at run time:
/// `fvm flutter run --dart-define=OPENAI_API_KEY=sk-... \`
/// `              --dart-define=ANTHROPIC_API_KEY=sk-ant-... \`
/// `              --dart-define=OPENROUTER_API_KEY=or-...`
const String _openAiKey = String.fromEnvironment('OPENAI_API_KEY');
const String _anthropicKey = String.fromEnvironment('ANTHROPIC_API_KEY');
const String _openRouterKey = String.fromEnvironment('OPENROUTER_API_KEY');

void main() => runApp(const ExampleApp());

/// The widget catalog the model is allowed to use. Same catalog is rendered
/// regardless of which provider is generating it — the whole point.
final Catalog appCatalog = BasicCatalogItems.asCatalog();

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'flutter_open_genui',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const ChatPage(),
  );
}

/// The providers wired into this example. Add a new one by extending
/// [GenUiAdapter] and adding an entry here.
enum Provider {
  openai('OpenAI', 'gpt-5.4'),
  openrouter('OpenRouter', 'anthropic/claude-sonnet-4-6'),
  anthropic('Anthropic', 'claude-sonnet-4-6'),
  ollama('Ollama (local)', 'llama3.1');

  const Provider(this.label, this.defaultModel);

  final String label;
  final String defaultModel;
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late SurfaceController _controller;
  late GenUiAdapter _adapter;
  late Conversation _conversation;
  StreamSubscription<ConversationEvent>? _events;

  Provider _provider = Provider.openai;
  final List<String> _surfaceIds = <String>[];
  final TextEditingController _input = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = SurfaceController(catalogs: [appCatalog]);
    _wireProvider(_provider);
  }

  /// (Re)builds the adapter + conversation for the chosen [provider], reusing
  /// the same [_controller] so existing surfaces keep rendering.
  void _wireProvider(Provider provider) {
    _events?.cancel();
    if (_provider != provider) {
      // ignore: unawaited_futures
      Future<void>.sync(_conversation.dispose);
      _adapter.dispose();
    }
    _provider = provider;

    final systemPrompt = GenUiPrompt.fromCatalog(appCatalog);
    _adapter = switch (provider) {
      Provider.openai => OpenAiGenUiAdapter(
        apiKey: _openAiKey,
        model: provider.defaultModel,
        systemPrompt: systemPrompt,
      ),
      Provider.openrouter => OpenRouterGenUiAdapter(
        apiKey: _openRouterKey,
        model: provider.defaultModel,
        systemPrompt: systemPrompt,
        referer: 'https://github.com/breadoncee/flutter_open_genui',
        title: 'flutter_open_genui example',
      ),
      Provider.anthropic => AnthropicGenUiAdapter(
        apiKey: _anthropicKey,
        model: provider.defaultModel,
        systemPrompt: systemPrompt,
      ),
      Provider.ollama => OllamaGenUiAdapter(
        model: provider.defaultModel,
        systemPrompt: systemPrompt,
      ),
    };
    _conversation = Conversation(
      controller: _controller,
      transport: _adapter.transport,
    );
    _events = _conversation.events.listen(_onEvent);
  }

  bool get _hasKeyForProvider => switch (_provider) {
    Provider.openai => _openAiKey.isNotEmpty,
    Provider.openrouter => _openRouterKey.isNotEmpty,
    Provider.anthropic => _anthropicKey.isNotEmpty,
    Provider.ollama => true, // no key needed
  };

  void _onEvent(ConversationEvent event) {
    switch (event) {
      case ConversationSurfaceAdded(:final surfaceId):
        setState(() => _surfaceIds.add(surfaceId));
      case ConversationSurfaceRemoved(:final surfaceId):
        setState(() => _surfaceIds.remove(surfaceId));
      case ConversationWaiting():
        setState(() => _busy = true);
      case ConversationError(:final error):
        setState(() => _busy = false);
        _showError('$error');
      case ConversationComponentsUpdated() || ConversationContentReceived():
        setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await _conversation.sendRequest(ChatMessage.user(text));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _events?.cancel();
    _conversation.dispose();
    _adapter.dispose();
    _controller.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_open_genui'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Provider>(
                value: _provider,
                onChanged: (p) {
                  if (p != null && p != _provider) {
                    setState(() => _wireProvider(p));
                  }
                },
                items: [
                  for (final p in Provider.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_hasKeyForProvider) _MissingKeyBanner(provider: _provider),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _surfaceIds.isEmpty
                ? Center(
                    child: Text(
                      'Ask for a UI to get started '
                      '— provider: ${_provider.label}',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final id in _surfaceIds)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Surface(
                              surfaceContext: _controller.contextFor(id),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Plan me a weekend trip',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _send, child: const Text('Send')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingKeyBanner extends StatelessWidget {
  const _MissingKeyBanner({required this.provider});
  final Provider provider;

  String get _envVar => switch (provider) {
    Provider.openai => 'OPENAI_API_KEY',
    Provider.openrouter => 'OPENROUTER_API_KEY',
    Provider.anthropic => 'ANTHROPIC_API_KEY',
    Provider.ollama => '', // unreachable; Ollama is keyless
  };

  @override
  Widget build(BuildContext context) => MaterialBanner(
    backgroundColor: Theme.of(context).colorScheme.errorContainer,
    content: Text('No $_envVar. Run with --dart-define=$_envVar=...'),
    actions: const [SizedBox.shrink()],
  );
}
