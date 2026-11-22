import 'package:flutter/material.dart';
import '../../chat/service/local_ai_service.dart';
import '../models/attached_document.dart';
import '../service/document_service.dart';
import 'document_workspace_screen.dart';

/// Dedicated Document Intelligence Hub (Knowledge Shelf).
/// Allows users to upload, persist, organize, and analyze PDF, TXT, and Markdown
/// files completely offline using local BM25 RAG and on-device LLM inference.
class DocumentIntelligenceScreen extends StatefulWidget {
  const DocumentIntelligenceScreen({
    super.key,
    required this.aiService,
    this.initialDocuments,
  });

  final LocalAiService aiService;

  /// Optional pre-populated documents for testing or previews.
  final List<AttachedDocument>? initialDocuments;

  @override
  State<DocumentIntelligenceScreen> createState() =>
      _DocumentIntelligenceScreenState();
}

class _DocumentIntelligenceScreenState
    extends State<DocumentIntelligenceScreen> {
  List<AttachedDocument> _documents = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialDocuments != null) {
      _documents = List<AttachedDocument>.from(widget.initialDocuments!);
      _isLoading = false;
    } else {
      _loadLibrary();
    }
  }

  Future<void> _loadLibrary() async {
    setState(() => _isLoading = true);
    final docs = await DocumentService.instance.loadLibrary();
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _isLoading = false;
    });
  }

  Future<void> _uploadDocument() async {
    if (_isUploading) return;
    setState(() => _isUploading = true);

    try {
      final doc = await DocumentService.instance.pickDocument();
      if (doc != null) {
        await DocumentService.instance.saveToLibrary(doc);
        if (!mounted) return;
        setState(() {
          _documents.insert(0, doc);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${doc.name}" to your Knowledge Shelf'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not import document: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _confirmDelete(AttachedDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Remove Document?'),
        content: Text(
          'Remove "${doc.name}" from your offline Knowledge Shelf? The original file on your device will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DocumentService.instance.deleteFromLibrary(doc.id);
      if (!mounted) return;
      setState(() {
        _documents.removeWhere((d) => d.id == doc.id);
      });
    }
  }

  void _openWorkspace(AttachedDocument doc) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentWorkspaceScreen(
          document: doc,
          aiService: widget.aiService,
        ),

      ),
    );
  }

  Color _badgeColor(String ext) {
    switch (ext) {
      case 'pdf':
        return const Color(0xFFEF4444);
      case 'md':
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFF10B981);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visibleDocs = _searchQuery.trim().isEmpty
        ? _documents
        : _documents
            .where((d) =>
                d.name.toLowerCase().contains(_searchQuery.trim().toLowerCase()))
            .toList();

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0F1E) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0.5,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Document Intelligence',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '100% Offline Knowledge Shelf',
              style: TextStyle(fontSize: 12, color: Color(0xFF10B981)),
            ),
          ],
        ),
        actions: [
          if (_isUploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Upload PDF, TXT, or Markdown',
              onPressed: _uploadDocument,
              icon: const Icon(Icons.upload_file_rounded),
            ),
        ],
      ),
      floatingActionButton: _documents.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              onPressed: _isUploading ? null : _uploadDocument,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Document'),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _documents.isEmpty
              ? _buildEmptyState(isDark)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search your Knowledge Shelf...',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFE2E8F0),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: visibleDocs.isEmpty
                          ? Center(
                              child: Text(
                                'No documents match "$_searchQuery"',
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                              itemCount: visibleDocs.length,
                              itemBuilder: (context, index) {
                                final doc = visibleDocs[index];
                                return _buildDocumentCard(doc, isDark);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildDocumentCard(AttachedDocument doc, bool isDark) {
    final ext = doc.extension.isEmpty ? 'TXT' : doc.extension.toUpperCase();
    final color = _badgeColor(doc.extension);
    final wordCount = doc.fullText.trim().isEmpty
        ? 0
        : doc.fullText.trim().split(RegExp(r'\s+')).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isDark ? const Color(0xFF131B2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openWorkspace(doc),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.description_rounded, color: color, size: 22),
                    Text(
                      ext,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${doc.sizeFormatted} • ${doc.chunks.length} sections • ~$wordCount words',
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
              IconButton(
                tooltip: 'Remove from library',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
                onPressed: () => _confirmDelete(doc),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5)
                    .withValues(alpha: isDark ? 0.18 : 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_stories_rounded,
                size: 48,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your Offline Knowledge Shelf',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Upload PDFs, text notes, or Markdown files to summarize, extract key takeaways, generate Q&A flashcards, and chat with verified citations—100% offline on your device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _isUploading ? null : _uploadDocument,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text(
                'Upload PDF, TXT, or MD',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
