# flutter_open_genui_openai

OpenAI adapter for
[flutter_open_genui](https://github.com/breadoncee/flutter_open_genui) — drive
[Flutter GenUI](https://docs.flutter.dev/ai/genui) A2UI surfaces with the OpenAI
Chat Completions API.

```dart
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/v0_9/basic_catalog.dart' as v0_9;
import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_open_genui_openai/flutter_open_genui_openai.dart';

final catalog = v0_9.basicCatalog();

final adapter = OpenAiGenUiAdapter(
  apiKey: myKey,
  model: 'gpt-5.4',
  catalog: catalog,
  systemPrompt: GenUiPrompt.fromCatalog(catalog),
);

final processor = MessageProcessor<ComponentImplementation>(
  catalogs: [catalog],
  validationConfig: ValidationConfig.relaxed,
  reportErrorsOnly: true,
);
adapter.incomingMessages.listen(
  (message) =>
      processor.processMessages(AgentToRendererMessagePayload.of(message)),
);
await adapter.sendRequest(ChatMessage.user('Plan me a trip'));
```

`OpenAiCompatibleAdapter` (also exported) is the reusable base for any
OpenAI-compatible endpoint — set `baseUrl` for OpenRouter, Ollama's `/v1`, or a
backend proxy.

> Security: the default path calls OpenAI directly from the app, so the key lives
> on-device. For production, route through a proxy via `baseUrl`. See the
> [repo README](https://github.com/breadoncee/flutter_open_genui).

Built against `a2ui_core` 0.6.0 and `a2ui_agent` 0.2.0. BSD-3-Clause.
