// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Signature for a function that receives diagnostic messages from
/// flutter_open_genui.
typedef GenUiLogHandler =
    void Function(String message, {Object? error, StackTrace? stackTrace});

GenUiLogHandler? _handler;

/// Installs a [handler] to observe diagnostics such as healed or dropped JSON
/// blocks. Pass `null` to silence logging again.
///
/// Mirrors the official SDK's `configureGenUiLogging` pattern so developers can
/// watch the raw vs. healed stream while debugging.
void configureFlutterOpenGenUiLogging(GenUiLogHandler? handler) {
  _handler = handler;
}

/// Emits a diagnostic message to the installed [GenUiLogHandler], if any.
void genUiLog(String message, {Object? error, StackTrace? stackTrace}) {
  _handler?.call(message, error: error, stackTrace: stackTrace);
}
