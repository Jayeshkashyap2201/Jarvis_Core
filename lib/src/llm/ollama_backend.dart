import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_backend.dart';

/// Talks to an Ollama server (https://ollama.com). Works on all platforms,
/// including Web (set OLLAMA_ORIGINS on the server for CORS).
class OllamaBackend implements LlmBackend {
  final String baseUrl;
  final String model;
  final double temperature;
  final int maxTokens;
  final Duration timeout;
  final http.Client _client = http.Client();

  OllamaBackend({
    required this.baseUrl,
    required this.model,
    this.temperature = 0.6,
    this.maxTokens = 300,
    this.timeout = const Duration(seconds: 120),
  });

  @override
  String get name => 'Server: $model';

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base$path');
  }

  @override
  Future<void> initialize() async {
    try {
      final res = await _client
          .get(_uri('/api/tags'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw LlmException('Server ne ${res.statusCode} diya ($baseUrl).');
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final models = (data['models'] as List? ?? const [])
          .map((m) => (m as Map)['name'].toString())
          .toList();
      final wanted = model.contains(':') ? model : '$model:latest';
      if (!models.contains(wanted) && !models.contains(model)) {
        throw LlmException(
            "Model '$model' server par nahi mila. Terminal me chalao: ollama pull $model");
      }
    } on LlmException {
      rethrow;
    } on TimeoutException {
      throw LlmException(
          'Server ($baseUrl) se jawab nahi aaya. Kya Ollama chal raha hai?');
    } catch (e) {
      throw LlmException('Server ($baseUrl) se connect nahi ho paya: $e');
    }
  }

  @override
  Future<String> chat(List<ChatMessage> messages) async {
    try {
      final res = await _client
          .post(
            _uri('/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'stream': false,
              'keep_alive': '30m',
              'messages': [
                for (final m in messages)
                  {'role': m.role.name, 'content': m.content},
              ],
              'options': {
                'temperature': temperature,
                'num_predict': maxTokens,
              },
            }),
          )
          .timeout(timeout);
      if (res.statusCode != 200) {
        throw LlmException(
            'Server error ${res.statusCode}: ${utf8.decode(res.bodyBytes)}');
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return ((data['message'] as Map?)?['content'] ?? '').toString();
    } on LlmException {
      rethrow;
    } on TimeoutException {
      throw LlmException('Server ne time par jawab nahi diya.');
    } catch (e) {
      throw LlmException('Server se baat karne me error: $e');
    }
  }

  @override
  Future<void> dispose() async => _client.close();
}
