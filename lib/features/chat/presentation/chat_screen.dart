import 'package:arivu_ai/tools/tool_registry.dart';
import 'package:arivu_ai/features/chat/service/chat_utils.dart';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:arivu_ai/features/chat/models/chat_message.dart';
import 'package:arivu_ai/features/chat/service/chat_database.dart';
import 'package:arivu_ai/features/chat/service/local_ai_service.dart';
import 'package:arivu_ai/features/chat/widgets/chat_empty_widget.dart';
import 'package:arivu_ai/features/settings/presentation/settings_screen.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:arivu_ai/features/chat/service/chat_export_service.dart';
import 'package:arivu_ai/features/chat/widgets/markdown_code_builder.dart';
import 'package:arivu_ai/features/document/models/attached_document.dart';
import 'package:arivu_ai/features/document/service/document_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.aiService});

  final LocalAiService aiService;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final ChatDatabase _chatDatabase = ChatDatabase.instance;
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final stt.SpeechToText _speech = stt.SpeechToText();
  List<Map<String, dynamic>> _conversations = [];
  final FlutterTts _flutterTts = FlutterTts();
  int? _currentConversationId;
  AttachedDocument? _attachedDocument;
  bool _isExtractingDocument = false;
  final ScrollController _scrollController = ScrollController();
  bool _isCancelled = false;

  final bool _modelReady = true;
  bool _isThinking = false;
  bool _hasResponseStarted = false;
  bool _isHistoryReady = false;
  final String _status = 'AI is ready';
  String? _historyError;
  bool isListen = false;
  bool isSpeak = false;
  final double _volume = 1.0;
  final double _pitch = 1.0;
  final double _rate = 0.5;

  @override
  void initState() {
    super.initState();
    _flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() => isSpeak = false);
    });
    _flutterTts.setErrorHandler((message) {
      log('Text-to-speech error: $message');
      if (!mounted) return;
      setState(() => isSpeak = false);
      _showHistoryError('The response could not be spoken.');
    });
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final conversations = await _chatDatabase.getConversations();
      final mostRecent = conversations.isEmpty ? null : conversations.first;
      final messages = mostRecent == null
          ? <ChatMessage>[]
          : await _chatDatabase.getMessages(mostRecent['id'] as int);

      if (!mounted) return;

      setState(() {
        _conversations = conversations;
        _currentConversationId = mostRecent?['id'] as int?;
        _messages
          ..clear()
          ..addAll(messages);
        _historyError = null;
        _isHistoryReady = true;
      });
      _scrollToBottom(animated: false);
    } catch (error, stackTrace) {
      debugPrint('Chat history loading error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _historyError = 'Chat history could not be loaded. Please try again.';
        _isHistoryReady = false;
      });
    }
  }

  Future<void> _refreshConversations() async {
    final conversations = _searchQuery.trim().isEmpty
        ? await _chatDatabase.getConversations()
        : await _chatDatabase.searchConversations(_searchQuery);
    if (!mounted) return;

    setState(() {
      _conversations = conversations;
    });
  }

  Future<void> _onSearchQueryChanged(String query) async {
    setState(() {
      _searchQuery = query;
    });
    try {
      final results = await _chatDatabase.searchConversations(query);
      if (!mounted) return;
      setState(() {
        _conversations = results;
      });
    } catch (error) {
      debugPrint('Search error: $error');
    }
  }

  Future<void> _handleExportOption(String action) async {
    if (_messages.isEmpty) return;

    String title = 'Arivu AI Conversation';
    if (_currentConversationId != null) {
      final matches = _conversations.where((c) => c['id'] == _currentConversationId);
      if (matches.isNotEmpty) {
        title = matches.first['title'] as String? ?? title;
      }
    }

    final markdown = ChatExportService.instance.formatAsMarkdown(
      title: title,
      messages: _messages,
    );

    try {
      switch (action) {
        case 'copy_markdown':
          await ChatExportService.instance.copyToClipboard(markdown);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Conversation copied as Markdown to clipboard'),
                  ],
                ),
                backgroundColor: Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          }
          break;
        case 'share_text':
          await ChatExportService.instance.shareText(
            text: markdown,
            subject: title,
          );
          break;
        case 'share_file':
          final file = await ChatExportService.instance.createExportFile(
            title: title,
            markdown: markdown,
          );
          await ChatExportService.instance.shareFile(
            file: file,
            subject: title,
          );
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _selectConversation(int id) async {
    if (_isThinking) return;
    Navigator.of(context).pop();

    try {
      final messages = await _chatDatabase.getMessages(id);
      if (!mounted) return;

      setState(() {
        _currentConversationId = id;
        _messages
          ..clear()
          ..addAll(messages);
        _historyError = null;
      });
      _scrollToBottom(animated: false);
    } catch (error, stackTrace) {
      debugPrint('Conversation loading error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showHistoryError('This conversation could not be loaded.');
    }
  }

  void _startNewChat({bool closeDrawer = false}) {
    if (_isThinking) return;

    if (closeDrawer) Navigator.of(context).pop();
    setState(() {
      _currentConversationId = null;
      _messages.clear();
    });
  }

  Future<void> _togglePinConversation(int id, bool currentlyPinned) async {
    try {
      await _chatDatabase.togglePinConversation(id, !currentlyPinned);
      await _refreshConversations();
    } catch (error) {
      debugPrint('Pin conversation error: $error');
      _showHistoryError('Could not update pin status.');
    }
  }

  Future<void> _renameConversation(int id, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.drive_file_rename_outline_rounded, color: Color(0xFF4F46E5)),
            SizedBox(width: 8),
            Text('Rename Chat', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Enter conversation title...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.of(ctx).pop(text);
              } else {
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newTitle == null || newTitle == currentTitle || !mounted) return;

    try {
      await _chatDatabase.renameConversation(id, newTitle);
      await _refreshConversations();
    } catch (error) {
      debugPrint('Rename conversation error: $error');
      _showHistoryError('Could not rename conversation.');
    }
  }

  Future<void> _deleteConversation(int id) async {
    final conversation = _conversations.firstWhere((item) => item['id'] == id);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          '"${conversation['title']}" will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    try {
      await _chatDatabase.deleteConversation(id);
      final conversations = await _chatDatabase.getConversations();
      if (!mounted) return;

      if (_currentConversationId == id) {
        final mostRecent = conversations.isEmpty ? null : conversations.first;
        final messages = mostRecent == null
            ? <ChatMessage>[]
            : await _chatDatabase.getMessages(mostRecent['id'] as int);
        if (!mounted) return;

        setState(() {
          _currentConversationId = mostRecent?['id'] as int?;
          _messages
            ..clear()
            ..addAll(messages);
          _conversations = conversations;
        });
      } else {
        setState(() {
          _conversations = conversations;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Conversation deletion error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showHistoryError('This conversation could not be deleted.');
    }
  }

  void _showHistoryError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom({bool animated = true, bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _scrollToBottomIfNear() {
    if (!_scrollController.hasClients) return;
    final distanceToBottom =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    if (distanceToBottom < 160) {
      _scrollToBottom(animated: true);
    }
  }

  void _stopGeneration() {
    if (!_isThinking) return;
    setState(() {
      _isCancelled = true;
      _isThinking = false;
      _hasResponseStarted = false;
    });
  }

  Future<void> _copyMessage(String content) async {
    try {
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Response copied to clipboard')),
      );
    } catch (error, stackTrace) {
      debugPrint('Response copy error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showHistoryError('The response could not be copied.');
    }
  }

  Future<void> _pickDocument() async {
    if (_isThinking || _isExtractingDocument) return;

    setState(() => _isExtractingDocument = true);
    try {
      final doc = await DocumentService.instance.pickDocument();
      if (doc != null && mounted) {
        setState(() {
          _attachedDocument = doc;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Attached ${doc.name} (${doc.sizeFormatted}, ${doc.chunks.length} chunks)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', ''),
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExtractingDocument = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final prompt = _controller.text.trim();

    if (prompt.isEmpty || !_modelReady || !_isHistoryReady || _isThinking) {
      return;
    }

    final docToUse = _attachedDocument;
    final savedPrompt = docToUse != null ? '📄 ${docToUse.name}\n\n$prompt' : prompt;

    setState(() {
      _isThinking = true;
      _hasResponseStarted = false;
    });

    final createdAt = DateTime.now();
    final createdConversation = _currentConversationId == null;
    int? conversationId = _currentConversationId;
    late final ChatMessage userMessage;

    try {
      conversationId ??= await _chatDatabase.createConversation(
        ChatUtils.formatConversationTitle(prompt),
      );

      userMessage = ChatMessage(
        conversationId: conversationId,
        role: 'user',
        content: savedPrompt,
        createdAt: createdAt,
      );

      await _chatDatabase.saveMessage(userMessage);
    } catch (error, stackTrace) {
      debugPrint('User message persistence error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (createdConversation && conversationId != null) {
        try {
          await _chatDatabase.deleteConversation(conversationId);
        } catch (cleanupError, cleanupStackTrace) {
          debugPrint('Empty conversation cleanup error: $cleanupError');
          debugPrintStack(stackTrace: cleanupStackTrace);
        }
      }

      if (!mounted) return;

      setState(() => _isThinking = false);
      _showHistoryError('Your message could not be saved. Please try again.');
      return;
    }

    final savedConversationId = conversationId;

    if (!mounted) return;

    setState(() {
      _currentConversationId = savedConversationId;
      _messages.add(userMessage);
    });

    _scrollToBottom(force: true);
    _controller.clear();

    try {
      await _refreshConversations();
    } catch (error, stackTrace) {
      debugPrint('Conversation list refresh error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showHistoryError('Chat history could not be refreshed.');
    }

    if (!mounted) return;

    await _generateAssistantReply(
      prompt: prompt,
      userMessage: userMessage,
      conversationId: savedConversationId,
      docToUse: docToUse,
    );
  }

  Future<void> _generateAssistantReply({
    required String prompt,
    required ChatMessage userMessage,
    required int conversationId,
    AttachedDocument? docToUse,
  }) async {
    if (!mounted) return;

    // Dispatch through Central Tool Registry (Two-Tier Hybrid Pipeline)
    final toolResult = await ToolRegistry.dispatch(
      prompt,
      aiService: widget.aiService,
    );
    if (toolResult.handled && toolResult.reply != null) {
      final replyMsg = ChatMessage(
        conversationId: conversationId,
        role: 'assistant',
        content: toolResult.reply!,
        createdAt: DateTime.now(),
      );
      await _chatDatabase.saveMessage(replyMsg);
      if (!mounted) return;
      setState(() {
        _messages.add(replyMsg);
        _isThinking = false;
      });
      _scrollToBottom(force: true);
      try {
        await _refreshConversations();
      } catch (_) {}
      return;
    }

    final assistantCreatedAt = DateTime.now();
    final assistantMessageIndex = _messages.length;
    final responseBuffer = StringBuffer();

    // Build context with RAG document injection if a document is attached
    String? ragSystemPrompt;
    if (docToUse != null) {
      final relevantChunks = DocumentService.instance.retrieveRelevantChunks(
        prompt,
        docToUse.chunks,
        maxChunks: 3,
      );
      ragSystemPrompt = DocumentService.instance.buildRagSystemPrompt(
        document: docToUse,
        relevantChunks: relevantChunks,
      );
    }

    // Dynamically align conversation history budget with active contextSize
    final config = widget.aiService.inferenceConfig;
    final effectiveSystemChars =
        (ragSystemPrompt ?? LocalAiService.defaultChatSystemPrompt).length;
    final dynamicMaxChars = ChatUtils.computeMaxInputCharacters(
      contextSize: config.contextSize,
      maxGenerationTokens: config.maxTokens,
      systemPromptChars: effectiveSystemChars,
    );
    final dynamicMaxMessages =
        config.contextSize >= 4096 ? 12 : (config.contextSize >= 2048 ? 8 : 4);

    final contextMessages = ChatUtils.buildContextMessages(
      messages: _messages,
      prompt: prompt,
      currentMessage: userMessage,
      maxInputCharacters: dynamicMaxChars,
      maxHistoryMessages: dynamicMaxMessages,
    );

    _isCancelled = false;

    try {
      await for (final chunk in widget.aiService.askStream(
        contextMessages,
        systemPrompt: ragSystemPrompt,
      )) {
        if (_isCancelled) break;
        responseBuffer.write(chunk);

        if (responseBuffer.toString().trim().isEmpty) continue;
        if (!mounted) return;

        setState(() {
          final message = ChatMessage(
            conversationId: conversationId,
            role: 'assistant',
            content: responseBuffer.toString(),
            createdAt: assistantCreatedAt,
          );
          if (_messages.length == assistantMessageIndex) {
            _messages.add(message);
          } else {
            _messages[assistantMessageIndex] = message;
          }
          _hasResponseStarted = true;
        });

        _scrollToBottomIfNear();
      }

      if (responseBuffer.toString().trim().isEmpty) {
        responseBuffer.clear();
        responseBuffer.write(
          'The AI returned an empty response. Please try rephrasing your question.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Inference error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (responseBuffer.toString().trim().isEmpty) {
        responseBuffer.clear();
        responseBuffer.write(_formatInferenceErrorMessage(error));
      }
    }

    if (!mounted) return;

    final assistantMessage = ChatMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: responseBuffer.toString(),
      createdAt: assistantCreatedAt,
    );

    try {
      await _chatDatabase.saveMessage(assistantMessage);
    } catch (error, stackTrace) {
      debugPrint('Assistant message persistence error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showHistoryError('The response could not be saved to chat history.');
    }

    if (!mounted) return;

    setState(() {
      if (_messages.length == assistantMessageIndex) {
        _messages.add(assistantMessage);
      } else {
        _messages[assistantMessageIndex] = assistantMessage;
      }
      _isThinking = false;
      _hasResponseStarted = false;
    });

    _scrollToBottom();

    try {
      await _refreshConversations();
    } catch (error, stackTrace) {
      debugPrint('Conversation list refresh error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showHistoryError('Chat history could not be refreshed.');
    }
  }

  Future<void> _regenerateLastResponse() async {
    if (_isThinking || _messages.isEmpty || _currentConversationId == null) {
      return;
    }

    final lastMessage = _messages.last;
    if (lastMessage.role != 'assistant') return;

    // Find the user message that prompted this assistant response
    ChatMessage? userMessage;
    for (int i = _messages.length - 2; i >= 0; i--) {
      if (_messages[i].role == 'user') {
        userMessage = _messages[i];
        break;
      }
    }

    if (userMessage == null) return;

    // Delete the last assistant message from database and local list
    try {
      if (lastMessage.id != null) {
        await _chatDatabase.deleteMessage(lastMessage.id!);
      }
    } catch (e) {
      debugPrint('Error deleting message to regenerate: $e');
    }

    setState(() {
      _messages.removeLast();
      _isThinking = true;
      _hasResponseStarted = false;
    });

    _scrollToBottom(force: true);

    await _generateAssistantReply(
      prompt: userMessage.content,
      userMessage: userMessage,
      conversationId: _currentConversationId!,
      docToUse: _attachedDocument,
    );
  }

  Future<void> _showEditPromptDialog(ChatMessage message, int index) async {
    if (_isThinking || _currentConversationId == null) return;

    final editController = TextEditingController(text: message.content);

    final newPrompt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: Color(0xFF4F46E5)),
            SizedBox(width: 8),
            Text('Edit Prompt', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: TextField(
          controller: editController,
          autofocus: true,
          maxLines: 5,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Edit your prompt...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
            ),
            onPressed: () {
              final text = editController.text.trim();
              if (text.isNotEmpty && text != message.content.trim()) {
                Navigator.pop(ctx, text);
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save & Resubmit'),
          ),
        ],
      ),
    );

    if (newPrompt == null || !mounted) return;

    setState(() {
      _isThinking = true;
      _hasResponseStarted = false;
    });

    // Delete message and any subsequent messages in this conversation
    try {
      await _chatDatabase.deleteMessagesFrom(
        conversationId: _currentConversationId!,
        messageId: message.id,
        createdAtMillis: message.createdAt.millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('Error deleting downstream messages on edit: $e');
    }

    final createdAt = DateTime.now();
    final updatedUserMessage = ChatMessage(
      conversationId: _currentConversationId!,
      role: 'user',
      content: newPrompt,
      createdAt: createdAt,
    );

    try {
      await _chatDatabase.saveMessage(updatedUserMessage);
    } catch (e) {
      debugPrint('Error saving edited user message: $e');
    }

    if (!mounted) return;

    setState(() {
      // Truncate list from this index onwards, then add the new user message
      if (index < _messages.length) {
        _messages.removeRange(index, _messages.length);
      }
      _messages.add(updatedUserMessage);
    });

    _scrollToBottom(force: true);

    await _generateAssistantReply(
      prompt: newPrompt,
      userMessage: updatedUserMessage,
      conversationId: _currentConversationId!,
      docToUse: _attachedDocument,
    );
  }

  String _formatInferenceErrorMessage(Object error) {
    final str = error.toString().toLowerCase();

    if (error is OutOfMemoryError ||
        str.contains('out of memory') ||
        str.contains('bad_alloc') ||
        str.contains('cannot allocate') ||
        str.contains('oom')) {
      return '⚠️ **Device Memory Full**: The phone ran out of RAM while generating tokens.\n\n'
          '**How to resolve:**\n'
          '• Switch to a lighter model (such as *SmolLM2-360M* or *Qwen2.5-0.5B*) in **Settings ➔ Manage Models**.\n'
          '• Reduce Context Window Size (e.g. 1024) in **Settings ➔ Inference Parameters**.\n'
          '• Close unused background apps to free up system memory.';
    }

    if (str.contains('context') ||
        str.contains('n_ctx') ||
        str.contains('token limit') ||
        str.contains('exceeded')) {
      return '⚠️ **Context Window Exceeded**: The conversation or attached document exceeds the active context window limit.\n\n'
          '**How to resolve:**\n'
          '• Start a fresh conversation using the **+** button.\n'
          '• Or increase the Context Size (up to 4096) in **Settings ➔ Inference Parameters**.';
    }

    if (str.contains('model has not been loaded') ||
        str.contains('not loaded') ||
        str.contains('null model')) {
      return '⚠️ **Model Not Ready**: The AI model is not loaded in memory.\n\n'
          'Please visit **Settings ➔ Manage Models** to re-activate your model, or restart the app.';
    }

    return '⚠️ **Inference Issue**: An error occurred while generating the response.\n\n'
        'Details: ${error.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '')}\n\n'
        'Please try asking again or starting a new chat.';
  }

  void _listen() async {
    if (!isListen) {
      bool available = await _speech.initialize(
        onStatus: (val) => log('onStatus: $val'),
        onError: (val) => log('onError: $val'),
      );
      debugPrint('Speech recognition available: $available');
      if (available) {
        setState(() => isListen = true);
        _speech.listen(
          listenOptions: stt.SpeechListenOptions(
            onDevice: true,
            partialResults: true,
          ),
          onResult: (val) => setState(() {
            _controller.text = val.recognizedWords;
          }),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone access is unavailable or permission denied. Please enable microphone permission in device Settings.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      setState(() => isListen = false);
      _speech.stop();
    }
  }

  Future<void> _speak(String content) async {
    if (isSpeak || content.trim().isEmpty) return;

    setState(() => isSpeak = true);
    try {
      await _flutterTts.setVolume(_volume);
      await _flutterTts.setPitch(_pitch);
      await _flutterTts.setSpeechRate(_rate);
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.speak(content);
    } catch (error, stackTrace) {
      log('Text-to-speech playback error: $error', stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => isSpeak = false);
      _showHistoryError('The response could not be spoken.');
    }
  }

  Future<void> _stop() async {
    setState(() => isSpeak = false);
    try {
      await _flutterTts.stop();
    } catch (error, stackTrace) {
      log('Text-to-speech stop error: $error', stackTrace: stackTrace);
      _showHistoryError('Speech could not be stopped.');
    }
  }

  Future<void> _toggleSpeech(String content) {
    return isSpeak ? _stop() : _speak(content);
  }

  @override
  void dispose() {
    _isCancelled = true;
    _flutterTts.stop();
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    final visibleMessages = _messages
        .where((message) => message.content.trim().isNotEmpty)
        .toList();

    return SafeArea(
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: 'New chat',
              onPressed: _isThinking ? null : _startNewChat,
              icon: const Icon(Icons.add_comment_outlined),
            ),
            if (_messages.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Export & Share conversation',
                icon: const Icon(Icons.share_outlined),
                onSelected: _handleExportOption,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'share_text',
                    child: Row(
                      children: [
                        Icon(Icons.share_rounded, size: 20, color: Color(0xFF6366F1)),
                        SizedBox(width: 12),
                        Text('Share Conversation'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'copy_markdown',
                    child: Row(
                      children: [
                        Icon(Icons.copy_rounded, size: 20, color: Color(0xFF10B981)),
                        SizedBox(width: 12),
                        Text('Copy as Markdown'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'share_file',
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined, size: 20, color: Color(0xFFF59E0B)),
                        SizedBox(width: 12),
                        Text('Export to .md File'),
                      ],
                    ),
                  ),
                ],
              ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(aiService: widget.aiService),
                  ),
                );
              },
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE0E7FF),
                child: Icon(
                  Icons.smart_toy_rounded,
                  color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Arivu AI',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF172033),
                      ),
                    ),
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 12,
                        color: _modelReady ? const Color(0xFF10B981) : Colors.orange,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        drawer: Drawer(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131B2E) : const Color(0xFFF8FAFC),
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      'Chat history',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('New chat'),
                  enabled: !_isThinking,
                  onTap: _isThinking
                      ? null
                      : () => _startNewChat(closeDrawer: true),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Theme & Settings'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(aiService: widget.aiService),
                      ),
                    );
                  },
                ),
                if (_historyError != null)
                  ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(_historyError!),
                    trailing: IconButton(
                      tooltip: 'Retry loading history',
                      onPressed: _loadHistory,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchQueryChanged,
                    decoration: InputDecoration(
                      hintText: 'Search chats & messages...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchQueryChanged('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _conversations.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _searchQuery.isNotEmpty
                                      ? Icons.search_off_rounded
                                      : Icons.chat_bubble_outline_rounded,
                                  size: 40,
                                  color: isDark ? const Color(0xFF64748B) : Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No chats matching "$_searchQuery"'
                                      : 'No conversations yet',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF64748B) : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _conversations.length,
                          itemBuilder: (context, index) {
                            final conversation = _conversations[index];
                            final id = conversation['id'] as int;
                            final title = conversation['title'] as String;
                            final isPinned = (conversation['is_pinned'] as int? ?? 0) == 1;
                            final snippet = conversation['matching_snippet'] as String?;
                            return ListTile(
                              leading: Icon(
                                isPinned
                                    ? Icons.push_pin_rounded
                                    : Icons.chat_bubble_outline,
                                size: isPinned ? 19 : 20,
                                color: isPinned
                                    ? const Color(0xFF4F46E5)
                                    : null,
                              ),
                              title: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isPinned
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: (snippet != null && snippet.trim().isNotEmpty)
                                  ? Text(
                                      snippet.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                      ),
                                    )
                                  : null,
                              selected: id == _currentConversationId,
                              selectedTileColor: isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFEEF2FF),
                              enabled: !_isThinking,
                              onTap: _isThinking
                                  ? null
                                  : () => _selectConversation(id),
                              trailing: PopupMenuButton<String>(
                                enabled: !_isThinking,
                                tooltip: 'Chat options',
                                icon: const Icon(Icons.more_vert_rounded, size: 19),
                                onSelected: (action) {
                                  if (action == 'pin') {
                                    _togglePinConversation(id, isPinned);
                                  } else if (action == 'rename') {
                                    _renameConversation(id, title);
                                  } else if (action == 'delete') {
                                    _deleteConversation(id);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'pin',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isPinned
                                              ? Icons.push_pin_outlined
                                              : Icons.push_pin_rounded,
                                          size: 18,
                                          color: const Color(0xFF4F46E5),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(isPinned ? 'Unpin chat' : 'Pin to top'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.drive_file_rename_outline_rounded,
                                          size: 18,
                                          color: Color(0xFF10B981),
                                        ),
                                        SizedBox(width: 10),
                                        Text('Rename'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: Color(0xFFEF4444),
                                        ),
                                        SizedBox(width: 10),
                                        Text('Delete'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            if (_historyError != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF78350F).withValues(alpha: 0.3)
                      : const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFFD97706) : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.history_toggle_off,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _historyError!,
                        style: TextStyle(
                          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF684000),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadHistory,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            if (_isHistoryReady && _messages.isEmpty && _historyError == null)
              Expanded(
                child: ChatEmptyWidget(
                  onPromptSelected: (prompt) {
                    _controller
                      ..text = prompt
                      ..selection = TextSelection.collapsed(
                        offset: prompt.length,
                      );
                  },
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 20,
                  ),
                  itemCount: visibleMessages.length +
                      (_isThinking && !_hasResponseStarted ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == visibleMessages.length) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Arivu AI is thinking...',
                              style: TextStyle(
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final message = visibleMessages[index];
                    final isMe = message.role == 'user';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMe) ...[
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFE0E7FF),
                              child: Icon(
                                Icons.smart_toy_rounded,
                                size: 18,
                                color: isDark
                                    ? const Color(0xFF818CF8)
                                    : const Color(0xFF4F46E5),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],

                          Flexible(
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? const Color(0xFF4F46E5)
                                        : (isDark
                                            ? const Color(0xFF131B2E)
                                            : Colors.white),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                                      bottomRight: Radius.circular(isMe ? 4 : 18),
                                    ),
                                    border: isMe
                                        ? null
                                        : Border.all(
                                            color: isDark
                                                ? Colors.white.withValues(alpha: 0.08)
                                                : const Color(0xFFE2E8F0),
                                          ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.2 : 0.04,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: isMe
                                      ? Text(
                                          message.content,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            height: 1.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : MarkdownBody(
                                          data: message.content,
                                          selectable: true,
                                          builders: {
                                            'code': CodeElementBuilder(
                                              isDark: isDark,
                                            ),
                                          },
                                          styleSheet:
                                              MarkdownStyleSheet.fromTheme(
                                            Theme.of(context),
                                          ).copyWith(
                                            p: TextStyle(
                                              fontSize: 15,
                                              height: 1.5,
                                              color: isDark
                                                  ? const Color(0xFFE2E8F0)
                                                  : const Color(0xFF20283A),
                                            ),
                                            h1: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF0F172A),
                                            ),
                                            h2: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF0F172A),
                                            ),
                                            h3: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF0F172A),
                                            ),
                                            listBullet: TextStyle(
                                              fontSize: 15,
                                              color: isDark
                                                  ? const Color(0xFF818CF8)
                                                  : const Color(0xFF4F46E5),
                                            ),
                                            blockquoteDecoration:
                                                BoxDecoration(
                                              color: isDark
                                                  ? const Color(0xFF1E293B)
                                                  : const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border(
                                                left: BorderSide(
                                                  color: isDark
                                                      ? const Color(0xFF818CF8)
                                                      : const Color(0xFF4F46E5),
                                                  width: 3.5,
                                                ),
                                              ),
                                            ),
                                            tableBorder: TableBorder.all(
                                              color: isDark
                                                  ? Colors.white24
                                                  : const Color(0xFFCBD5E1),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            tableHead: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                ),
                                if (!isMe)
                                  Row(
                                    children: [
                                      IconButton(
                                        tooltip: 'Copy response',
                                        onPressed: () =>
                                            _copyMessage(message.content),
                                        icon: Icon(
                                          Icons.copy_rounded,
                                          size: 18,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: isSpeak
                                            ? 'Stop speaking'
                                            : 'Read response aloud',
                                        onPressed: () =>
                                            _toggleSpeech(message.content),
                                        icon: Icon(
                                          isSpeak
                                              ? Icons.stop_rounded
                                              : Icons.volume_up,
                                          size: 18,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                      ),
                                      if (index == visibleMessages.length - 1)
                                        IconButton(
                                          tooltip: 'Regenerate response',
                                          onPressed: _isThinking
                                              ? null
                                              : _regenerateLastResponse,
                                          icon: Icon(
                                            Icons.refresh_rounded,
                                            size: 18,
                                            color: isDark
                                                ? const Color(0xFF94A3B8)
                                                : const Color(0xFF64748B),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                        ),
                                    ],
                                  ),
                                if (isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit prompt',
                                          onPressed: _isThinking
                                              ? null
                                              : () => _showEditPromptDialog(
                                                    message,
                                                    index,
                                                  ),
                                          icon: Icon(
                                            Icons.edit_outlined,
                                            size: 16,
                                            color: isDark
                                                ? const Color(0xFF94A3B8)
                                                : const Color(0xFF64748B),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Copy message',
                                          onPressed: () =>
                                              _copyMessage(message.content),
                                          icon: Icon(
                                            Icons.copy_rounded,
                                            size: 16,
                                            color: isDark
                                                ? const Color(0xFF94A3B8)
                                                : const Color(0xFF64748B),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // Message input area
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Active Attached Document Chip
                  if (_attachedDocument != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _attachedDocument!.extension == 'pdf'
                                ? Icons.picture_as_pdf_rounded
                                : Icons.description_rounded,
                            size: 22,
                            color: const Color(0xFF6366F1),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _attachedDocument!.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${_attachedDocument!.sizeFormatted} • ${_attachedDocument!.chunks.length} chunks indexed for RAG',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Remove document',
                            onPressed: () => setState(() => _attachedDocument = null),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Paperclip Attachment Button
                      Container(
                        height: 48,
                        margin: const EdgeInsets.only(right: 6),
                        child: IconButton(
                          tooltip: 'Attach local document (PDF, TXT, MD)',
                          icon: _isExtractingDocument
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  Icons.attach_file_rounded,
                                  color: _attachedDocument != null
                                      ? const Color(0xFF6366F1)
                                      : (isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B)),
                                ),
                          onPressed: _isThinking ? null : _pickDocument,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF3F5FA),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFFE6E8EF),
                            ),
                          ),
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                            decoration: InputDecoration(
                              hintText: _attachedDocument != null
                                  ? 'Ask about ${_attachedDocument!.name}...'
                                  : 'Message Arivu AI...',
                              hintStyle: TextStyle(
                                color: isDark
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF9299A8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              border: InputBorder.none,
                              suffixIcon: IconButton(
                                tooltip: 'Voice input',
                                icon: Icon(
                                  isListen ? Icons.mic : Icons.mic_none_rounded,
                                  color: isListen
                                      ? const Color(0xFFEF4444)
                                      : (isDark
                                          ? const Color(0xFF94A3B8)
                                          : Colors.grey),
                                ),
                                onPressed: _listen,
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _isThinking
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF4F46E5),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: (_isThinking
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFF4F46E5))
                                  .withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: IconButton(
                          tooltip:
                              _isThinking ? 'Stop generation' : 'Send message',
                          icon: Icon(
                            _isThinking
                                ? Icons.stop_rounded
                                : Icons.arrow_upward_rounded,
                            color: Colors.white,
                          ),
                          onPressed: _isThinking
                              ? _stopGeneration
                              : ((_modelReady && _isHistoryReady)
                                  ? _sendMessage
                                  : null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Arivu AI runs locally on device. AI can make mistakes — verify critical facts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
