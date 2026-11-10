# flutter_open_genui

**Bring your own LLM to [Flutter GenUI](https://docs.flutter.dev/ai/genui).**
`pub add` a provider, write one line, and drive A2UI surfaces with the model you
already use — OpenAI, Anthropic, a local model via Ollama, or anything behind
OpenRouter. No Firebase, no self-hosted A2UI server.

> Status: early alpha, built on the A2UI Dart SDKs (`a2ui_core` **0.6**,
> `a2ui_agent` **0.2**, rendered with `a2ui_flutter` **0.2**), which change
> often. Pin versions and expect churn.

## Why

The [A2UI protocol](https://a2ui.org) turns an LLM conversation into rendered
UI. Its Dart SDKs, which replace Google's
[`genui`](https://pub.dev/packages/genui) package, are **"Prompt-First"**:
[`a2ui_agent`](https://pub.dev/packages/a2ui_agent) writes a system prompt and
reads the A2UI JSON the model streams back, and
[`a2ui_flutter`](https://pub.dev/packages/a2ui_flutter) renders it. But the SDKs
ship **no** ready-made transport for OpenAI / Anthropic / Ollama / OpenRouter —
you have to build your own adapter.

`flutter_open_genui` is that adapter, done for you, plus a resilient
**JSON-healing** layer so malformed or truncated streamed JSON still renders
instead of silently falling back to chat text.

## Packages

| Package | Purpose |
| --- | --- |
| `flutter_open_genui` | Core: `GenUiAdapter` base class, JSON healing, prompt/logging helpers |
| `flutter_open_genui_openai` | `OpenAiGenUiAdapter` (+ reusable OpenAI-compatible base) |
| `flutter_open_genui_openrouter` | `OpenRouterGenUiAdapter` — many models, one Bearer key |
| `flutter_open_genui_anthropic` | `AnthropicGenUiAdapter` — Claude Messages API |
| `flutter_open_genui_ollama` | `OllamaGenUiAdapter` — local, no API key |

Each provider is an **optional** dependency — installing the OpenAI adapter does
not pull in any other provider's code.

## Install

```yaml
dependencies:
  a2ui_core: ^0.6.0
  a2ui_flutter: ^0.2.0
  flutter_open_genui_openai: ^0.0.1   # pulls in flutter_open_genui core
```

## Use

```dart
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/v0_9/basic_catalog.dart' as v0_9;
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';

// 1. Define the widget catalog the model may use.
final catalog = v0_9.basicCatalog();

// 2. Pick a provider — this is the one line you change to switch models.
final adapter = OpenAiGenUiAdapter(
  apiKey: myKey,
  model: 'gpt-5.4',
  catalog: catalog,
  systemPrompt: GenUiPrompt.fromCatalog(catalog),
);

// 3. Render the adapter's A2UI messages, and send actions back to the model.
final processor = MessageProcessor<ComponentImplementation>(
  catalogs: [catalog],
  validationConfig: ValidationConfig.relaxed,
  reportErrorsOnly: true,
);
adapter.incomingMessages.listen(
  (message) =>
      processor.processMessages(AgentToRendererMessagePayload.of(message)),
);
processor.model.onAction.subscribe(
  (action) =>
      adapter.sendInteraction(ActionMessage(version: 'v0.9', action: action)),
);

// 4. Render surfaces (A2uiSurface for each surface of
//    processor.model.onSurfaceCreated) and send a turn.
await adapter.sendRequest(ChatMessage.user('Plan me a trip'));
```

Switching providers is a one-line change:

```dart
final adapter = AnthropicGenUiAdapter(apiKey: key, model: 'claude-sonnet-4-6', catalog: catalog, systemPrompt: prompt);
// or via OpenRouter (any of dozens of models):
final adapter = OpenRouterGenUiAdapter(apiKey: key, model: 'anthropic/claude-sonnet-4-6', catalog: catalog, systemPrompt: prompt);
// or no API key — local:
final adapter = OllamaGenUiAdapter(model: 'llama3.1', catalog: catalog, systemPrompt: prompt);
```

See [`example/`](example/) for a complete app. Run it with:

```bash
fvm flutter run --dart-define=OPENAI_API_KEY=sk-...
```

## ⚠️ Security: keys live on-device by default

The default path calls the provider API **directly from the Flutter app**, so a
real API key shipped in a build is exposed. That's fine for prototypes, local
models (Ollama needs no key), and key-managed setups. **Production apps should
route through a thin backend proxy** — point any adapter at it in one line:

```dart
OpenAiGenUiAdapter(apiKey: '', baseUrl: 'https://your-proxy.example.com/v1', ...);
```

## JSON healing

LLMs streaming structured output often emit trailing commas, single quotes,
comments, or get cut off mid-object by a token limit. `a2ui_agent`'s parser
reads past trailing commas but rejects the other broken blocks. The core
`JsonRepair` / `A2uiJsonHealer` repair each `<a2ui-json>` block before it
reaches the parser, so surfaces still render. Observe what it does:

```dart
configureFlutterOpenGenUiLogging((m, {error, stackTrace}) => debugPrint(m));
```

## Toolchain

This repo uses [FVM](https://fvm.app) (Flutter version pinned in `.fvmrc`) and
[melos](https://melos.invertase.dev) for the monorepo. `fvm exec` puts the
pinned SDK on `PATH` so melos uses it:

```bash
fvm use                                   # set up the pinned Flutter SDK
fvm dart pub global activate melos        # once
fvm exec melos bootstrap                  # resolve all packages
fvm exec melos run analyze --no-select    # analyze every package
fvm exec melos run test --no-select       # run all tests (no network / no live LLM)
```

## Contributing

New providers are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the
"add a provider in 4 steps" guide.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
