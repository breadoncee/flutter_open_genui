// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import '../logging.dart';
import 'json_repair.dart';

/// A [StreamTransformer] that sits between a provider's raw token stream and
/// the `a2ui_agent` response stream, repairing malformed A2UI blocks so the
/// downstream parser can render them instead of rejecting them.
///
/// It detects complete `<a2ui-json>` … `</a2ui-json>` blocks incrementally,
/// the format `GenUiPrompt.fromCatalog` asks for. Text outside blocks streams
/// through with no added latency. A block whose JSON already parses is
/// forwarded unchanged; a broken block is run through [JsonRepair]; an
/// unrecoverable block is forwarded as-is and logged (graceful degradation —
/// never crash the surface). A truncated trailing block (e.g. a `maxTokens`
/// cutoff) is repaired and closed on stream close.
class A2uiJsonHealer extends StreamTransformerBase<String, String> {
  /// Creates a healer.
  ///
  /// [onRepair] is called with the original and repaired text whenever a block
  /// is fixed; [onDrop] is called with text that could not be repaired. Both
  /// default to emitting diagnostics via [genUiLog].
  const A2uiJsonHealer({this.onRepair, this.onDrop});

  /// Called when a malformed block is successfully repaired.
  final void Function(String original, String repaired)? onRepair;

  /// Called when a malformed block could not be repaired and is passed through.
  final void Function(String original)? onDrop;

  @override
  Stream<String> bind(Stream<String> stream) {
    final controller = StreamController<String>();
    final state = _HealerState(controller, onRepair, onDrop);
    controller.onListen = () {
      final subscription = stream.listen(
        state.onData,
        onError: controller.addError,
        onDone: () {
          state.onDone();
          controller.close();
        },
        cancelOnError: false,
      );
      controller
        ..onPause = subscription.pause
        ..onResume = subscription.resume
        ..onCancel = subscription.cancel;
    };
    return controller.stream;
  }
}

class _HealerState {
  _HealerState(this._out, this._onRepair, this._onDrop);

  final StreamController<String> _out;
  final void Function(String original, String repaired)? _onRepair;
  final void Function(String original)? _onDrop;
  String _buffer = '';

  static const String _openTagText = '<a2ui-json>';
  static const String _closeTagText = '</a2ui-json>';
  static final RegExp _openTag = RegExp(_openTagText, caseSensitive: false);
  static final RegExp _closeTag = RegExp(
    r'</a2ui-json\s*>',
    caseSensitive: false,
  );

  void onData(String chunk) {
    _buffer += chunk;
    _process(done: false);
  }

  void onDone() => _process(done: true);

  void _process({required bool done}) {
    while (_buffer.isNotEmpty) {
      final open = _openTag.firstMatch(_buffer);
      if (open == null) {
        // Prose. Hold back an open tag that has only partly arrived.
        final held = done ? 0 : _partialOpenTagLength(_buffer);
        _emitProse(_buffer.substring(0, _buffer.length - held));
        _buffer = _buffer.substring(_buffer.length - held);
        break;
      }

      _emitProse(_buffer.substring(0, open.start));
      _buffer = _buffer.substring(open.start);
      final bodyStart = open.end - open.start;
      final close = _findCloseTag(_buffer, bodyStart);
      if (close != null) {
        _emitBlock(
          _buffer.substring(bodyStart, close.start),
          _buffer.substring(0, close.end),
        );
        _buffer = _buffer.substring(close.end);
        continue;
      }

      // The buffer now starts with an open block.
      if (done) {
        final original = _buffer;
        final repaired = JsonRepair.tryRepair(original.substring(bodyStart));
        if (repaired != null) {
          _emitJson(repaired);
          _report(original, repaired);
        } else {
          _out.add(original);
          _drop(original);
        }
        _buffer = '';
      }
      break; // Wait for more data, or we are done.
    }
  }

  void _emitBlock(String body, String original) {
    if (JsonRepair.strict(body) != null) {
      _out.add(original);
      return;
    }
    final repaired = JsonRepair.tryRepair(body);
    if (repaired != null) {
      _emitJson(repaired);
      _report(original, repaired);
    } else {
      _out.add(original);
      _drop(original);
    }
  }

  void _emitJson(String json) =>
      _out.add('$_openTagText\n$json\n$_closeTagText');

  void _emitProse(String text) {
    if (text.isNotEmpty) _out.add(text);
  }

  void _report(String original, String repaired) {
    genUiLog('Healed malformed A2UI JSON block.');
    _onRepair?.call(original, repaired);
  }

  void _drop(String original) {
    genUiLog('Could not repair A2UI JSON block; forwarding as text.');
    _onDrop?.call(original);
  }

  /// The length of the end of [s] that could still grow into an open tag.
  static int _partialOpenTagLength(String s) {
    final start = s.lastIndexOf('<');
    if (start == -1) return 0;
    final tail = s.substring(start).toLowerCase();
    return _openTagText.startsWith(tail) ? tail.length : 0;
  }

  /// The first close tag in [s] from [start] that is not inside a JSON
  /// string, or null.
  static Match? _findCloseTag(String s, int start) {
    var inString = false;
    var escaped = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
      } else if (c == '"') {
        inString = true;
      } else if (c == '<') {
        final match = _closeTag.matchAsPrefix(s, i);
        if (match != null) return match;
      }
    }
    return null;
  }
}
