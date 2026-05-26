// Copyright (c) 2026, the flutter_open_genui authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

/// Repairs the common ways LLMs break the JSON they stream for A2UI messages.
///
/// Google's `genui` parser already buffers split chunks, strips Markdown code
/// fences, and waits for balanced braces. What it does *not* do is *repair* a
/// block that fails [jsonDecode] — it gives up and emits the broken block as
/// chat text, so the surface silently fails to render. This class fills that
/// gap: given a candidate JSON block it fixes the malformations real models
/// produce (trailing commas, single quotes, comments, and truncation from a
/// `maxTokens` cutoff) and returns valid, compact JSON.
abstract final class JsonRepair {
  /// Decodes [input] strictly and returns it re-encoded compactly, or `null`
  /// if [input] is not already valid JSON. Does not attempt any repair.
  static String? strict(String input) => _tryDecode(input.trim());

  /// Attempts to turn [input] into a valid, compact JSON string.
  ///
  /// [input] may be wrapped in a Markdown code fence and may be surrounded by
  /// prose. Returns the re-encoded JSON on success, or `null` if the text
  /// could not be repaired into valid JSON.
  static String? tryRepair(String input) {
    final candidate = _stripFence(input).trim();
    if (candidate.isEmpty) return null;

    // Fast path: already valid once the fence is removed.
    final direct = _tryDecode(candidate);
    if (direct != null) return direct;

    // Drop leading/trailing prose around the first JSON-looking region.
    final sliced = _sliceToJson(candidate);
    if (sliced == null) return null;

    var repaired = sliced;
    repaired = _removeComments(repaired);
    repaired = _normalizeQuotes(repaired);
    repaired = _closeUnterminated(repaired);
    repaired = _removeTrailingCommas(repaired);

    return _tryDecode(repaired);
  }

  /// Returns the index just past the end of the balanced JSON value that starts
  /// at index 0 of [s], or -1 if [s] does not start with `{`/`[` or never
  /// balances. String contents are skipped so braces inside strings don't
  /// count.
  static int balancedEnd(String s) {
    if (s.isEmpty) return -1;
    final open = s[0];
    final close = open == '{'
        ? '}'
        : open == '['
        ? ']'
        : '';
    if (close.isEmpty) return -1;

    var balance = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == open) {
        balance++;
      } else if (c == close) {
        balance--;
        if (balance == 0) return i + 1;
      }
    }
    return -1;
  }

  static String? _tryDecode(String s) {
    if (s.isEmpty) return null;
    try {
      return jsonEncode(jsonDecode(s));
    } on FormatException {
      return null;
    }
  }

  /// Returns the content of a Markdown ```` ```json ```` fence if present.
  /// Tolerates an unterminated opening fence (truncated stream).
  static String _stripFence(String input) {
    final closed = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(input);
    if (closed != null) return closed.group(1) ?? '';
    final open = RegExp(r'```(?:json)?[ \t]*\r?\n?').firstMatch(input);
    if (open != null) return input.substring(open.end);
    return input;
  }

  static String? _sliceToJson(String s) {
    final start = _firstPositive(s.indexOf('{'), s.indexOf('['));
    if (start == -1) return null;
    final sliced = s.substring(start);
    final end = balancedEnd(sliced);
    return end == -1 ? sliced : sliced.substring(0, end);
  }

  static int _firstPositive(int a, int b) {
    if (a == -1) return b;
    if (b == -1) return a;
    return a < b ? a : b;
  }

  static String _removeComments(String s) {
    final sb = StringBuffer();
    var i = 0;
    var inString = false;
    var escaped = false;
    while (i < s.length) {
      final c = s[i];
      if (inString) {
        sb.write(c);
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        i++;
        continue;
      }
      if (c == '"') {
        inString = true;
        sb.write(c);
        i++;
        continue;
      }
      if (c == '/' && i + 1 < s.length) {
        final n = s[i + 1];
        if (n == '/') {
          i += 2;
          while (i < s.length && s[i] != '\n') {
            i++;
          }
          continue;
        }
        if (n == '*') {
          i += 2;
          while (i + 1 < s.length && !(s[i] == '*' && s[i + 1] == '/')) {
            i++;
          }
          i += 2;
          continue;
        }
      }
      sb.write(c);
      i++;
    }
    return sb.toString();
  }

  static String _normalizeQuotes(String s) {
    final sb = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '"') {
        // Copy a double-quoted string verbatim.
        sb.write(c);
        i++;
        while (i < s.length) {
          final d = s[i];
          if (d == r'\' && i + 1 < s.length) {
            sb
              ..write(d)
              ..write(s[i + 1]);
            i += 2;
            continue;
          }
          sb.write(d);
          i++;
          if (d == '"') break;
        }
        continue;
      }
      if (c == "'") {
        // Convert a single-quoted string into a double-quoted one.
        i++;
        final content = StringBuffer();
        while (i < s.length && s[i] != "'") {
          final d = s[i];
          if (d == r'\' && i + 1 < s.length) {
            final e = s[i + 1];
            content.write(e == "'" ? "'" : '$d$e');
            i += 2;
            continue;
          }
          content.write(d == '"' ? r'\"' : d);
          i++;
        }
        i++; // skip the closing quote
        sb
          ..write('"')
          ..write(content)
          ..write('"');
        continue;
      }
      sb.write(c);
      i++;
    }
    return sb.toString();
  }

  static String _removeTrailingCommas(String s) {
    final sb = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        sb.write(c);
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        sb.write(c);
        continue;
      }
      if (c == ',') {
        var j = i + 1;
        while (j < s.length && _isWhitespace(s[j])) {
          j++;
        }
        if (j < s.length && (s[j] == '}' || s[j] == ']')) {
          continue; // drop the dangling comma
        }
      }
      sb.write(c);
    }
    return sb.toString();
  }

  static String _closeUnterminated(String s) {
    final stack = <String>[];
    var inString = false;
    var escaped = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      switch (c) {
        case '"':
          inString = true;
        case '{':
          stack.add('}');
        case '[':
          stack.add(']');
        case '}' || ']':
          if (stack.isNotEmpty) stack.removeLast();
      }
    }

    var result = s;
    if (escaped) {
      // A dangling backslash would escape the quote we are about to add.
      result = result.substring(0, result.length - 1);
    }
    if (inString) result = '$result"';
    for (var k = stack.length - 1; k >= 0; k--) {
      result = '$result${stack[k]}';
    }
    return result;
  }

  static bool _isWhitespace(String c) =>
      c == ' ' || c == '\n' || c == '\r' || c == '\t';
}
