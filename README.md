# flutter_open_genui

**Bring your own LLM to [Flutter GenUI](https://docs.flutter.dev/ai/genui).**
`pub add` a provider, write one line, and drive A2UI surfaces with the model you
already use — OpenAI, Anthropic, a local model via Ollama, or anything behind
OpenRouter. No Firebase, no self-hosted A2UI server.

> Status: early alpha, tracking the official `genui` **0.9.0** alpha (which
> changes often). Pin versions and expect churn until `genui` hits 1.0.

## Why

Google's official [`genui`](https://pub.dev/packages/genui) package turns an LLM
conversation into rendered Flutter UI over the [A2UI protocol](https://a2ui.org).
As of 0.9.0 it is **"Prompt-First"**: you feed the model a system prompt, it
emits A2UI JSON, and you push that text into one seam
(`A2uiTransportAdapter.onSend` + `addChunk`). But the SDK ships **no** ready-made
transport for OpenAI / Anthropic / Ollama / OpenRouter — the docs say "build your
own adapter."

`flutter_open_genui` is that adapter, done for you, plus a resilient
**JSON-healing** layer so malformed or truncated streamed JSON still renders
instead of silently falling back to chat text.

## Packages

| Package | Purpose |
| --- | --- |
| `flutter_open_genui` | Core: `GenUiAdapter` base class, JSON healing, prompt/logging helpers |
| `flutter_open_genui_openai` | `OpenAiGenUiAdapter` (+ reusable OpenAI-compatible base) |
| `flutter_open_genui_openrouter` | _planned_ — reuses the OpenAI path |
| `flutter_open_genui_anthropic` | _planned_ — Claude Messages API |
| `flutter_open_genui_ollama` | _planned_ — local, no API key |

Each provider is an **optional** dependency — installing the OpenAI adapter does
not pull in any other provider's code.

## Install

```yaml
dependencies:
  genui: ^0.9.0
  flutter_open_genui_openai: ^0.0.1   # pulls in flutter_open_genui core
```

## Use

```dart
import 'package:genui/genui.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';

// 1. Define the widget catalog the model may use.
final catalog = BasicCatalogItems.asCatalog();

// 2. Pick a provider — this is the one line you change to switch models.
final adapter = OpenAiGenUiAdapter(
  apiKey: myKey,
  model: 'gpt-5.4',
  systemPrompt: GenUiPrompt.fromCatalog(catalog),
);

// 3. Wire the official Conversation to the adapter's transport.
final controller = SurfaceController(catalogs: [catalog]);
final conversation = Conversation(
  controller: controller,
  transport: adapter.transport,
);

// 4. Render surfaces (controller.contextFor(id)) and send a turn.
await conversation.sendRequest(ChatMessage.user('Plan me a trip'));
```

Switching providers is a one-line change (planned adapters):

```dart
final adapter = AnthropicGenUiAdapter(apiKey: key, model: 'claude-sonnet-4-6', systemPrompt: prompt);
// or, no API key needed:
final adapter = OllamaGenUiAdapter(model: 'llama3.1', systemPrompt: prompt);
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
comments, or get cut off mid-object by a token limit. `genui`'s parser drops
those blocks to chat text. The core `JsonRepair` / `A2uiJsonHealer` repair them
before they reach the transport, so surfaces still render. Observe what it does:

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
