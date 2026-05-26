// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';
import 'package:genui/genui.dart';

/// Provide your key at run time:
/// `fvm flutter run --dart-define=OPENAI_API_KEY=sk-...`
const String _openAiKey = String.fromEnvironment('OPENAI_API_KEY');

void main() => runApp(const ExampleApp());

/// The widget catalog the model is allowed to use. Swapping providers does not
/// change this — the same catalog renders whatever any provider generates.
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

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final SurfaceController _controller;
  late final GenUiAdapter _adapter;
  late final Conversation _conversation;
  StreamSubscription<ConversationEvent>? _events;

  final List<String> _surfaceIds = <String>[];
  final TextEditingController _input = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = SurfaceController(catalogs: [appCatalog]);

    // One line picks the provider. Swap to AnthropicGenUiAdapter,
    // OllamaGenUiAdapter, or OpenRouterGenUiAdapter without touching the rest.
    _adapter = OpenAiGenUiAdapter(
      apiKey: _openAiKey,
      model: 'gpt-5.4',
      systemPrompt: GenUiPrompt.fromCatalog(appCatalog),
    );

    _conversation = Conversation(
      controller: _controller,
      transport: _adapter.transport,
    );
    _events = _conversation.events.listen(_onEvent);
  }

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
      appBar: AppBar(title: const Text('flutter_open_genui · OpenAI')),
      body: Column(
        children: [
          if (_openAiKey.isEmpty) const _MissingKeyBanner(),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _surfaceIds.isEmpty
                ? const Center(child: Text('Ask for a UI to get started.'))
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
  const _MissingKeyBanner();

  @override
  Widget build(BuildContext context) => MaterialBanner(
    backgroundColor: Theme.of(context).colorScheme.errorContainer,
    content: const Text(
      'No OPENAI_API_KEY. Run with '
      '--dart-define=OPENAI_API_KEY=sk-...',
    ),
    actions: const [SizedBox.shrink()],
  );
}
