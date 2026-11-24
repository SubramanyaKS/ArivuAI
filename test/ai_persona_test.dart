import 'package:flutter_test/flutter_test.dart';
import 'package:arivu_ai/features/chat/models/ai_persona.dart';
import 'package:arivu_ai/features/chat/service/local_ai_service.dart';

void main() {
  group('AiPersona & PersonaRouter Unit Tests', () {
    test('Auto router delegates coding prompts to Code Mentor', () {
      final resolved = PersonaRouter.resolvePersonaForPrompt(
        selectedPersona: AiPersona.autoRouter,
        prompt: 'Fix this Flutter async FutureBuilder bug and explain Big-O complexity',
      );
      expect(resolved.id, equals('code_mentor'));
      expect(resolved.recommendedTemperature, equals(0.2));
    });

    test('Auto router delegates executive prompts to Executive Assistant', () {
      final resolved = PersonaRouter.resolvePersonaForPrompt(
        selectedPersona: AiPersona.autoRouter,
        prompt: 'Draft a professional email with action items from today\'s meeting',
      );
      expect(resolved.id, equals('executive'));
      expect(resolved.recommendedTemperature, equals(0.3));
    });

    test('Auto router delegates creative prompts to Creative Writer', () {
      final resolved = PersonaRouter.resolvePersonaForPrompt(
        selectedPersona: AiPersona.autoRouter,
        prompt: 'Write a short sci-fi story about a quiet library on Mars',
      );
      expect(resolved.id, equals('creative'));
      expect(resolved.recommendedTemperature, equals(0.75));
    });

    test('Auto router delegates study prompts to Socratic Tutor', () {
      final resolved = PersonaRouter.resolvePersonaForPrompt(
        selectedPersona: AiPersona.autoRouter,
        prompt: 'Teach me how neural networks backpropagate step-by-step',
      );
      expect(resolved.id, equals('socratic'));
    });

    test('Auto router falls back to Arivu Default for general queries', () {
      final resolved = PersonaRouter.resolvePersonaForPrompt(
        selectedPersona: AiPersona.autoRouter,
        prompt: 'What is the capital of Karnataka?',
      );
      expect(resolved.id, equals('default'));
    });

    test('Manual persona selection overrides auto routing', () {
      final resolved = PersonaRouter.resolvePersonaForPrompt(
        selectedPersona: AiPersona.socraticTutor,
        prompt: 'Fix this Dart syntax error in my widget',
      );
      expect(resolved.id, equals('socratic'));
    });

    test('Custom persona preserves non-overridable core safety rules', () {
      final custom = AiPersona.customPersona('Always reply in bullet points.');
      expect(custom.id, equals('custom'));
      expect(custom.systemPrompt, contains('Always reply in bullet points.'));
      expect(custom.systemPrompt, contains('Core Non-Overridable Rules'));
      expect(custom.systemPrompt, contains('Safety:'));
    });

    test('LocalAiService defaults to default persona', () {
      final service = LocalAiService();
      expect(service.activePersona.id, equals('default'));
      expect(service.customPersonaPrompt, isEmpty);
    });
  });
}
