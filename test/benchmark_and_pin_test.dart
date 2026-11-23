import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arivu_ai/features/chat/service/local_ai_service.dart';
import 'package:arivu_ai/features/settings/presentation/benchmark_screen.dart';

void main() {
  group('BenchmarkResult Unit Tests', () {
    test('Computes tokensPerSecond, wordsPerSecond, and speed rating accurately', () {
      const fast = BenchmarkResult(
        modelName: 'SmolLM2 360M',
        modelSize: '386 MB',
        contextSize: 2048,
        threads: 4,
        ttftMs: 180,
        totalDurationMs: 2000,
        estimatedTokens: 40,
        wordCount: 30,
        modelLoadTimeMs: 950,
      );

      expect(fast.tokensPerSecond, closeTo(20.0, 0.01));
      expect(fast.wordsPerSecond, closeTo(15.0, 0.01));
      expect(fast.ratingLabel, equals('Blazing Fast'));

      final report = fast.toMarkdownReport();
      expect(report, contains('SmolLM2 360M'));
      expect(report, contains('20.0 tok/s'));
      expect(report, contains('180ms'));
      expect(report, contains('0.95s'));
      expect(report, contains('Blazing Fast'));
    });

    test('Assigns correct ratings across speed tiers', () {
      const smooth = BenchmarkResult(
        modelName: 'Qwen3 0.6B',
        modelSize: '639 MB',
        contextSize: 2048,
        threads: 4,
        ttftMs: 320,
        totalDurationMs: 5000,
        estimatedTokens: 50,
        wordCount: 38,
      );
      expect(smooth.ratingLabel, equals('Smooth'));

      const moderate = BenchmarkResult(
        modelName: 'Qwen2.5 1.5B',
        modelSize: '1.03 GB',
        contextSize: 2048,
        threads: 4,
        ttftMs: 650,
        totalDurationMs: 10000,
        estimatedTokens: 60,
        wordCount: 45,
      );
      expect(moderate.ratingLabel, equals('Moderate'));

      const heavy = BenchmarkResult(
        modelName: 'Heavy Model',
        modelSize: '2.0 GB',
        contextSize: 4096,
        threads: 2,
        ttftMs: 1500,
        totalDurationMs: 10000,
        estimatedTokens: 20,
        wordCount: 15,
      );
      expect(heavy.ratingLabel, equals('Lightweight Model Recommended'));
    });
  });

  group('BenchmarkScreen Widget Tests', () {
    testWidgets('Renders model metadata and Run Standardized Benchmark CTA', (tester) async {
      final aiService = LocalAiService();
      await tester.pumpWidget(
        MaterialApp(
          home: BenchmarkScreen(aiService: aiService),
        ),
      );

      expect(find.text('Benchmark My Phone'), findsOneWidget);
      expect(find.text('Run Standardized Benchmark'), findsOneWidget);
      expect(find.text(aiService.activeModel.name), findsOneWidget);

      // Tapping Run when model is not loaded displays graceful error banner
      await tester.tap(find.text('Run Standardized Benchmark'));
      await tester.pump();

      expect(
        find.text('No model is currently loaded. Please load a model first.'),
        findsOneWidget,
      );
    });
  });
}
