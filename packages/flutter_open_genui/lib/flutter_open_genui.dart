// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Bring your own LLM to Flutter GenUI.
///
/// This is the shared core: the [GenUiAdapter] base class that provider
/// packages extend, the resilient A2UI [A2uiJsonHealer] / [JsonRepair] layer,
/// and prompt/logging helpers. Install a provider package (e.g.
/// `flutter_open_genui_openai`) to get a concrete adapter.
library;

export 'src/gen_ui_adapter.dart';
export 'src/gen_ui_adapter_config.dart';
export 'src/gen_ui_request.dart';
export 'src/healing/a2ui_json_healer.dart';
export 'src/healing/json_repair.dart';
export 'src/logging.dart';
export 'src/prompt.dart';
