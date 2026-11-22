import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arivu_ai/features/chat/service/local_ai_service.dart';
import 'package:arivu_ai/features/document/models/attached_document.dart';
import 'package:arivu_ai/features/document/presentation/document_intelligence_screen.dart';
import 'package:arivu_ai/features/document/presentation/document_workspace_screen.dart';
import 'package:arivu_ai/features/document/service/document_service.dart';

void main() {
  group('Document Intelligence Service Unit Tests', () {
    final sampleDoc = AttachedDocument(
      id: 'doc-1',
      name: 'quarterly_report.pdf',
      path: '/storage/quarterly_report.pdf',
      sizeBytes: 24576,
      fullText: 'Revenue grew by 22% in Q3 due to strong offline AI adoption.\n\n'
          'Action items include launching Document Intelligence and optimizing GPU Vulkan support by December.',
      chunks: const [
        DocumentChunk(
          index: 0,
          text: 'Revenue grew by 22% in Q3 due to strong offline AI adoption.',
        ),
        DocumentChunk(
          index: 1,
          text: 'Action items include launching Document Intelligence and optimizing GPU Vulkan support by December.',
        ),
      ],
    );

    test('Specialized one-tap prompt builders include document name and task intent', () {
      final summary = DocumentService.instance.buildSummaryPrompt(sampleDoc);
      expect(summary, contains('quarterly_report.pdf'));
      expect(summary.toLowerCase(), contains('summary'));

      final takeaways = DocumentService.instance.buildKeyTakeawaysPrompt(sampleDoc);
      expect(takeaways, contains('quarterly_report.pdf'));
      expect(takeaways.toLowerCase(), contains('takeaways'));

      final qa = DocumentService.instance.buildQaGenerationPrompt(sampleDoc);
      expect(qa, contains('quarterly_report.pdf'));
      expect(qa, contains('**Q:**'));

      final actions = DocumentService.instance.buildActionItemsPrompt(sampleDoc);
      expect(actions, contains('quarterly_report.pdf'));
      expect(actions.toLowerCase(), contains('action items'));
    });

    test('searchChunks filters document chunks case-insensitively', () {
      final matches1 = DocumentService.instance.searchChunks('vulkan', sampleDoc.chunks);
      expect(matches1.length, 1);
      expect(matches1.first.index, 1);

      final matches2 = DocumentService.instance.searchChunks('REVENUE', sampleDoc.chunks);
      expect(matches2.length, 1);
      expect(matches2.first.index, 0);

      final allMatches = DocumentService.instance.searchChunks('', sampleDoc.chunks);
      expect(allMatches.length, 2);

      final noMatches = DocumentService.instance.searchChunks('nonexistent_term', sampleDoc.chunks);
      expect(noMatches, isEmpty);
    });

    test('buildRagSystemPrompt grounds assistant in Arivu AI and uses Excerpt numbering', () {
      final prompt = DocumentService.instance.buildRagSystemPrompt(
        document: sampleDoc,
        relevantChunks: [sampleDoc.chunks[1]],
      );
      expect(prompt, contains('Arivu AI'));
      expect(prompt, contains('[Excerpt 2]'));
      expect(prompt, contains('GPU Vulkan support'));
    });
  });

  group('Document Intelligence UI Widget Tests', () {
    testWidgets('Renders empty Knowledge Shelf state when no documents exist', (tester) async {
      final aiService = LocalAiService();
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentIntelligenceScreen(
            aiService: aiService,
            initialDocuments: const [],
          ),
        ),
      );

      expect(find.text('Document Intelligence'), findsOneWidget);
      expect(find.text('Your Offline Knowledge Shelf'), findsOneWidget);
      expect(find.text('Upload PDF, TXT, or MD'), findsOneWidget);
    });

    testWidgets('Renders saved documents and navigates to DocumentWorkspaceScreen on tap', (tester) async {
      final aiService = LocalAiService();
      final doc = AttachedDocument(
        id: 'doc-42',
        name: 'architecture_notes.md',
        path: '/tmp/architecture_notes.md',
        sizeBytes: 4096,
        fullText: 'Arivu AI runs GGUF models locally using llama.cpp.',
        chunks: const [
          DocumentChunk(
            index: 0,
            text: 'Arivu AI runs GGUF models locally using llama.cpp.',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentIntelligenceScreen(
            aiService: aiService,
            initialDocuments: [doc],
          ),
        ),
      );

      expect(find.text('architecture_notes.md'), findsOneWidget);
      expect(find.text('MD'), findsOneWidget);

      // Tap the document card to open the dedicated workspace
      await tester.tap(find.text('architecture_notes.md'));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentWorkspaceScreen), findsOneWidget);
      expect(find.text('Ask Arivu'), findsOneWidget);
      expect(find.text('Document Viewer'), findsOneWidget);
      expect(find.text('Summarize'), findsOneWidget);
      expect(find.text('Key Takeaways'), findsOneWidget);
      expect(find.text('Generate Q&A'), findsOneWidget);
      expect(find.text('Action Items'), findsOneWidget);

      // Switch to Document Viewer tab and verify chunk content is displayed
      await tester.tap(find.text('Document Viewer'));
      await tester.pumpAndSettle();

      expect(find.text('Excerpt 1'), findsOneWidget);
      expect(
        find.text('Arivu AI runs GGUF models locally using llama.cpp.'),
        findsOneWidget,
      );
    });
  });
}
