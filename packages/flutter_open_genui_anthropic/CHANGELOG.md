## Unreleased

- **Breaking:** `AnthropicGenUiAdapter` takes a required `catalog`, the
  `a2ui_core` `CatalogApi` the system prompt was built from, and the package
  depends on `a2ui_core` instead of `genui`. See the `flutter_open_genui`
  changelog for the rest of the move to the A2UI Dart SDKs.

## 0.0.1

- Initial release. `AnthropicGenUiAdapter` over raw `dio`, parsing the
  Messages API SSE stream (`content_block_delta` / `text_delta`). Built
  against `genui` 0.9.0.
