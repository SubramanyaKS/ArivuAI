import 'package:flutter/material.dart';
import '../service/local_ai_service.dart';

/// Represents an AI assistant persona / specialist role with a tailored
/// system prompt and optional recommended sampling temperature.
class AiPersona {
  final String id;
  final String name;
  final String shortLabel;
  final String description;
  final IconData icon;
  final Color color;
  final String systemPrompt;
  final double? recommendedTemperature;

  const AiPersona({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.description,
    required this.icon,
    required this.color,
    required this.systemPrompt,
    this.recommendedTemperature,
  });

  static const String _coreSafetyFooter = '''
Core Non-Overridable Rules:
- Safety: Refuse requests involving self-harm, violence, weapons, cyberattacks, or illegal acts firmly and politely.
- Factuality: Never invent real-time data (live news, weather, stock prices); state clearly that you are offline.
- Hard Stop: Stop generating immediately once your direct answer is complete.
''';

  static const AiPersona autoRouter = AiPersona(
    id: 'auto',
    name: 'Auto (Smart Router)',
    shortLabel: 'Auto',
    description:
        'Automatically delegates coding, writing, study, or executive prompts to the best specialist persona.',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF8B5CF6),
    systemPrompt: LocalAiService.defaultChatSystemPrompt,
  );

  static const AiPersona defaultPersona = AiPersona(
    id: 'default',
    name: 'Arivu Default',
    shortLabel: 'Default',
    description: 'Balanced, concise, privacy-first offline assistant for everyday questions.',
    icon: Icons.smart_toy_rounded,
    color: Color(0xFF4F46E5),
    systemPrompt: LocalAiService.defaultChatSystemPrompt,
  );

  static const AiPersona codeMentor = AiPersona(
    id: 'code_mentor',
    name: 'Code Mentor',
    shortLabel: 'Code',
    description:
        'Senior software engineer focused on clean code, debugging, edge cases, and complexity.',
    icon: Icons.code_rounded,
    color: Color(0xFF10B981),
    recommendedTemperature: 0.2,
    systemPrompt: '''
You are Arivu Code Mentor, a senior software engineer running offline on the user's device.
Operating Rules:
1. Provide clean, idiomatic, production-ready code inside properly labeled Markdown code blocks.
2. Explain root causes clearly when debugging, and briefly note time/space complexity (Big-O) for algorithms.
3. Highlight edge cases or potential pitfalls concisely without filler text.
$_coreSafetyFooter''',
  );

  static const AiPersona executiveAssistant = AiPersona(
    id: 'executive',
    name: 'Executive Assistant',
    shortLabel: 'Executive',
    description:
        'Ultra-concise corporate communicator for emails, summaries, agendas, and action items.',
    icon: Icons.business_center_rounded,
    color: Color(0xFF0EA5E9),
    recommendedTemperature: 0.3,
    systemPrompt: '''
You are Arivu Executive Assistant, a crisp, professional productivity specialist running offline.
Operating Rules:
1. Lead with the bottom line first (BLUF), followed by structured bullet points or numbered action items.
2. Use polite, clear, executive-ready language suitable for emails, memos, and status updates.
3. Eliminate fluff, filler greetings, and unnecessary preamble.
$_coreSafetyFooter''',
  );

  static const AiPersona socraticTutor = AiPersona(
    id: 'socratic',
    name: 'Socratic Tutor',
    shortLabel: 'Tutor',
    description:
        'Patient teacher who breaks concepts down step-by-step and asks guiding questions.',
    icon: Icons.school_rounded,
    color: Color(0xFFF59E0B),
    recommendedTemperature: 0.4,
    systemPrompt: '''
You are Arivu Socratic Tutor, a supportive offline teacher helping the user deeply understand concepts.
Operating Rules:
1. Explain concepts clearly using intuitive analogies and bite-sized steps.
2. When helping with a problem, guide the user's reasoning and end with 1 short thought-provoking check-in question.
3. Encourage curiosity and verify understanding rather than dumping dense walls of text.
$_coreSafetyFooter''',
  );

  static const AiPersona creativeWriter = AiPersona(
    id: 'creative',
    name: 'Creative Writer',
    shortLabel: 'Creative',
    description:
        'Expressive storyteller for vivid prose, poetry, dialogue, brainstorming, and scripts.',
    icon: Icons.edit_note_rounded,
    color: Color(0xFFEC4899),
    recommendedTemperature: 0.75,
    systemPrompt: '''
You are Arivu Creative Writer, an imaginative offline writer and brainstorming partner.
Operating Rules:
1. Craft vivid, engaging prose, poetry, or dialogue with strong imagery and natural rhythm.
2. Match the genre, mood, and tone requested by the user.
3. Avoid generic clichés and deliver the creative piece directly without meta-commentary.
$_coreSafetyFooter''',
  );

  static AiPersona customPersona(String customInstructions) {
    final cleaned = customInstructions.trim();
    final instructions = cleaned.isEmpty
        ? LocalAiService.defaultChatSystemPrompt
        : '''
You are Arivu AI operating with the following user-defined custom persona instructions:
$cleaned

$_coreSafetyFooter''';

    return AiPersona(
      id: 'custom',
      name: 'Custom Persona',
      shortLabel: 'Custom',
      description: cleaned.isEmpty
          ? 'Define your own custom system instructions saved locally on this device.'
          : cleaned,
      icon: Icons.tune_rounded,
      color: const Color(0xFF64748B),
      systemPrompt: instructions,
    );
  }

  /// All built-in selectable personas (including Auto Router and Custom).
  static List<AiPersona> allPersonas({String customPrompt = ''}) => [
        autoRouter,
        defaultPersona,
        codeMentor,
        executiveAssistant,
        socraticTutor,
        creativeWriter,
        customPersona(customPrompt),
      ];

  /// Looks up a persona by ID, falling back to [defaultPersona].
  static AiPersona byId(String id, {String customPrompt = ''}) {
    switch (id) {
      case 'auto':
        return autoRouter;
      case 'code_mentor':
        return codeMentor;
      case 'executive':
        return executiveAssistant;
      case 'socratic':
        return socraticTutor;
      case 'creative':
        return creativeWriter;
      case 'custom':
        return customPersona(customPrompt);
      case 'default':
      default:
        return defaultPersona;
    }
  }
}

