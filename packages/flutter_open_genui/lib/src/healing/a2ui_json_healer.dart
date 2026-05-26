// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import '../logging.dart';
import 'json_repair.dart';

/// A [StreamTransformer] that sits between a provider's raw token stream and the
/// official `A2uiTransportAdapter.addChunk`, repairing malformed JSON blocks so
/// the downstream parser can render them instead of dropping them to chat text.
///
/// It detects complete blocks incrementally (Markdown ```` ```json ```` fences
/// and balanced top-level `{...}` objects), so the happy path streams with no
/// added latency. A block that already parses is forwarded unchanged; a broken
/// block is run through [JsonRepair]; an unrecoverable block is forwarded as-is
/// and logged (graceful degradation — never crash the surface). A truncated
/// trailing block (e.g. a `maxTokens` cutoff) is repaired on stream close.
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

  static final RegExp _fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');

  void onData(String chunk) {
    _buffer += chunk;
    _process(done: false);
  }

  void onDone() => _process(done: true);

  void _process({required bool done}) {
    while (_buffer.isNotEmpty) {
      final fence = _fence.firstMatch(_buffer);
      if (fence != null) {
        _emitProse(_buffer.substring(0, fence.start));
        _emitBlock(fence.group(1) ?? '', fence.group(0) ?? '');
        _buffer = _buffer.substring(fence.end);
        continue;
      }

      if (_buffer.startsWith('{')) {
        final end = JsonRepair.balancedEnd(_buffer);
        if (end != -1) {
          final block = _buffer.substring(0, end);
          _emitBlock(block, block);
          _buffer = _buffer.substring(end);
          continue;
        }
      }

      // No complete block at the head of the buffer.
      final fenceStart = _buffer.indexOf('```');
      final braceStart = _buffer.indexOf('{');
      final firstStart = _firstPositive(fenceStart, braceStart);

      if (firstStart == -1) {
        // Pure prose; nothing JSON-like ahead.
        _emitProse(_buffer);
        _buffer = '';
        break;
      }

      if (firstStart > 0) {
        _emitProse(_buffer.substring(0, firstStart));
        _buffer = _buffer.substring(firstStart);
      }

      // The buffer now starts with an incomplete block.
      if (done) {
        final repaired = JsonRepair.tryRepair(_buffer);
        if (repaired != null) {
          _emitJson(repaired);
          _report(_buffer, repaired);
        } else {
          _out.add(_buffer);
          _drop(_buffer);
        }
        _buffer = '';
      }
      break; // Wait for more data, or we are done.
    }
  }

  void _emitBlock(String inner, String original) {
    final strict = JsonRepair.strict(inner);
    if (strict != null) {
      _emitJson(strict);
      return;
    }
    final repaired = JsonRepair.tryRepair(original);
    if (repaired != null) {
      _emitJson(repaired);
      _report(original, repaired);
    } else {
      _out.add(original);
      _drop(original);
    }
  }

  void _emitJson(String json) {
    _out
      ..add(json)
      // A trailing newline acts as a JSONL separator for the downstream parser.
      ..add('\n');
  }

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

  static int _firstPositive(int a, int b) {
    if (a == -1) return b;
    if (b == -1) return a;
    return a < b ? a : b;
  }
}
