import '../features/chat/service/local_ai_service.dart';
import 'nlp_normalizer.dart';
import 'pocket_tool.dart';
import 'safety_tool.dart';
import 'battery_tool.dart';
import 'torch_tool.dart';
import 'reminder_parser.dart';
import 'alarm_tool.dart';
import 'calculator_tool.dart';
import 'device_settings_tool.dart';
import 'app_launcher_tool.dart';
import 'tool_call_parser.dart';

class ToolExecutionResult {
  final bool handled;
  final String? reply;
  final String? toolName;
  final bool isFastPath;

  const ToolExecutionResult({
    required this.handled,
    this.reply,
    this.toolName,
    this.isFastPath = true,
  });

  const ToolExecutionResult.unhandled()
      : handled = false,
        reply = null,
        toolName = null,
        isFastPath = false;
}

/// Central Tool Registry managing discovery, schema definition,
/// and deterministic + structured execution of all offline device tools.
class ToolRegistry {
  ToolRegistry._();

  static final List<PocketTool> _tools = [
    const SafetyTool(),
    const TorchTool(),
    const ReminderTool(),
    const BatteryTool(),
    const AlarmTimerTool(),
    const CalculatorTool(),
    const DeviceSettingsTool(),
    const AppLauncherTool(),
  ];

  /// Returns immutable list of registered tools.
  static List<PocketTool> get tools => List.unmodifiable(_tools);

  /// Aggregates LLM tool definitions from all registered tools dynamically.
  static List<Map<String, dynamic>> get definitions =>
      _tools.map((t) => t.definition).toList();

  /// Executes a parsed [ToolCall] against registered tools using structured arguments.
  static Future<String?> executeToolCall(ToolCall toolCall) async {
    for (final tool in _tools) {
      if (tool.name == toolCall.name) {
        return await tool.executeWithArgs(toolCall.arguments);
      }
    }
    return null;
  }

  /// Dispatches user input through the Two-Tier Hybrid Tool Pipeline:
  ///
  /// - **Tier 1 (Fast-Path, <1ms)**: Pre-processes input with [NlpNormalizer] and
  ///   tests all deterministic tool rules without running the LLM.
  /// - **Tier 2 (Structured LLM Fallback)**: If unhandled, and [aiService] is loaded,
  ///   and the input contains action keywords, requests a short structured `<tool_call>`
  ///   from the local LLM and executes the parsed tool.
  static Future<ToolExecutionResult> dispatch(
    String prompt, {
    LocalAiService? aiService,
  }) async {
    final raw = prompt.trim();
    if (raw.isEmpty) return const ToolExecutionResult.unhandled();

    final normalized = NlpNormalizer.normalize(raw);

    // --- Tier 1: Fast-Path Deterministic Execution (<1ms) ---
    for (final tool in _tools) {
      try {
        final reply = await tool.tryExecute(normalized);
        if (reply != null) {
          return ToolExecutionResult(
            handled: true,
            reply: reply,
            toolName: tool.name,
            isFastPath: true,
          );
        }
      } catch (e) {
        continue;
      }
    }

    // --- Tier 2: Structured LLM Fallback ---
    if (aiService != null && aiService.isLoaded && _looksLikeAction(normalized)) {
      try {
        final toolSystemPrompt = LocalAiService.buildToolSystemPrompt(definitions);
        final llmResponse = await aiService.askOnce(
          raw,
          systemPrompt: toolSystemPrompt,
          maxTokens: 80,
          temperature: 0.1,
        );

        final toolCall = ToolCallParser.parse(llmResponse);
        if (toolCall != null) {
          final reply = await executeToolCall(toolCall);
          if (reply != null) {
            return ToolExecutionResult(
              handled: true,
              reply: reply,
              toolName: toolCall.name,
              isFastPath: false,
            );
          }
        }
      } catch (e) {
        // Fallback failure does not break chat
      }
    }

    return const ToolExecutionResult.unhandled();
  }

  /// Heuristic gating to prevent sending pure conversational queries
  /// (e.g. "tell me a story", "what is photosynthesis") to the tool extractor.
  static bool _looksLikeAction(String text) {
    const actionKeywords = [
      'alarm',
      'timer',
      'remind',
      'reminder',
      'clock',
      'wake',
      'torch',
      'flashlight',
      'light',
      'battery',
      'charge',
      'power',
      'calculate',
      'solve',
      'plus',
      'minus',
      'multiply',
      'divided',
      'sqrt',
      '%',
      'setting',
      'settings',
      'wifi',
      'bluetooth',
      'display',
      'airplane',
      'open',
      'launch',
      'app',
      'camera',
      'youtube',
      'maps',
      'whatsapp',
      'browser',
      'spotify',
    ];
    final lower = text.toLowerCase();
    for (final kw in actionKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }
}
