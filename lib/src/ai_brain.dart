import 'dart:convert';

import 'llm/llm_backend.dart';
import 'tools/jarvis_tool.dart';

/// Conversation memory + tool-calling loop on top of any [LlmBackend].
///
/// Tool calling uses a plain JSON convention in the prompt instead of a
/// model-specific format, so it works the same with every backend.
class AIBrain {
  final LlmBackend backend;
  final String systemInstruction;
  final Map<String, JarvisTool> tools;
  final int maxHistoryMessages;
  final int maxToolSteps;

  final List<ChatMessage> _history = [];

  AIBrain({
    required this.backend,
    required this.systemInstruction,
    required this.tools,
    this.maxHistoryMessages = 12,
    this.maxToolSteps = 3,
  });

  void clearHistory() => _history.clear();

  String _systemPrompt() {
    final b = StringBuffer(systemInstruction);
    if (tools.isNotEmpty) {
      b.writeln();
      b.writeln();
      b.writeln('You can use these tools:');
      for (final t in tools.values) {
        final params = t.parameters.isEmpty
            ? 'none'
            : t.parameters.entries.map((e) => '${e.key} (${e.value})').join(', ');
        b.writeln('- ${t.name}: ${t.description} Args: $params');
      }
      b.writeln(
          'If (and only if) a tool is needed, reply with ONLY one JSON object and nothing else, like: '
          '{"tool": "tool_name", "args": {"arg": "value"}}');
      b.writeln(
          'After you receive the tool result, answer the user briefly in their language. '
          'If no tool is needed, just answer normally.');
    }
    return b.toString();
  }

  List<ChatMessage> _messages() =>
      [ChatMessage(ChatRole.system, _systemPrompt()), ..._history];

  void _trim() {
    while (_history.length > maxHistoryMessages) {
      _history.removeAt(0);
    }
    // Chat templates expect the history to start with a user turn.
    while (_history.isNotEmpty && _history.first.role != ChatRole.user) {
      _history.removeAt(0);
    }
  }

  /// Returns Jarvis's reply. Throws [LlmException] if the backend fails.
  Future<String> getResponse(String prompt) async {
    _history.add(ChatMessage(ChatRole.user, prompt));
    try {
      for (var step = 0; step < maxToolSteps; step++) {
        final reply = (await backend.chat(_messages())).trim();
        final call = _parseToolCall(reply);
        if (call == null) {
          final text = reply.isEmpty ? 'Iske liye mere paas koi jawab nahi hai, sir.' : reply;
          _history.add(ChatMessage(ChatRole.assistant, text));
          _trim();
          return text;
        }

        _history.add(ChatMessage(ChatRole.assistant, reply));
        String result;
        try {
          result = await tools[call.name]!.execute(call.args);
        } catch (e) {
          result = 'Tool error: $e';
        }
        _history.add(ChatMessage(
            ChatRole.user, 'Tool result for ${call.name}: $result\nAb user ko chhota sa jawab do.'));
      }
      _trim();
      return 'Ye kaam poora nahi ho paya, sir.';
    } catch (_) {
      // Do not leave a dangling user turn in the history.
      if (_history.isNotEmpty && _history.last.role == ChatRole.user) {
        _history.removeLast();
      }
      rethrow;
    }
  }

  _ToolCall? _parseToolCall(String reply) {
    if (tools.isEmpty) return null;
    final s = reply.replaceAll(RegExp(r'```(?:json)?'), '').trim();
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(s.substring(start, end + 1));
      if (decoded is Map && decoded['tool'] is String) {
        final name = decoded['tool'] as String;
        if (!tools.containsKey(name)) return null;
        final args = decoded['args'];
        return _ToolCall(
            name, args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{});
      }
    } catch (_) {}
    return null;
  }

  Future<void> dispose() => backend.dispose();
}

class _ToolCall {
  final String name;
  final Map<String, dynamic> args;
  _ToolCall(this.name, this.args);
}
