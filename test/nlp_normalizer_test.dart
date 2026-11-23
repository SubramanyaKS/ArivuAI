import 'package:flutter_test/flutter_test.dart';
import 'package:arivu_ai/tools/nlp_normalizer.dart';

void main() {
  group('NlpNormalizer Unit Tests', () {
    test('Normalizes written word numbers to digits', () {
      expect(NlpNormalizer.normalize('remind me in ten minutes'), 'remind me in 10 minutes');
      expect(NlpNormalizer.normalize('timer for five minutes'), 'timer for 5 minutes');
      expect(NlpNormalizer.normalize('set timer for twenty-five seconds'), 'set timer for 25 seconds');
      expect(NlpNormalizer.normalize('set timer for thirty minutes'), 'set timer for 30 minutes');
      expect(NlpNormalizer.normalize('wake me up at six'), 'wake me up at 6');
    });

    test('Normalizes colloquial durations & fractions', () {
      expect(NlpNormalizer.normalize('remind me in half an hour to call mom'), 'remind me in 30 minutes to call mom');
      expect(NlpNormalizer.normalize('remind me in half hour to rest'), 'remind me in 30 minutes to rest');
      expect(NlpNormalizer.normalize('timer for quarter of an hour'), 'timer for 15 minutes');
      expect(NlpNormalizer.normalize('timer for an hour'), 'timer for 1 hour');
      expect(NlpNormalizer.normalize('timer for a minute'), 'timer for 1 minute');
      expect(NlpNormalizer.normalize('remind me in an hour and a half'), 'remind me in 90 minutes');
    });

    test('Normalizes relative clock times', () {
      expect(NlpNormalizer.normalize('wake me up at half past six'), 'wake me up at 6:30');
      expect(NlpNormalizer.normalize('alarm for quarter past seven'), 'alarm for 7:15');
      expect(NlpNormalizer.normalize('alarm for quarter to eight'), 'alarm for 7:45');
      expect(NlpNormalizer.normalize('alarm for quarter to one'), 'alarm for 12:45');
      expect(NlpNormalizer.normalize('alarm for 10 past nine'), 'alarm for 9:10');
      expect(NlpNormalizer.normalize('alarm for 10 to ten'), 'alarm for 9:50');
      expect(NlpNormalizer.normalize('alarm for 20 past four'), 'alarm for 4:20');
      expect(NlpNormalizer.normalize('alarm for 20 to five'), 'alarm for 4:40');
    });

    test('Cleans up speech punctuation & o\'clock', () {
      expect(NlpNormalizer.normalize('alarm for 7 o\'clock'), 'alarm for 7:00');
      expect(NlpNormalizer.normalize('alarm for 7 oclock'), 'alarm for 7:00');
      expect(NlpNormalizer.normalize('alarm for 6.25 p.m.'), 'alarm for 6.25 pm');
      expect(NlpNormalizer.normalize('alarm for 6.25 a.m.'), 'alarm for 6.25 am');
    });

    test('Handles empty and whitespace inputs safely', () {
      expect(NlpNormalizer.normalize(''), '');
      expect(NlpNormalizer.normalize('   '), '');
    });
  });
}
