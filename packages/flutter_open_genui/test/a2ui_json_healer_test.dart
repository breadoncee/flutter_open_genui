// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [chunks] through the healer and returns the concatenated output.
Future<String> heal(
  List<String> chunks, {
  A2uiJsonHealer healer = const A2uiJsonHealer(),
}) async {
  final out = await healer.bind(Stream.fromIterable(chunks)).toList();
  return out.join();
}

/// Extracts the JSON objects the downstream parser would see from healed text.
List<Object?> jsonBlocksIn(String text) {
  final blocks = <Object?>[];
  var rest = text;
  while (true) {
    final start = rest.indexOf('{');
    if (start == -1) break;
    rest = rest.substring(start);
    final end = JsonRepair.balancedEnd(rest);
    if (end == -1) break;
    blocks.add(jsonDecode(rest.substring(0, end)));
    rest = rest.substring(end);
  }
  return blocks;
}

void main() {
  group('A2uiJsonHealer', () {
    test('forwards a valid block split across chunk boundaries', () async {
      final result = await heal(['{"ver', 'sion": "v0', '.9"}']);
      expect(jsonBlocksIn(result), [
        {'version': 'v0.9'},
      ]);
    });

    test('repairs a trailing comma in a streamed block', () async {
      final result = await heal(['{"a": 1, "b": 2,}']);
      expect(jsonBlocksIn(result), [
        {'a': 1, 'b': 2},
      ]);
    });

    test('repairs a block inside a Markdown fence', () async {
      final result = await heal(['```json\n', '{"a": 1,}\n', '```']);
      expect(jsonBlocksIn(result), [
        {'a': 1},
      ]);
    });

    test('passes prose through untouched', () async {
      final result = await heal(['Thinking about it... ']);
      expect(result, 'Thinking about it... ');
    });

    test('handles prose followed by a JSON block', () async {
      final result = await heal(['Here: ', '{"a": 1}']);
      expect(result, contains('Here: '));
      expect(jsonBlocksIn(result), [
        {'a': 1},
      ]);
    });

    test('repairs a truncated final block on stream close', () async {
      final result = await heal(['{"a": 1, "b": "tex']);
      expect(jsonBlocksIn(result), [
        {'a': 1, 'b': 'tex'},
      ]);
    });

    test('handles multiple consecutive blocks', () async {
      final result = await heal([
        '{"version": "v0.9", "createSurface": {"surfaceId": "s1"}}\n',
        '{"version": "v0.9", "deleteSurface": {"surfaceId": "s1"}}',
      ]);
      final blocks = jsonBlocksIn(result);
      expect(blocks, hasLength(2));
      expect((blocks[0]! as Map).containsKey('createSurface'), isTrue);
      expect((blocks[1]! as Map).containsKey('deleteSurface'), isTrue);
    });

    test('invokes onRepair when a block is fixed', () async {
      var repaired = 0;
      final healer = A2uiJsonHealer(onRepair: (_, _) => repaired++);
      await heal(['{"a": 1,}'], healer: healer);
      expect(repaired, 1);
    });

    test('invokes onDrop and forwards text for unrecoverable JSON', () async {
      var dropped = 0;
      final healer = A2uiJsonHealer(onDrop: (_) => dropped++);
      final result = await heal(['{"a": @@@'], healer: healer);
      expect(dropped, 1);
      expect(result, contains('@@@'));
    });
  });
}
