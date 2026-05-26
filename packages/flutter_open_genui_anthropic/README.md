# flutter_open_genui_anthropic

Anthropic (Claude) adapter for
[flutter_open_genui](https://github.com/devid/flutter_open_genui).

Talks to the
[Messages API](https://docs.anthropic.com/en/api/messages) directly over `dio`
— no third-party SDK in the dependency graph. Sends the A2UI system prompt as
the top-level `system` field (the Messages API does not accept `system`
messages) and streams `content_block_delta` / `text_delta` events.

```dart
final adapter = AnthropicGenUiAdapter(
  apiKey: myKey,
  model: 'claude-sonnet-4-6',
  systemPrompt: GenUiPrompt.fromCatalog(catalog),
);
```

`max_tokens` defaults to 4096 (the Messages API requires it). Override via the
named constructor argument.

See the [repo README](https://github.com/devid/flutter_open_genui) for the full
setup. Built against `genui` 0.9.0. BSD-3-Clause.
