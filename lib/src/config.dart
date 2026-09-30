/// Which "brain" Jarvis uses to think.
enum BrainMode {
  /// Talks to a self-hosted server (Ollama) over HTTP. Works on every
  /// platform, including Web.
  server,

  /// Runs a GGUF model directly on the device via llama.cpp.
  /// Android, iOS, macOS, Windows only (not Web).
  onDevice,
}

/// Configuration holder for [Jarvis].
class JarvisConfig {
  static const String defaultSystemInstruction =
      'Tum Jarvis ho, ek smart aur friendly AI assistant. '
      'Agar user Hindi ya Hinglish me bole to Roman script me Hinglish me jawab do, '
      'agar English me bole to English me jawab do. '
      'Jawab chhote rakho (1 se 3 sentences), jaise tum bol kar bata rahe ho. '
      'Markdown, emoji, bullet list ya special symbols kabhi use mat karo. '
      'Kabhi kabhi user ko "sir" keh sakte ho.';

  /// Server (Ollama) or on-device model.
  final BrainMode brainMode;

  /// Ollama base URL. Android emulator: http://10.0.2.2:11434,
  /// real phone: http://<PC-LAN-IP>:11434.
  final String serverUrl;

  /// Ollama model tag, e.g. `qwen2.5:3b`.
  final String serverModel;

  /// Absolute path of a local GGUF file (on-device mode). If null, Jarvis
  /// looks for a previously downloaded model automatically.
  final String? localModelPath;

  /// Context window for on-device inference.
  final int localContextSize;

  /// Layers offloaded to GPU on-device (0 = CPU only, 99 = all).
  final int localGpuLayers;

  /// BCP-47 locale for speech recognition and synthesis.
  /// `en-IN` handles Hinglish reasonably; use `hi-IN` for pure Hindi.
  final String languageCode;

  /// Words that wake Jarvis in hands-free mode (lowercase).
  final List<String> wakeWords;

  /// Personality / behaviour prompt.
  final String systemInstruction;

  final double temperature;
  final int maxReplyTokens;

  /// How many user+assistant turns are remembered.
  final int maxHistoryTurns;

  /// Handle simple commands (time, date, timer, open site, search) with
  /// rules first, without waking the LLM. Instant and works offline.
  final bool enableFastCommands;

  const JarvisConfig({
    this.brainMode = BrainMode.server,
    this.serverUrl = 'http://localhost:11434',
    this.serverModel = 'qwen2.5:3b',
    this.localModelPath,
    this.localContextSize = 4096,
    this.localGpuLayers = 0,
    this.languageCode = 'en-IN',
    this.wakeWords = const [
      'jarvis',
      'jarvish',
      'jaarvis',
      'जार्विस',
      'जारविस',
      'जरवीस',
    ],
    this.systemInstruction = JarvisConfig.defaultSystemInstruction,
    this.temperature = 0.6,
    this.maxReplyTokens = 300,
    this.maxHistoryTurns = 6,
    this.enableFastCommands = true,
  });

  JarvisConfig copyWith({
    BrainMode? brainMode,
    String? serverUrl,
    String? serverModel,
    String? localModelPath,
    int? localContextSize,
    int? localGpuLayers,
    String? languageCode,
    List<String>? wakeWords,
    String? systemInstruction,
    double? temperature,
    int? maxReplyTokens,
    int? maxHistoryTurns,
    bool? enableFastCommands,
  }) {
    return JarvisConfig(
      brainMode: brainMode ?? this.brainMode,
      serverUrl: serverUrl ?? this.serverUrl,
      serverModel: serverModel ?? this.serverModel,
      localModelPath: localModelPath ?? this.localModelPath,
      localContextSize: localContextSize ?? this.localContextSize,
      localGpuLayers: localGpuLayers ?? this.localGpuLayers,
      languageCode: languageCode ?? this.languageCode,
      wakeWords: wakeWords ?? this.wakeWords,
      systemInstruction: systemInstruction ?? this.systemInstruction,
      temperature: temperature ?? this.temperature,
      maxReplyTokens: maxReplyTokens ?? this.maxReplyTokens,
      maxHistoryTurns: maxHistoryTurns ?? this.maxHistoryTurns,
      enableFastCommands: enableFastCommands ?? this.enableFastCommands,
    );
  }
}
