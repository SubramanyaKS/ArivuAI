import 'pocket_tool.dart';

/// Offline crisis response and self-harm interceptor for Responsible AI.
///
/// Smaller on-device quantized models (0.5B-1.5B) have weaker safety fine-tuning
/// than massive cloud models. This deterministic offline tool catches crisis and
/// self-harm inquiries instantly with zero latency, bypassing the LLM completely
/// to provide verified, compassionate support resources.
class SafetyTool implements PocketTool {
  const SafetyTool();

  @override
  String get name => 'safety_crisis_support';

  @override
  Map<String, dynamic> get definition => {
        "name": name,
        "description":
            "Intercepts self-harm, suicide, and psychological crisis queries to provide immediate support lifelines.",
        "parameters": {
          "type": "object",
          "properties": {},
          "required": [],
        },
      };

  static final List<RegExp> _crisisPatterns = [
    RegExp(r'\b(suicid(e|al))\b', caseSensitive: false),
    RegExp(r'\b(kill(ing)?\s+myself)\b', caseSensitive: false),
    RegExp(r'\b(end\s+my\s+life)\b', caseSensitive: false),
    RegExp(r'\b(want\s+to\s+die)\b', caseSensitive: false),
    RegExp(r'\b(hang(ing)?\s+myself)\b', caseSensitive: false),
    RegExp(r'\b(self[\s-]harm(ing)?)\b', caseSensitive: false),
    RegExp(r'\b(cut(ting)?\s+myself)\b', caseSensitive: false),
    RegExp(r'\b(overdos(e|ing))\b', caseSensitive: false),
    RegExp(r'\b(don\?t\s+want\s+to\s+live\s+anymore)\b', caseSensitive: false),
    RegExp(r'\b(life\s+is\s+not\s+worth\s+living)\b', caseSensitive: false),
    RegExp(r'\b(how\s+to\s+(die|commit\s+suicide))\b', caseSensitive: false),
  ];

  /// Checks if the user's input expresses acute crisis or self-harm intent.
  static bool isCrisisQuery(String input) {
    final text = input.trim().toLowerCase();
    if (text.isEmpty) return false;

    for (final pattern in _crisisPatterns) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  /// Generates a warm, supportive response with verified international crisis lifelines.
  static String getCrisisResponse() {
    return '💙 **You are not alone, and help is available right now.**\n\n'
        'If you are going through a difficult time, please reach out to someone who can support you. '
        'These free, confidential helplines are available 24/7 with caring professionals ready to listen:\n\n'
        '• **India**: Call **14416** or **1800-891-4416** (Tele-MANAS free 24/7 mental health helpline), or **+91 9152987821** (Vandrevala Foundation).\n'
        '• **United States & Canada**: Call or text **988** (Suicide & Crisis Lifeline).\n'
        '• **United Kingdom**: Call **111** (NHS Mental Health Services) or **116 123** (Samaritans).\n'
        '• **Australia**: Call **13 11 14** (Lifeline).\n'
        '• **International / Worldwide**: Visit **[findahelpline.com](https://findahelpline.com)** or **[befrienders.org](https://www.befrienders.org)** to find free support in your country.\n'
        '• **Emergency**: Contact your local emergency services (**112** in EU/India, **911** in US) immediately.\n\n'
        'Please stay safe and talk to a trusted friend, family member, or professional counselor.';
  }

  /// Voice-friendly spoken version without markdown or URLs.
  static String getSpokenCrisisResponse() {
    return 'You are not alone, and help is available. If you are in distress, please call your local crisis lifeline or emergency services right now. In India, call 14416 for Tele-MANAS. In the US and Canada, call 988. In the UK, call 111. Please stay safe and reach out to someone who can support you.';
  }

  @override
  Future<String?> tryExecute(String prompt) async {
    if (isCrisisQuery(prompt)) {
      return getCrisisResponse();
    }
    return null;
  }
}
