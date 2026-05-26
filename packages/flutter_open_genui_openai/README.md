# flutter_open_genui_openai

OpenAI adapter for
[flutter_open_genui](https://github.com/devid/flutter_open_genui) — drive
[Flutter GenUI](https://docs.flutter.dev/ai/genui) A2UI surfaces with the OpenAI
Chat Completions API.

```dart
import 'package:genui/genui.dart';
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';

final catalog = BasicCatalogItems.asCatalog();

final adapter = OpenAiGenUiAdapter(
  apiKey: myKey,
  model: 'gpt-5.4',
  systemPrompt: GenUiPrompt.fromCatalog(catalog),
);

final conversation = Conversation(
  controller: SurfaceController(catalogs: [catalog]),
  transport: adapter.transport,
);
await conversation.sendRequest(ChatMessage.user('Plan me a trip'));
```

`OpenAiCompatibleAdapter` (also exported) is the reusable base for any
OpenAI-compatible endpoint — set `baseUrl` for OpenRouter, Ollama's `/v1`, or a
backend proxy.

> Security: the default path calls OpenAI directly from the app, so the key lives
> on-device. For production, route through a proxy via `baseUrl`. See the
> [repo README](https://github.com/devid/flutter_open_genui).

Built against `genui` 0.9.0. BSD-3-Clause.
