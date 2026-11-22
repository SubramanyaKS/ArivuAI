import '../tools/remainder_tools.dart';
import 'nlp_normalizer.dart';
import 'pocket_tool.dart';

enum ReminderAction {
  create,
  list,
  cancel,
  cancelAll,
  none,
}

class ReminderIntentResult {
  final ReminderAction action;
  final String title;
  final int delayMinutes;
  final int? targetIndex;

  const ReminderIntentResult({
    required this.action,
    this.title = '',
    this.delayMinutes = 0,
    this.targetIndex,
  });

  bool get isReminder => action != ReminderAction.none;
}

class ReminderTool implements PocketTool {
  const ReminderTool();

  @override
  String get name => 'create_reminder';

  @override
  Map<String, dynamic> get definition => {
        "name": name,
        "description": "Create, list, or cancel personal reminders and alerts.",
        "parameters": {
          "type": "object",
          "properties": {
            "action": {
              "type": "string",
              "enum": ["create", "list", "cancel", "cancel_all"],
              "description": "The reminder action to perform",
            },
            "title": {
              "type": "string",
              "description": "The title or action of the reminder",
            },
            "delay_minutes": {
              "type": "integer",
              "description": "Delay before firing the reminder in minutes",
            },
            "index": {
              "type": "integer",
              "description": "The number of the reminder to cancel (1-based index)",
            }
          },
          "required": ["title", "delay_minutes"],
        },
      };

  /// Detects natural language reminder requests:
  /// - Create: "remind me to call John in 5 minutes", "remind me in 10 minutes to drink water"
  /// - List: "give me the list of reminders", "show my reminders", "what are my reminders"
  /// - Cancel: "cancel reminder to drink water", "delete reminder 1", "cancel all reminders"
  static ReminderIntentResult parse(String input) {
    final text = NlpNormalizer.normalize(input);
    if (text.isEmpty) return const ReminderIntentResult(action: ReminderAction.none);

    final lower = text.toLowerCase().replaceAll(RegExp(r'[?!.]+$'), '').trim();
    if (!lower.contains('remind')) {
      return const ReminderIntentResult(action: ReminderAction.none);
    }

    // 1. Check Cancel All: "cancel all reminders", "clear all reminders", "delete all reminders", "cancel reminders"
    final cancelAllPattern = RegExp(
      r'\b(?:cancel|delete|clear|remove)\s+(?:all\s+)?(?:the\s+)?(?:my\s+)?reminders?\b',
      caseSensitive: false,
    );
    if (cancelAllPattern.hasMatch(lower) &&
        (lower.contains('all') ||
            lower == 'cancel reminders' ||
            lower == 'clear reminders' ||
            lower == 'delete reminders')) {
      return const ReminderIntentResult(action: ReminderAction.cancelAll);
    }

    // 2. Check Cancel Specific: "cancel reminder 1", "delete reminder to call mom"
    final cancelIndexPattern = RegExp(
      r'\b(?:cancel|delete|clear|remove)\s+(?:the\s+)?reminder(?:\s+(?:number|#))?\s+(\d+)\b',
      caseSensitive: false,
    );
    final indexMatch = cancelIndexPattern.firstMatch(lower);
    if (indexMatch != null) {
      final idx = int.tryParse(indexMatch.group(1) ?? '');
      if (idx != null && idx > 0) {
        return ReminderIntentResult(
          action: ReminderAction.cancel,
          targetIndex: idx,
        );
      }
    }

    final cancelTitlePattern = RegExp(
      r'\b(?:cancel|delete|clear|remove)\s+(?:the\s+)?reminder(?:\s+(?:to|for|about))?\s+(.+)',
      caseSensitive: false,
    );
    final titleMatch = cancelTitlePattern.firstMatch(lower);
    if (titleMatch != null) {
      String target = titleMatch.group(1)?.trim() ?? '';
      target = target.replaceFirst(RegExp(r'^(to|for|about)\s+', caseSensitive: false), '').trim();
      if (target.isNotEmpty && target != 'all') {
        return ReminderIntentResult(
          action: ReminderAction.cancel,
          title: target,
        );
      }
    }

    // 3. Check List Reminders: "give me the list of reminders", "show my reminders", "what are my reminders"
    final listPattern = RegExp(
      r'\b(?:show|list|get|view|give\s+me|check|read|see)\s+(?:all\s+)?(?:the\s+)?(?:my\s+)?(?:list\s+of\s+)?(?:active\s+)?(?:upcoming\s+)?reminders?\b|\blist\s+of\s+reminders?\b|\bwhat\s+(?:are|were)\s+(?:all\s+)?(?:my\s+)?reminders?\b|\bdo\s+i\s+have\s+(?:any\s+)?reminders?\b|\bany\s+reminders?\b',
      caseSensitive: false,
    );
    if (listPattern.hasMatch(lower) || lower == 'reminders' || lower == 'my reminders') {
      return const ReminderIntentResult(action: ReminderAction.list);
    }

    // 4. Check Creation (Pattern B: "remind me in [X] minutes/hours to [action]")
    final regexB = RegExp(
      r'remind\s+(?:me\s+)?(?:in|after)\s+(\d+)\s*(minute|min|hour|hr)s?\s+(?:to\s+)?(.+)',
      caseSensitive: false,
    );

    // Pattern A: "remind me to [action] in [X] minutes/hours"
    final regexA = RegExp(
      r'remind\s+(?:me\s+)?(?:to\s+)?(.+?)\s+(?:in|after)\s+(\d+)\s*(minute|min|hour|hr)s?',
      caseSensitive: false,
    );

    int delayMinutes = 0;
    String task = '';

    final matchB = regexB.firstMatch(text);
    if (matchB != null) {
      final num = int.tryParse(matchB.group(1) ?? '0') ?? 0;
      final unit = matchB.group(2)?.toLowerCase() ?? 'minute';
      delayMinutes = unit.startsWith('h') ? num * 60 : num;
      task = matchB.group(3)?.trim() ?? '';
    } else {
      final matchA = regexA.firstMatch(text);
      if (matchA != null) {
        task = matchA.group(1)?.trim() ?? '';
        if (task.toLowerCase() == 'me') {
          task = '';
        }
        final num = int.tryParse(matchA.group(2) ?? '0') ?? 0;
        final unit = matchA.group(3)?.toLowerCase() ?? 'minute';
        delayMinutes = unit.startsWith('h') ? num * 60 : num;
      }
    }

    if (delayMinutes > 0 && task.isNotEmpty) {
      task = task.replaceFirst(RegExp(r'^(to\s+)', caseSensitive: false), '').trim();
      return ReminderIntentResult(
        action: ReminderAction.create,
        title: task,
        delayMinutes: delayMinutes,
      );
    }

    return const ReminderIntentResult(action: ReminderAction.none);
  }

