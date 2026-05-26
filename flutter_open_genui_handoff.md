# flutter_open_genui — Build Handoff Brief

> **For Claude Code.** This is a self-contained brief. Read it top to bottom, then start building.
> You should not need any other context to begin. External facts are dated; verify the alpha SDK's
> current API against pub.dev before coding, because it changes.

---

## 1. What we're building

`flutter_open_genui` is an open-source Flutter package that lets developers drive Google's
**Flutter GenUI SDK** with **any LLM provider** — OpenAI, Anthropic (Claude), local models via
Ollama, or anything reachable through OpenRouter — instead of being locked to Firebase/Gemini or a
self-hosted A2UI server.

**One-line pitch:** *Bring your own model to Flutter GenUI. `pub add flutter_open_genui`, write one
line, and drive A2UI surfaces with the model you already use — no Firebase, no server.*

### Why this exists (the gap)

Google's official `genui` package (alpha, on pub.dev) is an orchestration layer that turns an LLM
conversation into rendered Flutter UI. Today it ships connection paths for **Firebase AI Logic**
(Gemini, client-side) and **GenUI A2UI** (a server-side agent over WebSocket). For any other
provider the docs say "build your own adapter… expect more from us and the community soon."

That "build your own" step is the barrier. Most Flutter devs already hold an OpenAI or Anthropic
key, or run Ollama locally, and want to use *that*. This package fills the gap with ready-made,
plug-and-play adapters.

### Success criteria

