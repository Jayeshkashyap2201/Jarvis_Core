import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ai_brain.dart';
import 'audio_engine.dart';
import 'config.dart';
import 'llm/llm_backend.dart';
import 'llm/local_provider.dart';
import 'llm/ollama_backend.dart';
import 'tools/builtin_tools.dart';
import 'tools/fast_command_router.dart';
import 'tools/jarvis_tool.dart';

enum JarvisState { idle, listening, thinking, speaking }

/// High-level interface combining voice I/O, a switchable AI brain and tools.
class Jarvis {
  static const _noSpeech = 'Kuch sunai nahi diya, sir.';
  static const _noMic =
      'Speech recognition available nahi hai. Microphone permission check karo, sir.';
  static const _brainDown =
      'Mujhe apne dimaag se connect karne me problem aa rahi hai, sir.';

  JarvisConfig _config;
  final LocalModelProvider? _local;
  final AudioEngine _audio = AudioEngine();
  final Map<String, JarvisTool> _tools = {};
  late final FastCommandRouter _router;
  AIBrain? _brain;

  bool _initialized = false;
  bool _brainReady = false;
  String? _brainError;
  bool _handsFree = false;
  bool _busy = false;

  /// Observe this to drive your UI (listening / thinking / speaking).
  final ValueNotifier<JarvisState> state = ValueNotifier(JarvisState.idle);

  /// [localProvider] enables on-device mode (use `LlamaLocalProvider()` from
  /// the optional `jarvis_local` package). Without it only server mode works.
  Jarvis({
    required JarvisConfig config,
    List<JarvisTool> tools = const [],
    LocalModelProvider? localProvider,
  })  : _config = config,
        _local = localProvider {
    for (final t in BuiltinTools.create(onTimerDone: _onTimerDone)) {
      _tools[t.name] = t;
    }
    for (final t in tools) {
      _tools[t.name] = t;
    }
    _router = FastCommandRouter(_tools);
  }

  JarvisConfig get config => _config;
  bool get brainReady => _brainReady;
  String? get brainError => _brainError;
  String get brainName => _brain?.backend.name ?? '-';
  bool get isHandsFree => _handsFree;
  bool get hasLocalProvider => _local != null;

  /// Adds (or replaces) a tool at runtime.
  void registerTool(JarvisTool tool) => _tools[tool.name] = tool;

  /// Prepares speech engines and the brain. Call once before other methods.
  /// Never throws for a dead brain: check [brainReady] / [brainError].
  Future<void> initialize() async {
    if (_initialized) return;
    await _audio.init(_config.languageCode);
    _initialized = true;
    await _initBrain();
  }

  Future<LlmBackend> _createBackend() async {
    switch (_config.brainMode) {
      case BrainMode.server:
        return OllamaBackend(
          baseUrl: _config.serverUrl,
          model: _config.serverModel,
          temperature: _config.temperature,
          maxTokens: _config.maxReplyTokens,
        );
      case BrainMode.onDevice:
        final provider = _local;
        if (provider == null) {
          throw const LlmException(
              'On-device support install nahi hai. jarvis_local package add karo '
              'aur Jarvis(localProvider: LlamaLocalProvider()) do.');
        }
        final path = _config.localModelPath ?? await provider.findModel();
        return provider.createBackend(
          modelPath: path ?? '',
          contextSize: _config.localContextSize,
          gpuLayers: _config.localGpuLayers,
          temperature: _config.temperature,
          maxTokens: _config.maxReplyTokens,
        );
    }
  }

  Future<void> _initBrain() async {
    final old = _brain;
    _brain = null;
    _brainReady = false;
    _brainError = null;
    await old?.dispose();

    final LlmBackend backend;
    try {
      backend = await _createBackend();
    } on LlmException catch (e) {
      _brainError = e.message;
      return;
    } catch (e) {
      _brainError = '$e';
      return;
    }
    _brain = AIBrain(
      backend: backend,
      systemInstruction: _config.systemInstruction,
      tools: _tools,
      maxHistoryMessages: _config.maxHistoryTurns * 2,
    );
    try {
      await backend.initialize();
      _brainReady = true;
    } on LlmException catch (e) {
      _brainError = e.message;
    } catch (e) {
      _brainError = '$e';
    }
  }

  /// Applies a new config (switch model, server, language...) at runtime.
  Future<void> updateConfig(JarvisConfig newConfig) async {
    final languageChanged = newConfig.languageCode != _config.languageCode;
    _config = newConfig;
    if (_initialized) {
      if (languageChanged) await _audio.init(newConfig.languageCode);
      await _initBrain();
    }
  }

  /// Switch between server and on-device brain.
  Future<void> setBrainMode(BrainMode mode) =>
      updateConfig(_config.copyWith(brainMode: mode));

  /// Use a specific local GGUF file and switch to on-device mode.
  Future<void> useLocalModel(String path) => updateConfig(
      _config.copyWith(brainMode: BrainMode.onDevice, localModelPath: path));

  /// Downloads a GGUF model for on-device mode (default: Qwen2.5 3B Instruct,
  /// Q4_K_M, roughly 2 GB). Listen to the stream for progress; when
  /// `isComplete` is true, call [useLocalModel] with `modelPath`.
  Stream<ModelDownloadProgress> downloadModel({String? repoId}) {
    final provider = _local;
    if (provider == null) {
      return Stream.error(const LlmException(
          'On-device support install nahi hai (jarvis_local package chahiye).'));
    }
    return provider.download(repoId: repoId);
  }