  /// Lists upcoming active reminders in a clean formatted Markdown string.
  static Future<String> listReminders() async {
    final upcoming = await NotificationService.instance.getUpcomingReminders();
    if (upcoming.isEmpty) {
      return "You don't have any upcoming reminders.";
    }

    final buffer = StringBuffer('Here are your upcoming reminders:\n');
    for (int i = 0; i < upcoming.length; i++) {
      final r = upcoming[i];
      final title = r['title'] as String? ?? 'Reminder';
      final scheduledAt = r['scheduled_at'] as int? ?? 0;
      final timeStr = _formatRelativeTime(scheduledAt);
      buffer.writeln('• ${i + 1}. **$title** — $timeStr');
    }
    return buffer.toString().trim();
  }

  /// Cancels all pending reminders.
  static Future<String> cancelAll() async {
    final upcoming = await NotificationService.instance.getUpcomingReminders();
    if (upcoming.isEmpty) {
      return "You have no active reminders to cancel.";
    }
    await NotificationService.instance.cancelAllReminders();
    return "All upcoming reminders have been cleared.";
  }

  /// Cancels a specific reminder by title or list index.
  static Future<String> cancelSpecific({String title = '', int? targetIndex}) async {
    final upcoming = await NotificationService.instance.getUpcomingReminders();
    if (upcoming.isEmpty) {
      return "You have no active reminders to cancel.";
    }

    Map<String, dynamic>? toCancel;

    if (targetIndex != null && targetIndex > 0 && targetIndex <= upcoming.length) {
      toCancel = upcoming[targetIndex - 1];
    } else if (title.trim().isNotEmpty) {
      final cleanTarget = title.trim().toLowerCase();
      for (final r in upcoming) {
        final t = (r['title'] as String? ?? '').toLowerCase();
        if (t == cleanTarget || t.contains(cleanTarget) || cleanTarget.contains(t)) {
          toCancel = r;
          break;
        }
      }
    }

    if (toCancel != null) {
      final id = toCancel['id'] as int;
      final itemTitle = toCancel['title'] as String? ?? 'Reminder';
      await NotificationService.instance.cancelReminder(id);
      return "Cancelled reminder: '$itemTitle'.";
    }

    return title.isNotEmpty
        ? "Could not find an active reminder matching '$title'."
        : "Please specify which reminder to cancel.";
  }

