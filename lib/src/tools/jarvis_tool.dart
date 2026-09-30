/// A capability Jarvis can use (open a site, set a timer, control a device...).
///
/// The LLM sees [name], [description] and [parameters] and may ask to run the
/// tool; the fast command router can also call tools directly.
///
/// Whatever [execute] returns is either spoken as-is (fast path) or fed back
/// to the model so it can phrase the final answer.
abstract class JarvisTool {
  const JarvisTool();

  /// Unique snake_case name, e.g. `set_timer`.
  String get name;

  /// One clear English sentence: what it does and when to use it.
  String get description;

  /// argument name -> short description (type + meaning).
  Map<String, String> get parameters => const {};

  Future<String> execute(Map<String, dynamic> args);

  /// Called when Jarvis is disposed. Cancel timers / streams here.
  void dispose() {}
}

/// Quick way to add a tool without writing a class:
///
/// ```dart
/// FunctionTool(
///   name: 'flashlight',
///   description: 'Turns the flashlight on or off.',
///   parameters: {'state': '"on" or "off"'},
///   run: (args) async => 'Flashlight ${args['state']} kar di, sir.',
/// )
/// ```
class FunctionTool extends JarvisTool {
  @override
  final String name;
  @override
  final String description;
  @override
  final Map<String, String> parameters;
  final Future<String> Function(Map<String, dynamic> args) run;

  const FunctionTool({
    required this.name,
    required this.description,
    this.parameters = const {},
    required this.run,
  });

  @override
  Future<String> execute(Map<String, dynamic> args) => run(args);
}
