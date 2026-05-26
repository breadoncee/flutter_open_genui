// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_open_genui/flutter_open_genui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonRepair.strict', () {
    test('compacts already-valid JSON', () {
      expect(JsonRepair.strict('{ "a" : 1 }'), '{"a":1}');
    });

    test('returns null for invalid JSON without repairing', () {
      expect(JsonRepair.strict('{"a": 1,}'), isNull);
    });
  });

  group('JsonRepair.tryRepair', () {
    test('passes through valid JSON compacted', () {
      expect(
        JsonRepair.tryRepair('{"a": 1, "b": [2, 3]}'),
        '{"a":1,"b":[2,3]}',
      );
    });

    test('extracts JSON from a Markdown json fence', () {
      expect(JsonRepair.tryRepair('```json\n{"a": 1}\n```'), '{"a":1}');
    });

    test('extracts JSON from a bare ``` fence', () {
      expect(JsonRepair.tryRepair('```\n{"a": 1}\n```'), '{"a":1}');
    });

    test('removes a trailing comma in an object', () {
      expect(JsonRepair.tryRepair('{"a": 1, "b": 2,}'), '{"a":1,"b":2}');
    });

    test('removes a trailing comma in an array', () {
      expect(JsonRepair.tryRepair('{"a": [1, 2, 3,]}'), '{"a":[1,2,3]}');
    });

    test('converts single quotes to double quotes', () {
      expect(JsonRepair.tryRepair("{'a': 'hello'}"), '{"a":"hello"}');
    });

    test('keeps apostrophes inside double-quoted strings', () {
      expect(JsonRepair.tryRepair('{"a": "it\'s fine"}'), '{"a":"it\'s fine"}');
    });

    test('strips line comments', () {
      const input = '{\n  "a": 1, // the value\n  "b": 2\n}';
      expect(JsonRepair.tryRepair(input), '{"a":1,"b":2}');
    });

    test('strips block comments', () {
      expect(JsonRepair.tryRepair('{"a": /* x */ 1}'), '{"a":1}');
    });

    test('closes a truncated object', () {
      expect(JsonRepair.tryRepair('{"a": 1, "b": 2'), '{"a":1,"b":2}');
    });

    test('closes a truncated string and object', () {
      expect(JsonRepair.tryRepair('{"a": "hello'), '{"a":"hello"}');
    });

    test('closes a truncated nested structure', () {
      final repaired = JsonRepair.tryRepair('{"a": {"b": [1, 2');
      expect(repaired, isNotNull);
      expect(jsonDecode(repaired!), {
        'a': {
          'b': [1, 2],
        },
      });
    });

    test('drops leading prose before the object', () {
      expect(JsonRepair.tryRepair('Sure! Here you go: {"a": 1}'), '{"a":1}');
    });

    test('drops trailing prose after the object', () {
      expect(JsonRepair.tryRepair('{"a": 1} hope that helps!'), '{"a":1}');
    });

    test('repairs a top-level array even when an object brace comes first', () {
      expect(
        JsonRepair.tryRepair('[{"a": 1}, {"b": 2},]'),
        '[{"a":1},{"b":2}]',
      );
    });

    test('handles a realistic A2UI createSurface block', () {
      const input = '''
```json
{
  "version": "v0.9",
  "createSurface": {
    "surfaceId": "s1",
    "catalogId": "basic",
    "sendDataModel": true,
  }
}
```''';
      final repaired = JsonRepair.tryRepair(input);
      expect(repaired, isNotNull);
      final decoded = jsonDecode(repaired!) as Map<String, Object?>;
      expect(decoded['version'], 'v0.9');
      expect((decoded['createSurface']! as Map)['surfaceId'], 's1');
    });

    test('returns null for text with no JSON', () {
      expect(JsonRepair.tryRepair('just some prose here'), isNull);
    });

    test('returns null for hopelessly broken JSON', () {
      expect(JsonRepair.tryRepair('{"a": @@@ }'), isNull);
    });
  });

  group('JsonRepair.balancedEnd', () {
    test('finds the end of a balanced object', () {
      expect(JsonRepair.balancedEnd('{"a": 1} trailing'), 8);
    });

    test('ignores braces inside strings', () {
      expect(JsonRepair.balancedEnd('{"a": "}"}'), 10);
    });

    test('returns -1 for an unbalanced object', () {
      expect(JsonRepair.balancedEnd('{"a": 1'), -1);
    });

    test('returns -1 when not starting with a bracket', () {
      expect(JsonRepair.balancedEnd('prose {"a":1}'), -1);
    });
  });
}
