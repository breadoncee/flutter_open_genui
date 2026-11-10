# flutter_open_genui

Core of [flutter_open_genui](https://github.com/breadoncee/flutter_open_genui) —
**bring your own LLM to [Flutter GenUI](https://docs.flutter.dev/ai/genui)**.

This package provides the shared pieces every provider adapter builds on:

- `GenUiAdapter` — base class that runs the streaming loop and reads the
  model's replies with `a2ui_agent` into A2UI messages for a renderer. A
  provider only implements `streamCompletion`.
- `JsonRepair` / `A2uiJsonHealer` — repair malformed or truncated streamed JSON
  (trailing commas, single quotes, comments, `maxTokens` cutoffs) so surfaces
  render instead of being rejected.
- `GenUiPrompt` — builds the system prompt for a catalog with `a2ui_agent`.
- `configureFlutterOpenGenUiLogging` — observe the raw vs. healed stream.

Install a provider package (e.g.
[`flutter_open_genui_openai`](https://pub.dev/packages/flutter_open_genui_openai))
to get a concrete adapter. See the
[repo README](https://github.com/breadoncee/flutter_open_genui) for full usage.

Built against `a2ui_core` 0.6.0 and `a2ui_agent` 0.2.0. BSD-3-Clause.
