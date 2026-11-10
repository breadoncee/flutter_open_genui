## Unreleased

- **Breaking:** move from `genui` to the A2UI Dart SDKs, since `genui` will
  be deprecated. The package depends on `a2ui_core`, `a2ui_agent` and
  `genai_primitives` instead of `genui`, and still speaks A2UI v0.9.
  - `GenUiAdapter` no longer has a `transport` for genui's `Conversation`.
    `sendRequest(ChatMessage)` sends a turn, `incomingText` streams the
    model's text, and `incomingMessages` streams its A2UI messages as
    `a2ui_core` `AgentToRendererMessage`s for a renderer such as
    `a2ui_core`'s `MessageProcessor`. A block the model wrote that is
    rejected arrives on `incomingMessages` as an error.
  - The new `GenUiAdapter.sendInteraction` sends a renderer action or error
    to the model, as genui's `Conversation` did for its `SurfaceController`.
  - `GenUiAdapterConfig` takes a required `catalog`, an `a2ui_core`
    `CatalogApi` that replies are read and checked against.
  - `GenUiPrompt.fromCatalog` takes a `CatalogApi` and builds the prompt with
    `a2ui_agent`, which asks for a JSON array of A2UI messages in
    `<a2ui-json>` tags instead of markdown-fenced JSON. genui's basic catalog
    rules are no longer part of it.
  - `A2uiJsonHealer` repairs `<a2ui-json>` blocks instead of fenced or bare
    JSON objects, and holds each block back until it closes.
  - `ChatMessage` and `ChatMessageRole` come from `genai_primitives`, and this
    package re-exports them.

## 0.0.1

- Initial release. `GenUiAdapter` base class, `GenUiAdapterConfig`,
  `GenUiRequest`, prompt/logging helpers, and the `JsonRepair` /
  `A2uiJsonHealer` resilient streaming layer. Built against `genui` 0.9.0.
