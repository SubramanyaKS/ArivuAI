import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:arivu_ai/features/chat/service/chat_utils.dart';
import 'package:arivu_ai/features/chat/service/local_ai_service.dart';
import 'package:arivu_ai/features/document/service/document_service.dart';

void main() {
  group('P0 Stability Guardrails Unit Tests', () {
    test('ChatUtils.computeMaxInputCharacters prevents overflow on 1K context', () {
      // 1K context with 512 maxTokens and a large RAG system prompt (2000 chars)
      final budget = ChatUtils.computeMaxInputCharacters(
        contextSize: 1024,
        maxGenerationTokens: 512,
        systemPromptChars: 2000,
      );
      // Should hit the safe minimum floor (350 chars) rather than overflowing 1024 tokens
      expect(budget, equals(350));
    });

    test('ChatUtils.computeMaxInputCharacters scales up cleanly for 2K and 4K contexts', () {
      final budget1K = ChatUtils.computeMaxInputCharacters(
        contextSize: 1024,
        maxGenerationTokens: 256,
        systemPromptChars: 1000,
      );
      final budget2K = ChatUtils.computeMaxInputCharacters(
        contextSize: 2048,
        maxGenerationTokens: 256,
        systemPromptChars: 1000,
      );
      final budget4K = ChatUtils.computeMaxInputCharacters(
        contextSize: 4096,
        maxGenerationTokens: 512,
        systemPromptChars: 1000,
      );

      expect(budget1K, greaterThan(350));
      expect(budget2K, greaterThan(budget1K));
      expect(budget4K, greaterThan(budget2K));
      expect(budget4K, greaterThan(9000));
    });

    test('LocalAiService exposes isEngineBusy as false when idle', () {
      final service = LocalAiService();
      expect(service.isEngineBusy, isFalse);
      expect(service.isDownloading, isFalse);
    });

    test('LocalAiService tracks and clears OS memory pressure state', () {
      final service = LocalAiService();
      expect(service.hasMemoryPressure, isFalse);

      var notifiedCount = 0;
      service.addListener(() => notifiedCount++);

      service.handleMemoryPressure();
      expect(service.hasMemoryPressure, isTrue);
      expect(notifiedCount, 1);

      service.clearMemoryPressureFlag();
      expect(service.hasMemoryPressure, isFalse);
      expect(notifiedCount, 2);
    });

    test('DocumentService extraction and chunking execute cleanly in a background Isolate', () async {
      final sampleBytes = Uint8List.fromList(
        utf8.encode(
          'Arivu AI runs quantized GGUF models on-device.\n\n'
          'Background isolates prevent main-thread UI jank and Android ANRs during large document ingestion.',
        ),
      );

      final parsed = await Isolate.run(() {
        final text = DocumentService.instance.extractText(
          name: 'isolate_test.txt',
          bytes: sampleBytes,
        );
        final chunks = DocumentService.instance.chunkText(text);
        return (text: text, chunks: chunks);
      });

      expect(parsed.text, contains('Background isolates'));
      expect(parsed.chunks, isNotEmpty);
    });
  });
}
