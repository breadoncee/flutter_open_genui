// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/v0_9/basic_catalog.dart' as v0_9;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_anthropic/flutter_open_genui_anthropic.dart';
import 'package:flutter_open_genui_ollama/flutter_open_genui_ollama.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';
import 'package:flutter_open_genui_openrouter/flutter_open_genui_openrouter.dart';
import 'package:url_launcher/url_launcher.dart';

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
final CatalogImplementation appCatalog = v0_9.basicCatalog(openUrl: launchUrl);

/// The A2UI protocol version the catalog and the model speak.
final String _version = A2uiProtocolVersion.v0_9.jsonValue;

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
  late final MessageProcessor<ComponentImplementation> _processor;
  late final List<Subscription> _processorSubscriptions;
  late GenUiAdapter _adapter;
  final List<StreamSubscription<Object?>> _adapterSubscriptions = [];

  Provider _provider = Provider.openai;
  final List<SurfaceModel<ComponentImplementation>> _surfaces = [];
  final TextEditingController _input = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _processor = MessageProcessor<ComponentImplementation>(
      catalogs: [appCatalog],
      // A surface streams in over several messages, which the strict checks
      // would reject.
      validationConfig: ValidationConfig.relaxed,
      reportErrorsOnly: true,
    );
    _processorSubscriptions = [
      _processor.model.onSurfaceCreated.subscribe(
        (surface) => setState(() => _surfaces.add(surface)),
      ),
      _processor.model.onSurfaceDeleted.subscribe(
        (surfaceId) =>
            setState(() => _surfaces.removeWhere((s) => s.id == surfaceId)),
      ),
      // Actions and errors go back to the model as the next turn, as genui's
      // Conversation sent them.
      _processor.model.onAction.subscribe(
        (action) => _sendTurn(
          () => _adapter.sendInteraction(
            ActionMessage(version: _version, action: action),
          ),
        ),
      ),
      _processor.model.onError.subscribe(
        (error) => _sendTurn(
          () => _adapter.sendInteraction(
            ErrorMessage(version: _version, error: error),
          ),
        ),
      ),
    ];
    _wireProvider(_provider);
  }

  /// (Re)builds the adapter for the chosen [provider], reusing the same
  /// [_processor] so existing surfaces keep rendering.
  void _wireProvider(Provider provider) {
    for (final subscription in _adapterSubscriptions) {
      unawaited(subscription.cancel());
    }
    _adapterSubscriptions.clear();
    if (_provider != provider) _adapter.dispose();
    _provider = provider;

    final systemPrompt = GenUiPrompt.fromCatalog(appCatalog);
    _adapter = switch (provider) {
      Provider.openai => OpenAiGenUiAdapter(
        apiKey: _openAiKey,
        model: provider.defaultModel,
        catalog: appCatalog,
        systemPrompt: systemPrompt,
      ),
      Provider.openrouter => OpenRouterGenUiAdapter(
        apiKey: _openRouterKey,
        model: provider.defaultModel,
        catalog: appCatalog,
        systemPrompt: systemPrompt,
        referer: 'https://github.com/breadoncee/flutter_open_genui',
        title: 'flutter_open_genui example',
      ),
      Provider.anthropic => AnthropicGenUiAdapter(
        apiKey: _anthropicKey,
        model: provider.defaultModel,
        catalog: appCatalog,
        systemPrompt: systemPrompt,
      ),
      Provider.ollama => OllamaGenUiAdapter(
        model: provider.defaultModel,
        catalog: appCatalog,
        systemPrompt: systemPrompt,
      ),
    };
    _adapterSubscriptions.addAll([
      _adapter.incomingText.listen((_) => _onContent()),
      _adapter.incomingMessages.listen(
        (message) {
          _onContent();
          _processor.processMessages(AgentToRendererMessagePayload.of(message));
        },
        // A block the adapter rejected goes back to the model too, as genui's
        // SurfaceController reported messages that failed validation.
        onError: (Object error) {
          _onContent();
          if (error is A2uiError) {
            _sendTurn(
              () => _adapter.sendInteraction(MessageErrorMapper.map(error)),
            );
          } else {
            _showError('$error');
          }
        },
      ),
    ]);
  }

  bool get _hasKeyForProvider => switch (_provider) {
    Provider.openai => _openAiKey.isNotEmpty,
    Provider.openrouter => _openRouterKey.isNotEmpty,
    Provider.anthropic => _anthropicKey.isNotEmpty,
    Provider.ollama => true, // no key needed
  };

  /// Hides the progress bar once the model's reply starts to arrive.
  void _onContent() {
    if (_busy) setState(() => _busy = false);
  }

  /// Shows the progress bar and runs [send], showing any error it throws.
  Future<void> _sendTurn(Future<void> Function() send) async {
    setState(() => _busy = true);
    try {
      await send();
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      _showError('$error');
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await _sendTurn(() => _adapter.sendRequest(ChatMessage.user(text)));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    for (final subscription in _adapterSubscriptions) {
      unawaited(subscription.cancel());
    }
    _adapter.dispose();
    for (final subscription in _processorSubscriptions) {
      subscription.unsubscribe();
    }
    _processor.dispose();
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
            child: _surfaces.isEmpty
                ? Center(
                    child: Text(
                      'Ask for a UI to get started '
                      '— provider: ${_provider.label}',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final surface in _surfaces)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            // Text components render Markdown, as genui's did.
                            child: v0_9.A2uiMarkdown(
                              builder: _buildMarkdown,
                              child: A2uiSurface(
                                key: ObjectKey(surface),
                                surface: surface,
                              ),
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

Widget _buildMarkdown(BuildContext context, String markdown, TextStyle style) =>
    MarkdownBody(
      data: markdown,
      styleSheet: MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).copyWith(p: style),
    );

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
