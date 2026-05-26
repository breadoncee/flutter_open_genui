// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// OpenAI adapter for flutter_open_genui.
///
/// Exposes [OpenAiGenUiAdapter] and the reusable [OpenAiCompatibleAdapter] base
/// that OpenRouter and Ollama (`/v1`) build on.
library;

export 'src/openai_compatible_adapter.dart';
export 'src/openai_gen_ui_adapter.dart';
