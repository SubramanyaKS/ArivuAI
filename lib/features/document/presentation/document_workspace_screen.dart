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
  final List<DocumentChunk> citedChunks;

  const _DocChatEntry({
    required this.role,
    required this.content,
    this.citedChunks = const [],
  });
}

/// Dedicated interactive workspace for analyzing a single document.
/// Provides a 2-tab layout:
/// 1. Ask Arivu (One-tap AI workflows + grounded RAG chat with tappable source citations)
/// 2. Document Viewer (Offline full-text search & chunk explorer)
class DocumentWorkspaceScreen extends StatefulWidget {
  const DocumentWorkspaceScreen({
    super.key,
    required this.document,
    required this.aiService,
  });

  final AttachedDocument document;
  final LocalAiService aiService;

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
  List<DocumentChunk> _filteredChunks = [];
  bool _isGenerating = false;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _filteredChunks = widget.document.chunks;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _promptController.dispose();
    _docSearchController.dispose();
    _chatScrollController.dispose();
    super.dispose();
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

    // Retrieve top relevant chunks via offline BM25
    final relevantChunks = DocumentService.instance.retrieveRelevantChunks(
      trimmed,
      widget.document.chunks,
      maxChunks: 3,
    );

    final systemPrompt = DocumentService.instance.buildRagSystemPrompt(
      document: widget.document,
      relevantChunks: relevantChunks,
    );

    setState(() {
      _entries.add(_DocChatEntry(
        role: 'user',
        content: displayLabel ?? trimmed,
      ));
      _entries.add(_DocChatEntry(
        role: 'assistant',
        content: '',
        citedChunks: relevantChunks,
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
            citedChunks: relevantChunks,
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
            citedChunks: relevantChunks,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _entries[assistantIndex] = _DocChatEntry(
            role: 'assistant',
            content: 'Error analyzing document: $e',
            citedChunks: relevantChunks,
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

  void _showCitationSheet(DocumentChunk chunk) {
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
                      'Excerpt ${chunk.index + 1}',
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
                      widget.document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy excerpt',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: chunk.text));
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
                    chunk.text,
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
              widget.document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${widget.document.sizeFormatted} • ${widget.document.chunks.length} sections',
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
    final doc = widget.document;
    return Column(
      children: [
        // One-Tap Quick Document Actions
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
              children: [
                _buildQuickActionChip(
                  icon: Icons.summarize_rounded,
                  label: 'Summarize',
                  color: const Color(0xFF4F46E5),
                  onTap: () => _askDocument(
                    DocumentService.instance.buildSummaryPrompt(doc),
                    displayLabel: '📝 Summarize this document',
                  ),
                ),
                const SizedBox(width: 8),
                _buildQuickActionChip(
                  icon: Icons.lightbulb_outline_rounded,
                  label: 'Key Takeaways',
                  color: const Color(0xFFF59E0B),
                  onTap: () => _askDocument(
                    DocumentService.instance.buildKeyTakeawaysPrompt(doc),
                    displayLabel: '💡 Extract key takeaways',
                  ),
                ),
                const SizedBox(width: 8),
                _buildQuickActionChip(
                  icon: Icons.quiz_outlined,
                  label: 'Generate Q&A',
                  color: const Color(0xFF10B981),
                  onTap: () => _askDocument(
                    DocumentService.instance.buildQaGenerationPrompt(doc),
                    displayLabel: '❓ Generate Q&A study pairs',
                  ),
                ),
                const SizedBox(width: 8),
                _buildQuickActionChip(
                  icon: Icons.checklist_rounded,
                  label: 'Action Items',
                  color: const Color(0xFFEC4899),
                  onTap: () => _askDocument(
                    DocumentService.instance.buildActionItemsPrompt(doc),
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
                          child: const Icon(
                            Icons.document_scanner_rounded,
                            size: 36,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ready to analyze ${doc.name}',
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
                        Text(
                          'Tap a quick action above or ask any specific question. Answers are strictly grounded in this document with tappable citations.',
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
                      hintText: 'Ask anything about this document...',
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
                            'Analyzing document...',
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
                  (chunk) => InkWell(
                    onTap: () => _showCitationSheet(chunk),
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
                            'Source: Excerpt ${chunk.index + 1}',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _docSearchController,
            onChanged: (val) {
              setState(() {
                _filteredChunks = DocumentService.instance
                    .searchChunks(val, widget.document.chunks);
              });
            },
            decoration: InputDecoration(
              hintText: 'Search keywords inside document...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _docSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _docSearchController.clear();
                        setState(() {
                          _filteredChunks = widget.document.chunks;
                        });
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
                'Showing ${_filteredChunks.length} of ${widget.document.chunks.length} sections',
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
                    final chunk = _filteredChunks[idx];
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
                                Container(
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
                                    'Excerpt ${chunk.index + 1}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? const Color(0xFF818CF8)
                                          : const Color(0xFF4F46E5),
                                    ),
                                  ),
                                ),
                                Text(
                                  '~${chunk.tokenEstimate} tokens',
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
                              chunk.text,
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
