# flutter_open_genui_openrouter

OpenRouter adapter for
[flutter_open_genui](https://github.com/devid/flutter_open_genui).

[OpenRouter](https://openrouter.ai) exposes dozens of models behind one
OpenAI-compatible API; this adapter is a thin wrapper over the reusable
`OpenAiCompatibleAdapter` from
[`flutter_open_genui_openai`](https://pub.dev/packages/flutter_open_genui_openai),
adding the OpenRouter endpoint and the optional `HTTP-Referer` / `X-Title`
attribution headers.

```dart
final adapter = OpenRouterGenUiAdapter(
  apiKey: myKey,
  model: 'anthropic/claude-sonnet-4-6', // any OpenRouter model id
  systemPrompt: GenUiPrompt.fromCatalog(catalog),
  referer: 'https://myapp.example.com', // optional
  title: 'MyApp',                       // optional
);
```

See the [repo README](https://github.com/devid/flutter_open_genui) for the
full setup. Built against `genui` 0.9.0. BSD-3-Clause.
