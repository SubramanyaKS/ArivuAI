import '../models/chat_message.dart';

class ChatUtils {
  ChatUtils._();

  /// Generates a truncated title from the first prompt (max 48 runes).
  static String formatConversationTitle(String prompt) {
    final characters = prompt.runes.toList();
    if (characters.length <= 48) return prompt;
    return '${String.fromCharCodes(characters.take(48))}...';
  }

  /// Dynamically computes a safe character budget for conversation history
  /// based on the active model's [contextSize] tokens, [maxGenerationTokens]
  /// reserve, and [systemPromptChars] (~3.5 chars/token heuristic).
  /// Prevents KV-cache overflow on 1K context models and unlocks full history
  /// capacity on 4K context models.
  static int computeMaxInputCharacters({
    required int contextSize,
    required int maxGenerationTokens,
    int systemPromptChars = 1200,
  }) {
    const double charsPerToken = 3.5;
    final systemPromptTokens = (systemPromptChars / charsPerToken).ceil();
    // Reserve tokens for system prompt, generation output, and ChatML template tags
    final availableHistoryTokens =
        contextSize - maxGenerationTokens - systemPromptTokens - 128;
    if (availableHistoryTokens <= 100) {
      return 350;
    }
    return (availableHistoryTokens * charsPerToken).floor();
  }

  /// Builds context window history ensuring character and message limits are respected.
  static List<ChatMessage> buildContextMessages({
    required List<ChatMessage> messages,
    required String prompt,
    required ChatMessage currentMessage,
    int maxInputCharacters = 3000,
    int maxHistoryMessages = 6,
  }) {
    var remainingHistoryCharacters = maxInputCharacters - prompt.runes.length;
    final history = <ChatMessage>[];
    final previousMessages =
        messages.isEmpty ? <ChatMessage>[] : messages.take(messages.length - 1).toList();

    for (final message in previousMessages.reversed) {
      if (history.length == maxHistoryMessages ||
          remainingHistoryCharacters <= 0) {
        break;
      }
      if ((message.role != 'user' && message.role != 'assistant') ||
          message.content.trim().isEmpty) {
        continue;
      }

      final messageCharacters = message.content.runes.length;
      if (messageCharacters > remainingHistoryCharacters) break;

      history.add(message);
      remainingHistoryCharacters -= messageCharacters;
    }

    return [...history.reversed, currentMessage];
  }
}
