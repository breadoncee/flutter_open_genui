# Contributing to flutter_open_genui

Thanks for helping! The highest-value contributions are **new provider
adapters** and **JSON-healing edge cases**.

## Setup

This repo uses [FVM](https://fvm.app) + [melos](https://melos.invertase.dev).

```bash
dart pub global activate fvm           # if you don't have it
fvm use                                # installs the Flutter version in .fvmrc
fvm dart pub global activate melos
fvm exec melos bootstrap               # resolve all workspace packages
fvm exec melos run analyze --no-select # must be clean
fvm exec melos run test --no-select    # must pass (no network access needed)
```

`fvm exec` runs the command with the pinned Flutter/Dart on `PATH`. Melos
config lives in the root `pubspec.yaml` under `melos:` (pub workspaces).

All tests run against recorded fixtures / mocked HTTP — **never** a live LLM, so
CI stays deterministic and free.

## Add a provider in 4 steps

The base class does the hard parts (transport wiring, history, JSON healing). A
new provider usually only implements `streamCompletion`.

1. **Create a package** `packages/flutter_open_genui_<provider>/` and add it to
   the `workspace:` list in the root `pubspec.yaml`. Depend on
   `flutter_open_genui`, `genui`, and `dio`.

2. **Extend `GenUiAdapter`** (or `OpenAiCompatibleAdapter` from the OpenAI
   package if the provider speaks the OpenAI wire format — OpenRouter and
   Ollama's `/v1` do, so they reuse it with just a different `baseUrl`/headers).

3. **Implement `streamCompletion`** — call the provider's streaming endpoint
   with `dio` and `yield` the raw text deltas. Do **not** parse A2UI; the base
   class heals and forwards. Most of v0.9 is prompt-first, so a plain text
   stream is all that's needed. Override `buildToolSpec` only if you add a
   native tool-calling path later.

4. **Add contract tests** with a fake `HttpClientAdapter` (see
   `flutter_open_genui_openai/test/openai_adapter_test.dart`): assert the request
   envelope (URL, headers, body) and that the streaming format parses into text
   chunks.

Built-in: OpenAI, OpenRouter, Anthropic, Ollama.
Wanted next: Mistral, Groq, AWS Bedrock, Gemini-direct (non-Firebase), Cohere,
Together, DeepSeek, Cerebras.

## Style

- `dart format .` (enforced by `melos run format`).
- Lints in `analysis_options.yaml` are fatal in CI — keep `melos run analyze`
  clean.
- Prefer raw `dio` over wrapping a community LLM SDK, to keep each adapter's
  transitive dependencies minimal and optional.

## Pull requests

Keep PRs focused (one provider or one fix). Include tests. Note the `genui`
version you built against — it is alpha and the API moves.