- A dev can swap providers with a **one-line change**.
- Each adapter is an **optional dependency** (installing the OpenAI adapter must not pull in
  Anthropic's SDK).
- A clean base class lets the **community contribute new providers** via PR.
- Malformed/partial AI JSON is **handled gracefully** in the shared core, so every provider inherits
  resilient streaming.

---

## 2. How Flutter GenUI works (the integration seam)

The official SDK runs a streaming loop. The key named components (verify exact names/signatures on
pub.dev — this is alpha):

- **Catalog** — the set of `CatalogItem`s defining the *only* widgets the AI may use. Each item has a
  name, a JSON data schema (built with `json_schema_builder`), and a `widgetBuilder`. This is the
  security boundary: the agent references trusted widgets, it never ships executable code.
- **DataModel** — observable state store; widgets bind to paths (e.g. `/user/name`) and rebuild when
  bound data changes. User input writes back into it.
- **A2uiTransportAdapter** — **THIS IS OUR SEAM.** It parses a raw text/token stream from the LLM
  into structured `A2uiMessage` commands (`createSurface`, `surfaceUpdate`, `dataModelUpdate`,
  `deleteSurface`). It is constructed with an `onSend` callback and exposes a method to push stream
  chunks in (in the current alpha, `addChunk(String)`).
- **SurfaceController** — applies the parsed messages, owns the DataModel, tracks surfaces.
- **Surface** — the widget you drop in your tree to render a surface by ID.
- **Conversation** — high-level facade; manages history and wires transport → controller.

**What our adapter must do, per provider, is narrow:**

1. Take the user message + system prompt (the official `PromptBuilder` produces the A2UI system
   instructions; see the token-bloat note in §6).
2. Call the provider's **streaming** chat/completions API.
3. Pump the streamed text chunks into the `A2uiTransportAdapter` (via `addChunk` or current
   equivalent).
4. Translate the provider's function-calling / structured-output quirks so the model reliably emits
   the A2UI `createSurface`/`updateComponents` tool calls the SDK expects.

That's the whole job. We are **not** re-implementing the catalog, the DataModel, surfaces, or the
A2UI parser — we sit on top of the one well-defined transport seam. This is why the scope is small
and resilient to upstream churn.

### Target developer experience (the API we're designing toward)

```dart
import 'package:genui/genui.dart';
import 'package:flutter_open_genui/openai.dart';

final adapter = OpenAiGenUiAdapter(apiKey: myKey, model: 'gpt-4o');

final conversation = Conversation(
  controller: surfaceController, // dev's widget catalog
  transport: adapter.transport,  // the adapter owns/exposes the A2uiTransportAdapter
);

await conversation.sendRequest(ChatMessage.user(TextPart('Plan me a trip')));
```

Switching to Claude or Ollama is a one-line change:

```dart
final adapter = AnthropicGenUiAdapter(apiKey: myKey, model: 'claude-sonnet-4-6');
// or
final adapter = OllamaGenUiAdapter(model: 'llama3.1', baseUrl: 'http://localhost:11434');
```

---

## 3. Repository architecture

Monorepo of small, independently-publishable packages so each provider dependency stays optional.

```
flutter_open_genui/                      ← repo root
├─ packages/
│  ├─ flutter_open_genui/                ← core: GenUiAdapter base class, JSON healing, shared plumbing
│  │                                       (this is the published "core" package; re-exports nothing provider-specific)
│  ├─ flutter_open_genui_openai/         ← OpenAiGenUiAdapter
│  ├─ flutter_open_genui_anthropic/      ← AnthropicGenUiAdapter
│  ├─ flutter_open_genui_ollama/         ← OllamaGenUiAdapter (local, no API key)
│  └─ flutter_open_genui_openrouter/     ← OpenRouterGenUiAdapter (many models, one adapter)
├─ example/                              ← one app; switch providers from a dropdown
├─ melos.yaml                            ← monorepo tooling (or pubspec workspaces)
├─ README.md
├─ CONTRIBUTING.md                       ← "how to add a new provider" guide (the flywheel)
└─ LICENSE                               ← BSD-3-Clause or MIT (match Flutter ecosystem norms; confirm with maintainer)
```

> Naming note: the core package is `flutter_open_genui`; provider packages are
> `flutter_open_genui_<provider>`. Each provider package depends on the core package and on that
> provider's Dart SDK/HTTP client. Decide per-package whether to wrap an existing community Dart
> client or call the REST API directly with `package:http` / `package:dio` (prefer the latter to
> minimize transitive deps and keep control over streaming).

---

## 4. The `GenUiAdapter` core interface

Design the base class so a new provider is implemented by overriding **one or two methods**. Treat
the following as the intended shape; refine names as you implement against the real alpha API.

```dart
/// Base class every provider adapter extends.
abstract class GenUiAdapter {
  GenUiAdapter({required this.config});

  final GenUiAdapterConfig config;

  /// The transport the official genui SDK's Conversation consumes.
  /// The base class constructs and owns this, wiring its onSend callback
  /// to [streamCompletion] below.
  A2uiTransportAdapter get transport;

  /// Provider-specific: given the assembled request (system prompt + history +
  /// the new user turn + the A2UI tool definitions), call the provider's
  /// STREAMING API and yield text chunks as they arrive.
  ///
  /// The base class is responsible for feeding these chunks through the
  /// JSON-healing layer and into [transport].addChunk.
  Stream<String> streamCompletion(GenUiRequest request);

  /// Optional override: translate the A2UI tool/function-call schema into the
  /// provider's native tool-calling format. Default implementation targets the
  /// OpenAI-style "tools" schema (which OpenRouter and many others accept).
  ProviderToolSpec buildToolSpec(A2uiToolSchema schema) => /* default */;

  void dispose();
}
```

Supporting types:

- `GenUiAdapterConfig` — apiKey, model, baseUrl (for Ollama/self-host/OpenRouter), optional
  temperature/maxTokens, optional custom `http`/`dio` client for testing.
- `GenUiRequest` — system prompt, message history, current user turn, the A2UI tool schema the
  model must call.
- The **JSON-healing layer** lives in the base class so all providers inherit it (see §5).

**Contributor flywheel:** `CONTRIBUTING.md` should document that adding a provider = create a new
package, extend `GenUiAdapter`, implement `streamCompletion`, and (if the provider isn't
OpenAI-tool-compatible) override `buildToolSpec`. Target providers for community PRs: Mistral, Groq,
AWS Bedrock, Google Gemini-direct (non-Firebase), Cohere.

---

## 5. JSON healing (the built-in differentiator)

LLMs streaming structured A2UI output frequently emit partial, truncated, or slightly-malformed JSON
mid-stream. The official `A2uiTransportAdapter` expects parseable A2UI messages. Put a healing layer
in the **core base class** so every provider benefits:

- Buffer streamed chunks and detect complete JSON objects/lines (A2UI is JSONL-style — one compact
  JSON object per line).
- Tolerate and repair common breakage: trailing commas, unterminated strings at chunk boundaries,
  stray markdown code fences (```` ```json ````), leading prose before the first `{`.
- On an unrecoverable line, **skip and log** rather than crash the surface (graceful degradation).
- Expose a debug/log hook so devs can observe the raw vs. healed stream (mirror the official SDK's
  `configureGenUiLogging` pattern).

This is the "trust signal" that makes the package worth using over a hand-rolled adapter. Keep it
well-tested (see §7).

---

## 6. Provider-specific notes

**OpenAI** — Chat Completions (or Responses API) with streaming + `tools`/function-calling. The
reference shape for `buildToolSpec`. Ship first.

**OpenRouter** — OpenAI-compatible API. Largely reuses the OpenAI adapter's request/stream/tool
logic with a different `baseUrl` and auth header; one adapter exposes many models. Cheap to build
once OpenAI exists — do it right after.

**Anthropic (Claude)** — Messages API with streaming. Tool use is similar in spirit to OpenAI but
the request/response envelope differs (system prompt is a top-level field; tool calls arrive as
`tool_use` content blocks). Override `buildToolSpec` and the stream parsing accordingly.

**Ollama / local** — No API key; `baseUrl` defaults to `http://localhost:11434`. Streaming chat
endpoint. Two real constraints to handle:
- Tool-calling support varies by local model; provide a fallback path that instructs the model to
  emit raw A2UI JSON directly (relying harder on the JSON-healing layer).
- **System-prompt bloat:** the official `PromptBuilder.chat()` can generate **3,000–5,000+ tokens**,
  which can exceed small/on-device context windows. Document this prominently and consider a
  `compactSystemPrompt` helper or guidance to use `systemPromptFragments` with only the needed
  schema portions. This is a documented upstream pain point.

---

## 7. Testing strategy

- **JSON-healing unit tests** are the highest-value tests — feed deliberately broken/partial chunk
  sequences and assert correct healed A2UI messages or clean skips. This is where bugs will live.
- **Adapter contract tests** against a mocked HTTP client: assert each provider builds the correct
  request envelope and correctly parses its streaming format into text chunks.
- **No live-LLM dependency in CI.** Use recorded/canned streaming responses per provider as fixtures.
- **Example app** doubles as a manual integration test: a provider dropdown that swaps adapters at
  runtime against the same widget catalog.

---

## 8. Security caveat (must be prominent in README)

This package's default path is **client-side direct**: the adapter calls the provider API straight
from the Flutter app, so **API keys live on-device**. State plainly in the README that this is ideal
for prototypes, local models (Ollama needs no key), and key-managed/proxied setups, but that
production apps shipping a real key to clients should route through a thin backend proxy. Being
upfront builds credibility. (Design `GenUiAdapterConfig.baseUrl` so pointing an adapter at a proxy is
trivial — that's the upgrade path.)

---

## 9. Build sequence (≈ a few weeks)

**Phase 1 — core + first provider + example**
1. Scaffold monorepo (melos or pub workspaces), licenses, analysis_options, CI skeleton.
2. Add `genui` as a dependency in the core package; study the real `A2uiTransportAdapter`,
   `SurfaceController`, `Conversation`, `PromptBuilder` signatures on pub.dev and pin a version.
3. Implement `GenUiAdapter` base class + `GenUiAdapterConfig` + `GenUiRequest` + the JSON-healing
   layer, with thorough healing unit tests.
4. Implement `flutter_open_genui_openai` (`OpenAiGenUiAdapter`).
5. Build the `example/` app with a working OpenAI flow and a simple custom catalog (riddle card or
   travel-style widgets) to prove the end-to-end loop.

**Phase 2 — breadth**
6. `flutter_open_genui_openrouter` (reuse OpenAI logic, new baseUrl/auth).
7. `flutter_open_genui_anthropic` (override tool spec + stream parsing).
8. `flutter_open_genui_ollama` (no-key path + raw-JSON fallback + prompt-compaction guidance).
9. Add the provider dropdown to the example app.

**Phase 3 — ship**
10. README (pitch, install, one-line examples per provider, security caveat, supported models).
11. `CONTRIBUTING.md` "add a provider in 4 steps" guide.
12. Polish, finalize tests in CI, publish core + provider packages to pub.dev.

---

## 10. Things to verify before/while coding (don't trust this doc blindly)

- The `genui` package is **alpha and changing**. Confirm current names/signatures for
  `A2uiTransportAdapter` (esp. `onSend` and `addChunk`), `Conversation`, `SurfaceController`,
  `Surface`, and `PromptBuilder` on pub.dev / the `flutter/genui` repo before building against them.
- Confirm whether the official transport expects raw text chunks or already-structured messages in
  the current version — our healing layer sits just before whatever it expects.
- Check the official `examples/` (e.g. the travel app) in the `flutter/genui` repo for the current
  idiomatic wiring, and mirror it.
- Pick and pin a `genui` version constraint; document the tested version in the README.

---

## Appendix — reference links

- Flutter GenUI overview: https://docs.flutter.dev/ai/genui
- GenUI components & concepts: https://docs.flutter.dev/ai/genui/components
- GenUI get started (Firebase / A2UI / build-your-own paths): https://docs.flutter.dev/ai/genui/get-started
- `genui` package: https://pub.dev/packages/genui
- `flutter/genui` repo (examples incl. travel_app): https://github.com/flutter/genui
- A2UI protocol: https://a2ui.org/  ·  spec: https://github.com/google/A2UI
- A2UI v0.9 announcement (ecosystem context): https://developers.googleblog.com/a2ui-v0-9-generative-ui/
