import 'package:flutter_test/flutter_test.dart';
import 'package:arivu_ai/tools/safety_tool.dart';
import 'package:arivu_ai/tools/tool_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SafetyTool & Responsible AI Crisis Interceptor Tests', () {
    const safetyTool = SafetyTool();

    test('Tool metadata and definition are valid', () {
      expect(safetyTool.name, 'safety_crisis_support');
      expect(safetyTool.definition['name'], 'safety_crisis_support');
      expect(safetyTool.definition['description'], contains('self-harm'));
    });

    test('Identifies acute crisis, self-harm, and suicidal intent', () {
      expect(SafetyTool.isCrisisQuery('I want to kill myself'), isTrue);
      expect(SafetyTool.isCrisisQuery('I feel like committing suicide'), isTrue);
      expect(SafetyTool.isCrisisQuery('how to end my life'), isTrue);
      expect(SafetyTool.isCrisisQuery('I want to die'), isTrue);
      expect(SafetyTool.isCrisisQuery('thoughts of self harm'), isTrue);
      expect(SafetyTool.isCrisisQuery('cutting myself'), isTrue);
      expect(SafetyTool.isCrisisQuery('life is not worth living anymore'), isTrue);
    });

    test('Rejects non-crisis and informational questions', () {
      expect(SafetyTool.isCrisisQuery('what is the capital of France?'), isFalse);
      expect(SafetyTool.isCrisisQuery('turn on flashlight'), isFalse);
      expect(SafetyTool.isCrisisQuery('calculate 15 * 8'), isFalse);
      expect(SafetyTool.isCrisisQuery('set an alarm for 7 am'), isFalse);
      expect(SafetyTool.isCrisisQuery('tell me a funny joke'), isFalse);
      expect(SafetyTool.isCrisisQuery('how do cells die naturally (apoptosis)?'), isFalse);
    });

    test('Returns supportive response with regional lifelines', () async {
      final reply = await safetyTool.tryExecute('I want to end my life');
      expect(reply, isNotNull);
      expect(reply, contains('You are not alone'));
      expect(reply, contains('14416')); // Tele-MANAS India
      expect(reply, contains('988')); // US/Canada
      expect(reply, contains('111')); // UK
      expect(reply, contains('findahelpline.com'));
    });

    test('Spoken crisis response is clean plain text without markdown', () {
      final spoken = SafetyTool.getSpokenCrisisResponse();
      expect(spoken, isNotEmpty);
      expect(spoken, isNot(contains('**')));
      expect(spoken, isNot(contains('[')));
      expect(spoken, contains('You are not alone'));
      expect(spoken, contains('14416'));
    });

    test('ToolRegistry prioritizes SafetyTool for crisis queries', () async {
      final result = await ToolRegistry.dispatch('I feel like committing suicide');
      expect(result.handled, isTrue);
      expect(result.toolName, 'safety_crisis_support');
      expect(result.reply, contains('You are not alone'));
    });
  });
}
