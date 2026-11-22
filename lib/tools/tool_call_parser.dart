import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Represents an executable tool call extracted from LLM generation.
class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({
    required this.name,
    this.arguments = const {},
  });

  @override
  String toString() => 'ToolCall(name: $name, arguments: $arguments)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCall &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          mapEquals(arguments, other.arguments);

  @override
  int get hashCode => name.hashCode ^ arguments.hashCode;
}

/// Robust on-device parser for LLM structured tool calling.
///
/// Designed to tolerate small model (0.5B - 1.5B) formatting quirks:
/// - XML wrappers: `<tool_call> ... </tool_call>`
/// - Markdown code fences: ````json ... ````
/// - Raw JSON objects: `{"name": "...", "arguments": {...}}` or `{"tool": "...", "args": {...}}`
/// - Lenient single-quote replacement and trailing comma removal
class ToolCallParser {
  ToolCallParser._();

  /// Attempts to parse a [ToolCall] from model output text.
  /// Returns `null` if no valid tool call is found.
  static ToolCall? parse(String text) {
    if (text.trim().isEmpty) return null;

    // 1. Check for standard XML container
    final xmlMatch = RegExp(r'<tool_call>(.*?)</tool_call>', dotAll: true).firstMatch(text);
    String raw = xmlMatch != null ? xmlMatch.group(1)! : text;

    // 2. Strip Markdown code fences if any
    raw = raw.replaceAll(RegExp(r'```(?:json)?|```'), '').trim();

    // 3. Extract JSON object boundary
    final firstBrace = raw.indexOf('{');
    final lastBrace = raw.lastIndexOf('}');
    if (firstBrace == -1 || lastBrace == -1 || lastBrace <= firstBrace) {
      return null;
    }

    final jsonCandidate = raw.substring(firstBrace, lastBrace + 1);
    final map = _decodeLenient(jsonCandidate);
    if (map == null) return null;

    return _toToolCall(map);
  }

  static Map<String, dynamic>? _decodeLenient(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Small LLMs may produce single quotes or trailing commas
      try {
        final repaired = jsonStr
            .replaceAll("'", '"')
            .replaceAll(RegExp(r',\s*\}'), '}');
        final decoded = jsonDecode(repaired);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (e) {
        debugPrint('[ToolCallParser] Failed to decode JSON: $e');
      }
    }
    return null;
  }

  static ToolCall? _toToolCall(Map<String, dynamic> map) {
    // Supports common tool calling key conventions:
    // name / tool / function
    final name = map['name'] ?? map['tool'] ?? map['function'];
    if (name is! String || name.trim().isEmpty) {
      return null;
    }

    final rawArgs = map['arguments'] ?? map['args'] ?? map['parameters'];
    Map<String, dynamic> arguments = {};

    if (rawArgs is Map) {
      arguments = Map<String, dynamic>.from(rawArgs);
    } else if (rawArgs is String && rawArgs.trim().startsWith('{')) {
      final parsed = _decodeLenient(rawArgs);
      if (parsed != null) arguments = parsed;
    } else {
      // If arguments are at root level (e.g. {"name": "torch_control", "action": "on"})
      final rootArgs = Map<String, dynamic>.from(map)
        ..remove('name')
        ..remove('tool')
        ..remove('function');
      if (rootArgs.isNotEmpty) {
        arguments = rootArgs;
      }
    }

    return ToolCall(
      name: name.trim(),
      arguments: arguments,
    );
  }
}