  static String _formatRelativeTime(int scheduledAtMillis) {
    final now = DateTime.now();
    final target = DateTime.fromMillisecondsSinceEpoch(scheduledAtMillis);
    final diff = target.difference(now);

    final hour12 = target.hour > 12
        ? target.hour - 12
        : (target.hour == 0 ? 12 : target.hour);
    final minutePad = target.minute.toString().padLeft(2, '0');
    final meridian = target.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:$minutePad $meridian';

    if (diff.inMinutes < 60 && diff.inMinutes > 0) {
      return 'in ${diff.inMinutes} ${diff.inMinutes == 1 ? "minute" : "minutes"} (at $timeStr)';
    } else if (diff.inHours < 24 && target.day == now.day) {
      return 'Today at $timeStr';
    } else if (target.day == now.day + 1) {
      return 'Tomorrow at $timeStr';
    } else {
      return '${target.month}/${target.day} at $timeStr';
    }
  }

  /// Executes the reminder intent and returns a natural conversational confirmation string.
  static Future<String?> tryExecuteReminder(String prompt) async {
    final result = parse(prompt);
    if (!result.isReminder) return null;

    switch (result.action) {
      case ReminderAction.list:
        return await listReminders();

      case ReminderAction.cancelAll:
        return await cancelAll();

      case ReminderAction.cancel:
        return await cancelSpecific(
          title: result.title,
          targetIndex: result.targetIndex,
        );

      case ReminderAction.create:
        await NotificationService.instance.createReminder(
          title: result.title,
          delayMinutes: result.delayMinutes,
        );
        final durationStr = result.delayMinutes >= 60
            ? '${result.delayMinutes ~/ 60} ${result.delayMinutes ~/ 60 == 1 ? "hour" : "hours"}'
            : '${result.delayMinutes} ${result.delayMinutes == 1 ? "minute" : "minutes"}';
        return "Got it! I've set a reminder to ${result.title} in $durationStr.";

      case ReminderAction.none:
        return null;
    }
  }

  @override
  Future<String?> tryExecute(String prompt) => tryExecuteReminder(prompt);

  @override
  Future<String?> executeWithArgs(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim();

    if (action == 'list' || action == 'show_reminders') {
      return await listReminders();
    } else if (action == 'cancel_all' || action == 'clear_all') {
      return await cancelAll();
    } else if (action == 'cancel' || action == 'delete') {
      final title = args['title']?.toString() ?? '';
      final idx = int.tryParse(args['index']?.toString() ?? '');
      return await cancelSpecific(title: title, targetIndex: idx);
    }

    final title = args['title']?.toString().trim();
    if (title == null || title.isEmpty) return null;

    final delay = int.tryParse(args['delay_minutes']?.toString() ?? '') ?? 0;
    if (delay <= 0) return null;

    await NotificationService.instance.createReminder(
      title: title,
      delayMinutes: delay,
    );

    final durationStr = delay >= 60
        ? '${delay ~/ 60} ${delay ~/ 60 == 1 ? "hour" : "hours"}'
        : '$delay ${delay == 1 ? "minute" : "minutes"}';

    return "Got it! I've set a reminder to $title in $durationStr.";
  }
}

/// Backwards compatibility typedef
typedef ReminderParser = ReminderTool;