/// Fast (<1ms) offline persona router for Auto-Delegation mode.
class PersonaRouter {
  PersonaRouter._();

  static final RegExp _codeRegex = RegExp(
    r'\b(code|coding|bug|debug|error|exception|stacktrace|function|method|class|flutter|dart|python|java|javascript|typescript|react|sql|sqlite|regex|algorithm|refactor|api|json|git|compile|syntax|loop|async|await|widget|big[\s-]?o|complexity|c\+\+|rust|golang|html|css|kotlin|swift)\b',
    caseSensitive: false,
  );

  static final RegExp _executiveRegex = RegExp(
    r'\b(email|mail|memo|agenda|meeting|action\s+items|proposal|executive\s+summary|stakeholder|professional|decline|follow[\s-]?up|status\s+update|pitch|resume|cover\s+letter|linkedin|report\s+to\s+manager|formal\s+letter)\b',
    caseSensitive: false,
  );

  static final RegExp _creativeRegex = RegExp(
    r'\b(story|poem|poetry|haiku|fiction|novel|creative|dialogue|script|lyrics|metaphor|character|plot|fantasy|sci[\s-]?fi|fairy\s+tale|short\s+story|song\s+about)\b',
    caseSensitive: false,
  );

  static final RegExp _socraticRegex = RegExp(
    r'\b(teach\s+me|help\s+me\s+learn|quiz\s+me|study\s+for|explain\s+like|guide\s+me|practice\s+problem|homework|give\s+me\s+a\s+hint|tutor\s+me|step[\s-]by[\s-]step\s+lesson)\b',
    caseSensitive: false,
  );

  /// Resolves the active [AiPersona] for a given user [prompt].
  /// - In manual mode, returns [selectedPersona] directly.
  /// - In `auto` mode, inspects [prompt] in <1ms and routes to the best specialist.
  static AiPersona resolvePersonaForPrompt({
    required AiPersona selectedPersona,
    required String prompt,
    String customPrompt = '',
  }) {
    if (selectedPersona.id == 'custom') {
      return AiPersona.customPersona(customPrompt);
    }
    if (selectedPersona.id != 'auto') {
      return selectedPersona;
    }

    final text = prompt.trim();
    if (text.isEmpty) return AiPersona.defaultPersona;

    if (_codeRegex.hasMatch(text)) return AiPersona.codeMentor;
    if (_executiveRegex.hasMatch(text)) return AiPersona.executiveAssistant;
    if (_creativeRegex.hasMatch(text)) return AiPersona.creativeWriter;
    if (_socraticRegex.hasMatch(text)) return AiPersona.socraticTutor;

    return AiPersona.defaultPersona;
  }
}
