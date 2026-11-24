import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../chat/models/chat_message.dart';
import '../../chat/service/local_ai_service.dart';
import '../../chat/widgets/markdown_code_builder.dart';
import '../models/attached_document.dart';
import '../service/document_service.dart';

class _DocChatEntry {
  final String role; // 'user' or 'assistant'
  final String content;
  final List<SourcedDocumentChunk> citedChunks;

  const _DocChatEntry({
    required this.role,
    required this.content,
    this.citedChunks = const [],
  });
}

/// Dedicated interactive workspace for analyzing one or multiple documents.
/// Provides a 2-tab layout:
/// 1. Ask Arivu (One-tap AI workflows + grounded single/multi-doc RAG chat with tappable source citations)
/// 2. Document Viewer (Offline full-text search & chunk explorer with per-document filter chips)
class DocumentWorkspaceScreen extends StatefulWidget {
  DocumentWorkspaceScreen({
    super.key,
    AttachedDocument? document,
    List<AttachedDocument>? documents,
    required this.aiService,
  })  : assert(
          document != null || (documents != null && documents.isNotEmpty),
          'Provide either a single document or a non-empty list of documents.',
        ),
        documents = documents != null && documents.isNotEmpty
            ? documents
            : [document!];

  final List<AttachedDocument> documents;
  final LocalAiService aiService;

  bool get isMultiDoc => documents.length > 1;

  @override
  State<DocumentWorkspaceScreen> createState() =>
      _DocumentWorkspaceScreenState();
}

