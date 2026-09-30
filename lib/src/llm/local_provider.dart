import 'llm_backend.dart';

/// Plug-in point for on-device models. Implemented by the optional
/// `jarvis_local` package, so `jarvis_core` itself has no native (llama.cpp)
/// dependency and builds everywhere.
abstract class LocalModelProvider {
  /// Path of an already downloaded model, or null.
  Future<String?> findModel();

  Future<LlmBackend> createBackend({
    required String modelPath,
    required int contextSize,
    required int gpuLayers,
    required double temperature,
    required int maxTokens,
  });

  Stream<ModelDownloadProgress> download({String? repoId});
}
