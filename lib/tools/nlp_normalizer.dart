/// Natural Language Pre-Processing Normalizer for Arivu AI.
///
/// Converts colloquial speech-to-text phrases, written number words,
/// and relative time expressions into standardized digits and formats.
/// This allows the Tier 1 deterministic Fast-Path to match natural conversational
/// inputs in < 1ms without requiring heavy LLM inference.
class NlpNormalizer {
  NlpNormalizer._();

  static const List<MapEntry<String, String>> _compoundWordNumbers = [
    MapEntry('twenty-five', '25'),
    MapEntry('twenty five', '25'),
    MapEntry('thirty-five', '35'),
    MapEntry('thirty five', '35'),
    MapEntry('forty-five', '45'),
    MapEntry('forty five', '45'),
    MapEntry('fourty-five', '45'),
    MapEntry('fourty five', '45'),
    MapEntry('fifty-five', '55'),
    MapEntry('fifty five', '55'),
  ];

  static const Map<String, String> _singleWordNumbers = {
    'zero': '0',
    'one': '1',
    'two': '2',
    'three': '3',
    'four': '4',
    'five': '5',
    'six': '6',
    'seven': '7',
    'eight': '8',
    'nine': '9',
    'ten': '10',
    'eleven': '11',
    'twelve': '12',
    'thirteen': '13',
    'fourteen': '14',
    'fifteen': '15',
    'sixteen': '16',
    'seventeen': '17',
    'eighteen': '18',
    'nineteen': '19',
    'twenty': '20',
    'thirty': '30',
    'forty': '40',
    'fourty': '40',
    'fifty': '50',
    'sixty': '60',
  };

  /// Normalizes a conversational prompt for deterministic tool parsers.
  static String normalize(String input) {
    if (input.trim().isEmpty) return '';

    String text = input.trim();

    // 1. Normalize punctuation variations from speech dictation
    text = text
        .replaceAll(RegExp(r'\bp\.?\s*m\.?(?:\s|$|[.!?,;])', caseSensitive: false), ' pm ')
        .replaceAll(RegExp(r'\ba\.?\s*m\.?(?:\s|$|[.!?,;])', caseSensitive: false), ' am ')
        .replaceAll(RegExp(r"\s*o\x27?clock\b", caseSensitive: false), ':00');

    // 2. Normalize durations and colloquial fractions
    text = text
        .replaceAll(RegExp(r'\b(?:an?\s+)?hour\s+and\s+(?:a\s+)?half\b', caseSensitive: false), '90 minutes')
        .replaceAll(RegExp(r'\bone\s+and\s+(?:a\s+)?half\s+hours?\b', caseSensitive: false), '90 minutes')
        .replaceAll(RegExp(r'\bhalf\s+(?:an?\s+)?hour\b', caseSensitive: false), '30 minutes')
        .replaceAll(RegExp(r'\bquarter\s+(?:of\s+)?(?:an?\s+)?hour\b', caseSensitive: false), '15 minutes')
        .replaceAll(RegExp(r'\ban?\s+hour\b', caseSensitive: false), '1 hour')
        .replaceAll(RegExp(r'\ban?\s+hr\b', caseSensitive: false), '1 hr')
        .replaceAll(RegExp(r'\ba\s+min(?:ute)?\b', caseSensitive: false), '1 minute')
        .replaceAll(RegExp(r'\ba\s+sec(?:ond)?\b', caseSensitive: false), '1 second');

    // 3. Convert compound numbers first ("twenty-five" -> "25")
    for (final entry in _compoundWordNumbers) {
      final pattern = RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false);
      text = text.replaceAll(pattern, entry.value);
    }

    // 4. Convert single word numbers, ensuring not part of a hyphenated word
    for (final entry in _singleWordNumbers.entries) {
      final pattern = RegExp('\\b${RegExp.escape(entry.key)}(?!-)\\b', caseSensitive: false);
      text = text.replaceAll(pattern, entry.value);
    }

    // 5. Normalize relative clock times (e.g. "half past six", "quarter to seven")
    // "half past [hour]" -> "[hour]:30"
    text = text.replaceAllMapped(
      RegExp(r'\bhalf\s+past\s+(\d{1,2})\b', caseSensitive: false),
      (m) => '${m.group(1)}:30',
    );

    // "quarter past [hour]" -> "[hour]:15"
    text = text.replaceAllMapped(
      RegExp(r'\bquarter\s+past\s+(\d{1,2})\b', caseSensitive: false),
      (m) => '${m.group(1)}:15',
    );

    // "quarter to [hour]" -> "[hour-1]:45"
    text = text.replaceAllMapped(
      RegExp(r'\bquarter\s+to\s+(\d{1,2})\b', caseSensitive: false),
      (m) {
        final targetHour = int.tryParse(m.group(1) ?? '') ?? 0;
        final hour = targetHour <= 1 ? 12 : targetHour - 1;
        return '$hour:45';
      },
    );

    // "twenty past [hour]" -> "[hour]:20"
    text = text.replaceAllMapped(
      RegExp(r'\b20\s+past\s+(\d{1,2})\b', caseSensitive: false),
      (m) => '${m.group(1)}:20',
    );

    // "twenty to [hour]" -> "[hour-1]:40"
    text = text.replaceAllMapped(
      RegExp(r'\b20\s+to\s+(\d{1,2})\b', caseSensitive: false),
      (m) {
        final targetHour = int.tryParse(m.group(1) ?? '') ?? 0;
        final hour = targetHour <= 1 ? 12 : targetHour - 1;
        return '$hour:40';
      },
    );

    // "ten past [hour]" -> "[hour]:10"
    text = text.replaceAllMapped(
      RegExp(r'\b10\s+past\s+(\d{1,2})\b', caseSensitive: false),
      (m) => '${m.group(1)}:10',
    );

    // "ten to [hour]" -> "[hour-1]:50"
    text = text.replaceAllMapped(
      RegExp(r'\b10\s+to\s+(\d{1,2})\b', caseSensitive: false),
      (m) {
        final targetHour = int.tryParse(m.group(1) ?? '') ?? 0;
        final hour = targetHour <= 1 ? 12 : targetHour - 1;
        return '$hour:50';
      },
    );

    // Clean up multiple spaces
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }
}