class _DocumentWorkspaceScreenState extends State<DocumentWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _docSearchController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  final List<_DocChatEntry> _entries = [];
  late List<SourcedDocumentChunk> _allSourcedChunks;
  List<SourcedDocumentChunk> _filteredChunks = [];
  String? _selectedDocFilterId; // null means "All Documents"
  bool _isGenerating = false;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _allSourcedChunks = [
      for (final doc in widget.documents)
        for (final chunk in doc.chunks)
          SourcedDocumentChunk(
            documentId: doc.id,
            documentName: doc.name,
            chunk: chunk,
          ),
    ];
    _filteredChunks = _allSourcedChunks;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _promptController.dispose();
    _docSearchController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _applyViewerFilter() {
    final query = _docSearchController.text.trim().toLowerCase();
    setState(() {
      _filteredChunks = _allSourcedChunks.where((item) {
        if (_selectedDocFilterId != null &&
            item.documentId != _selectedDocFilterId) {
          return false;
        }
        if (query.isNotEmpty &&
            !item.chunk.text.toLowerCase().contains(query)) {
          return false;
        }
        return true;
      }).toList();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _stopGeneration() {
    if (_isGenerating) {
      setState(() {
        _isCancelled = true;
      });
    }
  }

  Future<void> _askDocument(String prompt, {String? displayLabel}) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || _isGenerating) return;

    if (!widget.aiService.isLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for the local AI model to finish loading.'),
        ),
      );
      return;
    }

    _promptController.clear();

    final List<SourcedDocumentChunk> citedChunks;
    final String systemPrompt;

    if (widget.isMultiDoc) {
      citedChunks = DocumentService.instance.retrieveRelevantChunksAcrossDocuments(
        trimmed,
        widget.documents,
        maxChunks: 4,
      );
      systemPrompt = DocumentService.instance.buildMultiDocRagSystemPrompt(
        documents: widget.documents,
        relevantChunks: citedChunks,
      );
    } else {
      final doc = widget.documents.first;
      final relevantChunks = DocumentService.instance.retrieveRelevantChunks(
        trimmed,
        doc.chunks,
        maxChunks: 3,
      );
      citedChunks = relevantChunks
          .map((c) => SourcedDocumentChunk(
                documentId: doc.id,
                documentName: doc.name,
                chunk: c,
              ))
          .toList();
      systemPrompt = DocumentService.instance.buildRagSystemPrompt(
        document: doc,
        relevantChunks: relevantChunks,
      );
    }

    setState(() {
      _entries.add(_DocChatEntry(
        role: 'user',
        content: displayLabel ?? trimmed,
      ));
      _entries.add(_DocChatEntry(
        role: 'assistant',
        content: '',
        citedChunks: citedChunks,
      ));
      _isGenerating = true;
      _isCancelled = false;
    });
    _scrollToBottom();

    final assistantIndex = _entries.length - 1;
    final buffer = StringBuffer();

    try {
      final conversation = [
        ChatMessage(
          conversationId: -1,
          role: 'user',
          content: trimmed,
          createdAt: DateTime.now(),
        ),
      ];

      await for (final token in widget.aiService.askStream(
        conversation,
        systemPrompt: systemPrompt,
      )) {
        if (_isCancelled || !mounted) break;
        buffer.write(token);
        if (buffer.toString().trim().isEmpty) continue;

        setState(() {
          _entries[assistantIndex] = _DocChatEntry(
            role: 'assistant',
            content: buffer.toString(),
            citedChunks: citedChunks,
          );
        });
        _scrollToBottom();
      }

      if (buffer.toString().trim().isEmpty && mounted) {
        setState(() {
          _entries[assistantIndex] = _DocChatEntry(
            role: 'assistant',
            content: _isCancelled
                ? 'Generation stopped.'
                : 'No response generated. Please try rephrasing your question.',
            citedChunks: citedChunks,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _entries[assistantIndex] = _DocChatEntry(
            role: 'assistant',
            content: 'Error analyzing document: $e',
            citedChunks: citedChunks,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  void _showCitationSheet(SourcedDocumentChunk sourced) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Excerpt ${sourced.chunk.index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4F46E5),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sourced.documentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF334155),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy excerpt',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: sourced.chunk.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Excerpt copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const Divider(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: SelectableText(
                    sourced.chunk.text,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.6,
                      color: isDark
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleText = widget.isMultiDoc
        ? 'Cross-Document Analysis'
        : widget.documents.first.name;
    final subtitleText = widget.isMultiDoc
        ? '${widget.documents.length} documents • ${_allSourcedChunks.length} total sections'
        : '${widget.documents.first.sizeFormatted} • ${_allSourcedChunks.length} sections';

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0F1E) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              subtitleText,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4F46E5),
          labelColor: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
          unselectedLabelColor:
              isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          tabs: const [
            Tab(icon: Icon(Icons.auto_awesome_rounded, size: 18), text: 'Ask Arivu'),
            Tab(icon: Icon(Icons.menu_book_rounded, size: 18), text: 'Document Viewer'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAskTab(isDark),
          _buildViewerTab(isDark),
        ],
      ),
    );
  }

  Widget _buildAskTab(bool isDark) {
    return Column(
      children: [
        // One-Tap Quick Document Actions (adapts for single vs multi-doc)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: widget.isMultiDoc
                  ? [
                      _buildQuickActionChip(
                        icon: Icons.compare_arrows_rounded,
                        label: 'Compare Docs',
                        color: const Color(0xFF4F46E5),
                        onTap: () => _askDocument(
                          DocumentService.instance
                              .buildCompareDocumentsPrompt(widget.documents),
                          displayLabel: '⚖️ Compare selected documents',
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildQuickActionChip(
                        icon: Icons.hub_outlined,
                        label: 'Synthesize All',
                        color: const Color(0xFF10B981),
                        onTap: () => _askDocument(
                          DocumentService.instance
                              .buildCrossSynthesisPrompt(widget.documents),
                          displayLabel: '🧩 Synthesize unified summary',
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildQuickActionChip(
                        icon: Icons.checklist_rounded,
                        label: 'All Action Items',
                        color: const Color(0xFFEC4899),
                        onTap: () => _askDocument(
                          DocumentService.instance
                              .buildMultiDocActionItemsPrompt(widget.documents),
                          displayLabel: '✅ Consolidate all action items',
                        ),
                      ),
                    ]
                  : [
                      _buildQuickActionChip(
                        icon: Icons.summarize_rounded,
                        label: 'Summarize',
                        color: const Color(0xFF4F46E5),
                        onTap: () => _askDocument(
                          DocumentService.instance
                              .buildSummaryPrompt(widget.documents.first),
                          displayLabel: '📝 Summarize this document',
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildQuickActionChip(
                        icon: Icons.lightbulb_outline_rounded,
                        label: 'Key Takeaways',
                        color: const Color(0xFFF59E0B),
                        onTap: () => _askDocument(
                          DocumentService.instance
                              .buildKeyTakeawaysPrompt(widget.documents.first),
                          displayLabel: '💡 Extract key takeaways',
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildQuickActionChip(
                        icon: Icons.quiz_outlined,
                        label: 'Generate Q&A',
                        color: const Color(0xFF10B981),
                        onTap: () => _askDocument(
                          DocumentService.instance
                              .buildQaGenerationPrompt(widget.documents.first),
                          displayLabel: '❓ Generate Q&A study pairs',
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildQuickActionChip(
                        icon: Icons.checklist_rounded,
                        label: 'Action Items',
                        color: const Color(0xFFEC4899),
                        onTap: () => _askDocument(
                          DocumentService.instance
                              .buildActionItemsPrompt(widget.documents.first),
                          displayLabel: '✅ Extract action items',
                        ),
                      ),
                    ],
            ),
          ),
        ),

        // Chat List or Empty State
        Expanded(
          child: _entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5)
                                .withValues(alpha: isDark ? 0.18 : 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.isMultiDoc
                                ? Icons.compare_arrows_rounded
                                : Icons.document_scanner_rounded,
                            size: 36,
                            color: const Color(0xFF4F46E5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.isMultiDoc
                              ? 'Cross-Referencing ${widget.documents.length} Documents'
                              : 'Ready to analyze ${widget.documents.first.name}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (widget.isMultiDoc) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: widget.documents
                                .map(
                                  (d) => Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      d.name,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          widget.isMultiDoc
                              ? 'Ask questions or tap Compare Docs above to synthesize insights across all selected files with filename-tagged citations.'
                              : 'Tap a quick action above or ask any specific question. Answers are strictly grounded in this document with tappable citations.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    final isUser = entry.role == 'user';
                    return _buildMessageBubble(entry, isUser, isDark);
                  },
                ),
        ),

        // Input Bar
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    enabled: !_isGenerating,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (val) => _askDocument(val),
                    decoration: InputDecoration(
                      hintText: widget.isMultiDoc
                          ? 'Ask across all ${widget.documents.length} documents...'
                          : 'Ask anything about this document...',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: _isGenerating
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                  ),
                  tooltip: _isGenerating ? 'Stop generating' : 'Ask document',
                  onPressed: _isGenerating
                      ? _stopGeneration
                      : () => _askDocument(_promptController.text),
                  icon: Icon(
                    _isGenerating ? Icons.stop_rounded : Icons.send_rounded,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1E293B),
        ),
      ),
      backgroundColor: isDark
          ? color.withValues(alpha: 0.16)
          : color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: _isGenerating ? null : onTap,
    );
  }

  Widget _buildMessageBubble(_DocChatEntry entry, bool isUser, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.86,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isUser
                  ? const Color(0xFF4F46E5)
                  : (isDark ? const Color(0xFF131B2E) : Colors.white),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              border: isUser
                  ? null
                  : Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                    ),
            ),
            child: isUser
                ? Text(
                    entry.content,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5),
                  )
                : entry.content.isEmpty
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            widget.isMultiDoc
                                ? 'Cross-referencing documents...'
                                : 'Analyzing document...',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      )
                    : MarkdownBody(
                        data: entry.content,
                        selectable: true,
                        builders: {
                          'code': CodeElementBuilder(isDark: isDark),
                        },
                      ),
          ),
          if (!isUser && entry.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...entry.citedChunks.map(
                  (sourced) => InkWell(
                    onTap: () => _showCitationSheet(sourced),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5)
                            .withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.format_quote_rounded,
                            size: 13,
                            color: Color(0xFF4F46E5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.isMultiDoc
                                ? sourced.citationLabel
                                : 'Source: Excerpt ${sourced.chunk.index + 1}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFF818CF8)
                                  : const Color(0xFF4F46E5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy answer',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: entry.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Answer copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewerTab(bool isDark) {
    return Column(
      children: [
        if (widget.isMultiDoc)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All Docs'),
                  selected: _selectedDocFilterId == null,
                  onSelected: (_) {
                    _selectedDocFilterId = null;
                    _applyViewerFilter();
                  },
                ),
                const SizedBox(width: 8),
                ...widget.documents.map(
                  (doc) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(doc.name),
                      selected: _selectedDocFilterId == doc.id,
                      onSelected: (_) {
                        _selectedDocFilterId = doc.id;
                        _applyViewerFilter();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _docSearchController,
            onChanged: (_) => _applyViewerFilter(),
            decoration: InputDecoration(
              hintText: widget.isMultiDoc
                  ? 'Search keywords across selected documents...'
                  : 'Search keywords inside document...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _docSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _docSearchController.clear();
                        _applyViewerFilter();
                      },
                    )
                  : null,
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Row(
            children: [
              Text(
                'Showing ${_filteredChunks.length} of ${_allSourcedChunks.length} sections',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredChunks.isEmpty
              ? Center(
                  child: Text(
                    'No matching text found.',
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                  itemCount: _filteredChunks.length,
                  itemBuilder: (context, idx) {
                    final sourced = _filteredChunks[idx];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      color: isDark ? const Color(0xFF131B2E) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4F46E5)
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      widget.isMultiDoc
                                          ? sourced.citationLabel
                                          : 'Excerpt ${sourced.chunk.index + 1}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? const Color(0xFF818CF8)
                                            : const Color(0xFF4F46E5),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '~${sourced.chunk.tokenEstimate} tokens',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? const Color(0xFF64748B)
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SelectableText(
                              sourced.chunk.text,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.55,
                                color: isDark
                                    ? const Color(0xFFE2E8F0)
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
