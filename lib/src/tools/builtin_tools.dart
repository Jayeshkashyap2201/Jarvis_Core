import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'jarvis_tool.dart';

/// The tools that ship with Jarvis.
class BuiltinTools {
  static List<JarvisTool> create({required void Function(String label) onTimerDone}) => [
        const GetTimeTool(),
        const GetDateTool(),
        const OpenWebsiteTool(),
        const WebSearchTool(),
        SetTimerTool(onDone: onTimerDone),
      ];
}

class GetTimeTool extends JarvisTool {
  const GetTimeTool();

  @override
  String get name => 'get_time';

  @override
  String get description => 'Tells the current local time.';

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    return 'Abhi samay hai $h:$m $ampm, sir.';
  }
}

class GetDateTool extends JarvisTool {
  const GetDateTool();

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'
  ];

  @override
  String get name => 'get_date';

  @override
  String get description => "Tells today's date and the day of the week.";

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final n = DateTime.now();
    return 'Aaj ${_days[n.weekday - 1]} hai, ${n.day} ${_months[n.month - 1]} ${n.year}, sir.';
  }
}

class OpenWebsiteTool extends JarvisTool {
  const OpenWebsiteTool();

  /// Friendly names (also Hindi spellings) -> URL.
  static const Map<String, String> knownSites = {
    'youtube': 'https://www.youtube.com',
    'यूट्यूब': 'https://www.youtube.com',
    'google': 'https://www.google.com',
    'गूगल': 'https://www.google.com',
    'gmail': 'https://mail.google.com',
    'जीमेल': 'https://mail.google.com',
    'maps': 'https://maps.google.com',
    'whatsapp': 'https://web.whatsapp.com',
    'व्हाट्सएप': 'https://web.whatsapp.com',
    'instagram': 'https://www.instagram.com',
    'इंस्टाग्राम': 'https://www.instagram.com',
    'facebook': 'https://www.facebook.com',
    'twitter': 'https://x.com',
    'github': 'https://github.com',
    'chatgpt': 'https://chatgpt.com',
    'wikipedia': 'https://www.wikipedia.org',
  };

  @override
  String get name => 'open_website';

  @override
  String get description =>
      'Opens a website or web app in the browser (e.g. youtube, gmail, maps).';

  @override
  Map<String, String> get parameters =>
      const {'site': 'website name like "youtube" or a full URL'};

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final site = '${args['site'] ?? ''}'.trim().toLowerCase();
    if (site.isEmpty) return 'Kaunsi website kholni hai, sir?';

    String url;
    if (site.startsWith('http://') || site.startsWith('https://')) {
      url = site;
    } else if (knownSites.containsKey(site)) {
      url = knownSites[site]!;
    } else if (site.contains('.') && !site.contains(' ')) {
      url = 'https://$site';
    } else {
      url = 'https://www.google.com/search?q=${Uri.encodeQueryComponent(site)}';
    }
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return ok ? '$site khol diya, sir.' : '$site nahi khul paya, sir.';
    } catch (_) {
      return '$site nahi khul paya, sir.';
    }
  }
}

class WebSearchTool extends JarvisTool {
  const WebSearchTool();

  @override
  String get name => 'web_search';

  @override
  String get description =>
      'Opens a Google search for a query in the browser. Use when the user wants to search the web.';

  @override
  Map<String, String> get parameters =>
      const {'query': 'the text to search for'};

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final q = '${args['query'] ?? ''}'.trim();
    if (q.isEmpty) return 'Kya search karna hai, sir?';
    final url = 'https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}';
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return ok ? '$q search kar raha hoon, sir.' : 'Search nahi khul payi, sir.';
    } catch (_) {
      return 'Search nahi khul payi, sir.';
    }
  }
}

/// In-app countdown timer (runs while the app is alive; it is not a system alarm).
class SetTimerTool extends JarvisTool {
  final void Function(String label) onDone;
  final List<Timer> _timers = [];

  SetTimerTool({required this.onDone});

  @override
  String get name => 'set_timer';

  @override
  String get description =>
      'Sets a countdown timer. Use when the user asks for a timer or a reminder after some time.';

  @override
  Map<String, String> get parameters => const {
        'seconds': 'number, total duration in seconds',
        'label': 'optional text, what the timer is for',
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final seconds = num.tryParse('${args['seconds']}')?.round();
    if (seconds == null || seconds <= 0) {
      return 'Timer ka time samajh nahi aaya, sir.';
    }
    final label = '${args['label'] ?? ''}'.trim();
    _timers.add(Timer(Duration(seconds: seconds), () => onDone(label)));
    return 'Theek hai sir, ${_pretty(seconds)} ka timer set ho gaya.';
  }

  String _pretty(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final parts = <String>[
      if (h > 0) '$h ghanta',
      if (m > 0) '$m minute',
      if (sec > 0) '$sec second',
    ];
    return parts.join(' ');
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }
}