  /// Path of an already downloaded model, if any.
  Future<String?> findDownloadedModel() async => _local?.findModel();

  void _onTimerDone(String label) {
    final msg = label.isEmpty
        ? 'Sir, aapka timer poora ho gaya.'
        : 'Sir, $label ka timer poora ho gaya.';
    _audio.speak(msg);
  }

  /// Runs [command] (fast rules first, then the AI), speaks the reply and
  /// passes it to [onReply].
  Future<void> processCommand(
      String command, Function(String) onReply) async {
    if (!_initialized) await initialize();
    final text = command.trim();
    if (text.isEmpty || _busy) return;
    _busy = true;

    String reply;
    String? spoken;
    state.value = JarvisState.thinking;
    try {
      String? fast;
      if (_config.enableFastCommands) fast = await _router.tryHandle(text);

      if (fast != null) {
        reply = fast;
      } else {
        if (!_brainReady) await _initBrain(); // maybe the server started later
        if (!_brainReady) {
          spoken = _brainDown;
          reply = '$_brainDown\n(${_brainError ?? 'unknown error'})';
        } else {
          reply = await _brain!.getResponse(text);
        }
      }
    } on LlmException catch (e) {
      spoken = _brainDown;
      reply = '$_brainDown\n(${e.message})';
    } catch (e) {
      spoken = 'Kuch gadbad ho gayi, sir.';
      reply = 'Kuch gadbad ho gayi, sir.\n($e)';
    }

    onReply(reply);
    state.value = JarvisState.speaking;
    try {
      await _audio.speak(spoken ?? reply);
    } finally {
      _busy = false;
      state.value = JarvisState.idle;
    }
  }

  /// Push-to-talk: listens once, then processes what was said.
  Future<void> listenAndRespond(Function(String) onReply,
      {Function(String)? onHeard}) async {
    if (!_initialized) await initialize();
    if (!_audio.sttAvailable) {
      onReply(_noMic);
      return;
    }
    state.value = JarvisState.listening;
    final words = await _audio.listenOnce();
    if (words.isEmpty) {
      state.value = JarvisState.idle;
      onReply(_noSpeech);
      return;
    }
    onHeard?.call(words);
    await processCommand(words, onReply);
  }

  // ---------------------------------------------------------------- hands-free

  /// Hands-free mode: keeps listening; when it hears a wake word
  /// ("Jarvis ..."), it runs the command that follows. Call [stopListening]
  /// to end it.
  ///
  /// Note: this uses the platform speech recognizer in a loop, so some
  /// Android devices play a small "listening" beep on every restart and it
  /// uses more battery than a dedicated wake-word engine.
  Future<void> startHandsFree({
    required Function(String) onReply,
    Function(String)? onHeard,
    Function()? onWake,
  }) async {
    if (_handsFree) return;
    if (!_initialized) await initialize();
    if (!_audio.sttAvailable) {
      onReply(_noMic);
      return;
    }
    _handsFree = true;
    unawaited(_handsFreeLoop(onReply, onHeard, onWake));
  }

  Future<void> _handsFreeLoop(Function(String) onReply,
      Function(String)? onHeard, Function()? onWake) async {
    while (_handsFree) {
      try {
        if (_busy) {
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }
        state.value = JarvisState.listening;
        final heard = await _audio.listenOnce(
            listenFor: const Duration(seconds: 30),
            pauseFor: const Duration(seconds: 2));
        if (!_handsFree) break;

        final afterWake = heard.isEmpty ? null : _afterWakeWord(heard);
        if (afterWake == null) {
          await Future.delayed(const Duration(milliseconds: 400));
          continue;
        }

        onWake?.call();
        var command = afterWake;
        if (command.isEmpty) {
          state.value = JarvisState.speaking;
          await _audio.speak('Ji sir?');
          if (!_handsFree) break;
          state.value = JarvisState.listening;
          command = await _audio.listenOnce(
              listenFor: const Duration(seconds: 15),
              pauseFor: const Duration(seconds: 2));
          if (command.isEmpty) continue;
        }

        onHeard?.call(command);
        await processCommand(command, onReply);
        await Future.delayed(const Duration(milliseconds: 400));
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    state.value = JarvisState.idle;
  }

  /// Returns the text spoken after the wake word, '' if only the wake word
  /// was said, or null if there was no wake word.
  String? _afterWakeWord(String heard) {
    final lower = heard.toLowerCase();
    for (final w in _config.wakeWords) {
      final word = w.toLowerCase();
      final i = lower.indexOf(word);
      if (i < 0) continue;
      var rest = lower.substring(i + word.length).trim();
      rest = rest.replaceFirst(RegExp(r'^[,.\-:!?\s]+'), '');
      rest = rest.replaceFirst(RegExp(r'^(sir|सर)(?=[\s,.!?]|$)[,.\s]*'), '');
      return rest.trim();
    }
    return null;
  }

  // ---------------------------------------------------------------- controls

  /// Stops microphone listening (and hands-free mode).
  Future<void> stopListening() async {
    _handsFree = false;
    await _audio.stopListening();
  }

  Future<void> stopSpeaking() => _audio.stopSpeaking();

  /// Forgets the conversation so far.
  void clearMemory() => _brain?.clearHistory();

  Future<void> dispose() async {
    _handsFree = false;
    await _audio.stopListening();
    await _audio.stopSpeaking();
    for (final t in _tools.values) {
      t.dispose();
    }
    await _brain?.dispose();
    state.dispose();
  }
}
