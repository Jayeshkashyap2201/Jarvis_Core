import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Handles speech-to-text input and text-to-speech output.
class AudioEngine {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();

  String _language = 'en-IN';
  bool _sttAvailable = false;
  Completer<String>? _listenCompleter;
  String _lastWords = '';

  bool get isListening => _stt.isListening;
  bool get sttAvailable => _sttAvailable;

  /// Initializes TTS and STT for the given [language] (e.g. `en-IN`).
  Future<void> init(String language) async {
    _language = language;
    try {
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
    try {
      _sttAvailable = await _stt.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') _finishListen();
        },
        onError: (_) => _finishListen(),
      );
    } catch (_) {
      _sttAvailable = false;
    }
  }

  static final _emoji =
      RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);

  String _cleanForSpeech(String text) => text
      .replaceAll(_emoji, ' ')
      .replaceAll(RegExp(r'[*_#`~>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Speaks [text] aloud and completes when speech finishes.
  Future<void> speak(String text) async {
    final clean = _cleanForSpeech(text);
    if (clean.isEmpty) return;
    // Safety timeout so a lost "completed" callback can never freeze the app.
    final maxWait = Duration(seconds: 20 + clean.length ~/ 8);
    try {
      await _tts.speak(clean).timeout(maxWait);
    } on TimeoutException {
      await _tts.stop();
    }
  }

  void _finishListen() {
    final c = _listenCompleter;
    if (c != null && !c.isCompleted) c.complete(_lastWords);
  }

  /// Listens once and returns what was heard ('' if nothing / unavailable).
  Future<String> listenOnce({
    Duration listenFor = const Duration(seconds: 20),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!_sttAvailable) return '';
    if (_stt.isListening) await _stt.stop();

    _lastWords = '';
    final completer = _listenCompleter = Completer<String>();
    try {
      await _stt.listen(
        localeId: _language,
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (result) {
          _lastWords = result.recognizedWords;
          if (result.finalResult) _finishListen();
        },
      );
    } catch (_) {
      _finishListen();
    }

    final words = await completer.future.timeout(
      listenFor + const Duration(seconds: 5),
      onTimeout: () => _lastWords,
    );
    _listenCompleter = null;
    return words.trim();
  }

  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
    _finishListen();
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }
}
