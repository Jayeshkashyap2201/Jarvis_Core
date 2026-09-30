enum ChatRole { system, user, assistant }

class ChatMessage {
  final ChatRole role;
  final String content;
  const ChatMessage(this.role, this.content);
}

/// Thrown when a backend cannot be reached / loaded / queried.
/// [message] is written to be shown to the user.
class LlmException implements Exception {
  final String message;
  const LlmException(this.message);

  @override
  String toString() => 'LlmException: $message';
}

/// A "brain" that turns a chat history into a reply.
/// Implement this to plug in any other model or service.
abstract class LlmBackend {
  String get name;

  /// Connects / loads the model. Throws [LlmException] on failure.
  Future<void> initialize();

  /// Returns the full assistant reply for [messages].
  Future<String> chat(List<ChatMessage> messages);

  Future<void> dispose();
}

/// Progress of an on-device model download.
class ModelDownloadProgress {
  final String message;

  /// 0.0 - 1.0, or null if unknown.
  final double? progress;
  final bool isComplete;

  /// Set once the download is complete.
  final String? modelPath;

  const ModelDownloadProgress({
    required this.message,
    this.progress,
    this.isComplete = false,
    this.modelPath,
  });
}
