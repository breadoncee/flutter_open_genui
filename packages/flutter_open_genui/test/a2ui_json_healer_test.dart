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

/// Decodes the payload of each `<a2ui-json>` block the downstream parser
/// would see in healed text.
List<Object?> jsonBlocksIn(String text) => [
  for (final match in RegExp(
    r'<a2ui-json>([\s\S]*?)</a2ui-json>',
  ).allMatches(text))
    jsonDecode(match.group(1)!),
];

void main() {
  group('A2uiJsonHealer', () {
    test('forwards a valid block split across chunk boundaries', () async {
      final result = await heal([
        'Here you go <a2',
        'ui-json>[{"ver',
        'sion": "v0',
        '.9"}]</a2ui',
        '-json> done',
      ]);
      expect(
        result,
        'Here you go <a2ui-json>[{"version": "v0.9"}]</a2ui-json> done',
      );
    });

    test('repairs a trailing comma in a streamed block', () async {
      final result = await heal([
        '<a2ui-json>[{"a": 1, "b": 2,},]</a2ui-json>',
      ]);
      expect(jsonBlocksIn(result), [
        [
          {'a': 1, 'b': 2},
        ],
      ]);
    });

    test('repairs a block inside a Markdown fence', () async {
      final result = await heal([
        '<a2ui-json>\n```json\n',
        "[{'a': 1}]\n",
        '```\n</a2ui-json>',
      ]);
      expect(jsonBlocksIn(result), [
        [
          {'a': 1},
        ],
      ]);
    });

    test('passes prose through untouched', () async {
      final result = await heal(['Thinking about {it}... ']);
      expect(result, 'Thinking about {it}... ');
    });

    test('handles prose followed by a block', () async {
      final result = await heal([
        'Here: ',
        '<a2ui-json>[{"a": 1}]</a2ui-json>',
      ]);
      expect(result, startsWith('Here: '));
      expect(jsonBlocksIn(result), [
        [
          {'a': 1},
        ],
      ]);
    });

    test('ignores a close tag inside a JSON string', () async {
      final result = await heal([
        '<a2ui-json>[{"text": "</a2ui-json>"}]</a2ui-json>',
      ]);
      expect(result, '<a2ui-json>[{"text": "</a2ui-json>"}]</a2ui-json>');
    });

    test(
      'repairs and closes a truncated final block on stream close',
      () async {
        final result = await heal(['<a2ui-json>[{"a": 1, "b": "tex']);
        expect(jsonBlocksIn(result), [
          [
            {'a': 1, 'b': 'tex'},
          ],
        ]);
      },
    );

    test('handles multiple consecutive blocks', () async {
      final result = await heal([
        '<a2ui-json>[{"version": "v0.9", "createSurface": '
            '{"surfaceId": "s1"}}]</a2ui-json>\n',
        '<a2ui-json>[{"version": "v0.9", "deleteSurface": '
            '{"surfaceId": "s1"}}]</a2ui-json>',
      ]);
      final blocks = jsonBlocksIn(result);
      expect(blocks, hasLength(2));
      expect(
        ((blocks[0]! as List).single as Map).containsKey('createSurface'),
        isTrue,
      );
      expect(
        ((blocks[1]! as List).single as Map).containsKey('deleteSurface'),
        isTrue,
      );
    });

    test('invokes onRepair when a block is fixed', () async {
      var repaired = 0;
      final healer = A2uiJsonHealer(onRepair: (_, _) => repaired++);
      await heal(['<a2ui-json>[{"a": 1,}]</a2ui-json>'], healer: healer);
      expect(repaired, 1);
    });

    test('invokes onDrop and forwards text for unrecoverable JSON', () async {
      var dropped = 0;
      final healer = A2uiJsonHealer(onDrop: (_) => dropped++);
      final result = await heal([
        '<a2ui-json>[{"a": @@@</a2ui-json>',
      ], healer: healer);
      expect(dropped, 1);
      expect(result, contains('@@@'));
    });
  });
}
