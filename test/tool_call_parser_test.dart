import 'package:flutter_test/flutter_test.dart';
import 'package:arivu_ai/tools/tool_call_parser.dart';

void main() {
  group('ToolCallParser Unit Tests', () {
    test('Parses standard <tool_call> XML container', () {
      const output = '''
Here is your tool call:
<tool_call>
{"name": "create_reminder", "arguments": {"title": "drink water", "delay_minutes": 30}}
</tool_call>
''';
      final call = ToolCallParser.parse(output);
      expect(call, isNotNull);
      expect(call!.name, 'create_reminder');
      expect(call.arguments['title'], 'drink water');
      expect(call.arguments['delay_minutes'], 30);
    });

    test('Parses raw JSON without XML tags', () {
      const output = '{"name": "torch_control", "arguments": {"action": "on"}}';
      final call = ToolCallParser.parse(output);
      expect(call, isNotNull);
      expect(call!.name, 'torch_control');
      expect(call.arguments['action'], 'on');
    });

    test('Parses Markdown code fence wrapped JSON', () {
      const output = '''
```json
{
  "tool": "set_alarm_or_timer",
  "args": {
    "action": "set_alarm",
    "hour": 7,
    "minute": 30
  }
}
```
''';
      final call = ToolCallParser.parse(output);
      expect(call, isNotNull);
      expect(call!.name, 'set_alarm_or_timer');
      expect(call.arguments['action'], 'set_alarm');
      expect(call.arguments['hour'], 7);
      expect(call.arguments['minute'], 30);
    });

    test('Leniently repairs single quotes and trailing commas from small LLMs', () {
      const output = "{'name': 'create_reminder', 'arguments': {'title': 'call dad', 'delay_minutes': 15,}}";
      final call = ToolCallParser.parse(output);
      expect(call, isNotNull);
      expect(call!.name, 'create_reminder');
      expect(call.arguments['title'], 'call dad');
      expect(call.arguments['delay_minutes'], 15);
    });

    test('Returns null for non-tool or invalid outputs', () {
      expect(ToolCallParser.parse(''), isNull);
      expect(ToolCallParser.parse('I cannot help with that.'), isNull);
      expect(ToolCallParser.parse('NO_TOOL'), isNull);
      expect(ToolCallParser.parse('{"foo": "bar"}'), isNull);
    });
  });
}
