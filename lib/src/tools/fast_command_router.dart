import 'builtin_tools.dart';
import 'jarvis_tool.dart';

/// Rule-based shortcut for simple commands (English / Hinglish / Hindi).
/// Instant, needs no LLM, works even if the brain is offline.
/// Returns null when the sentence is not a simple command -> LLM handles it.
class FastCommandRouter {
  final Map<String, JarvisTool> tools;
  FastCommandRouter(this.tools);

  static bool _hasAny(String t, List<String> needles) =>
      needles.any((n) => t.contains(n));

  Future<String?> tryHandle(String input) async {
    final t = input.toLowerCase().trim();
    if (t.isEmpty) return null;
    // Only short utterances are treated as commands; long sentences go to the LLM.
    if (t.split(RegExp(r'\s+')).length > 9) return null;

    // Timer:  "5 minute ka timer laga do"
    final timer = tools['set_timer'];
    if (timer != null &&
        _hasAny(t, ['timer', 'टाइमर', 'alarm', 'अलार्म', 'remind', 'yaad dila'])) {
      final m = RegExp(
              r'(\d+)\s*(seconds?|secs?|सेकंड|minutes?|mins?|मिनट|hours?|hrs?|ghante|ghanta|घंटे|घंटा)')
          .firstMatch(t);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        final u = m.group(2)!;
        var mult = 1;
        if (u.startsWith('min') || u.startsWith('मिन')) {
          mult = 60;
        } else if (u.startsWith('h') || u.startsWith('g') || u.startsWith('घं')) {
          mult = 3600;
        }
        return timer.execute({'seconds': n * mult, 'label': ''});
      }
    }

    // Time
    final timeTool = tools['get_time'];
    if (timeTool != null &&
        !t.contains('timer') &&
        _hasAny(t, [
          'what time', 'current time', 'time kya', 'kya time', 'kitne baje',
          'kitna baja', 'kitne bje', 'samay kya', 'kya samay', 'abhi samay',
          'waqt kya', 'कितने बजे', 'समय क्या', 'टाइम क्या', 'क्या टाइम',
        ])) {
      return timeTool.execute({});
    }

    // Date / day
    final dateTool = tools['get_date'];
    if (dateTool != null &&
        _hasAny(t, [
          'date kya', 'aaj ki date', 'aaj ki tarikh', 'tarikh kya', 'what date',
          "today's date", 'what day', 'aaj kaun sa din', 'aaj kya din',
          'kaun sa din', 'तारीख', 'आज कौन सा दिन',
        ])) {
      return dateTool.execute({});
    }

    // Open website:  "youtube kholo"
    final open = tools['open_website'];
    if (open != null &&
        _hasAny(t, ['open', 'khol', 'chalao', 'launch', 'खोल'])) {
      for (final site in OpenWebsiteTool.knownSites.keys) {
        if (t.contains(site)) return open.execute({'site': site});
      }
    }

    // Web search:  "search karo flutter tutorial" / "flutter tutorial search karo"
    final search = tools['web_search'];
    if (search != null) {
      final a = RegExp(r'^(?:search for|search karo|search|google pe search karo|google)\s+(.+)$')
          .firstMatch(t);
      if (a != null) return search.execute({'query': a.group(1)!});
      final b = RegExp(r'^(.+?)\s+(?:search karo|search kar do|search kar|google karo|google kar|dhundo|dhoondo|सर्च करो|खोजो)$')
          .firstMatch(t);
      if (b != null) return search.execute({'query': b.group(1)!});
    }

    return null;
  }
}
