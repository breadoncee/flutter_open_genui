# flutter_open_genui_ollama

Local-LLM adapter for
[flutter_open_genui](https://github.com/breadoncee/flutter_open_genui).

Talks to a local [Ollama](https://ollama.com) server via its OpenAI-compatible
`/v1` endpoint. No API key required — perfect for offline development and
keeping data on-device.

```dart
final adapter = OllamaGenUiAdapter(
  model: 'llama3.1',
  systemPrompt: GenUiPrompt.fromCatalog(catalog),
  // baseUrl: 'http://ollama.local:11434/v1', // optional override
);
```

## Local-model caveats

- **Prompt size:** the A2UI system prompt is large (commonly 3,000–5,000+
  tokens). Small/quantized models with tight context windows may truncate.
  Use a model with a generous context, or trim the catalog and
  `systemPromptFragments` when calling `PromptBuilder.chat`.
- **Tool calling:** support varies wildly by model. This adapter sticks to
  the *prompt-first* path (model emits A2UI JSON in fenced blocks), which the
  shared healer in `flutter_open_genui` repairs and forwards.

See the [repo README](https://github.com/breadoncee/flutter_open_genui) for the
full setup. Built against `genui` 0.9.0. BSD-3-Clause.
