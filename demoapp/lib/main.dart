import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:jarvis_core/jarvis_core.dart';

void main() {
  runApp(const JarvisApp());
}

/// Where the Ollama server lives.
///  - Android emulator: 10.0.2.2 = your PC.
///  - Real phone: replace with your PC's LAN IP, e.g. http://192.168.1.10:11434
///    (start Ollama with OLLAMA_HOST=0.0.0.0).
///  - Desktop / Web: localhost.
///
/// Real phone par test kar rahe ho? Apne PC ka IP yahan likho, e.g.
/// 'http://192.168.1.10:11434' (phone aur PC same Wi-Fi par hone chahiye).
const String kServerUrlOverride = 'http://127.0.0.1:11434';

String _defaultServerUrl() {
  if (kServerUrlOverride.isNotEmpty) return kServerUrlOverride;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:11434';
  }
  return 'http://localhost:11434';
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jarvis AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyanAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const JarvisHomeScreen(),
    );
  }
}

class JarvisHomeScreen extends StatefulWidget {
  const JarvisHomeScreen({super.key});

  @override
  State<JarvisHomeScreen> createState() => _JarvisHomeScreenState();
}

class _JarvisHomeScreenState extends State<JarvisHomeScreen>
    with SingleTickerProviderStateMixin {
  // No API key needed anymore.
  final Jarvis _jarvis = Jarvis(
    config: JarvisConfig(
      brainMode: BrainMode.server,
      serverUrl: _defaultServerUrl(),
      serverModel: 'qwen2.5:3b',
    ),
    // On-device mode ke liye (jarvis_local package add karne ke baad):
    // localProvider: const LlamaLocalProvider(),
    //
    // Add your own tools here, for example:
    // tools: [
    //   FunctionTool(
    //     name: 'flashlight',
    //     description: 'Turns the flashlight on or off.',
    //     parameters: {'state': '"on" or "off"'},
    //     run: (args) async => 'Flashlight ${args['state']} kar di, sir.',
    //   ),
    // ],
  );

  BrainMode _mode = BrainMode.server;
  bool _isListening = false;
  bool _handsFree = false;
  bool _downloading = false;
  double? _downloadProgress;
  String _statusText = 'Starting...';
  String _lastSpoken = '';
  String _lastReply = '';
  final TextEditingController _textController = TextEditingController();

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _jarvis.state.addListener(_onJarvisState);
    _initJarvis();
  }

  Future<void> _initJarvis() async {
    await _jarvis.initialize();
    if (!mounted) return;
    _reportBrain();
  }

  void _reportBrain() {
    setState(() {
      if (_jarvis.brainReady) {
        _statusText = 'Online - ${_jarvis.brainName}';
      } else {
        _statusText = 'Brain Offline';
        _lastSpoken = '';
        _lastReply = _jarvis.brainError ?? 'Unknown error';
      }
    });
  }

  void _onJarvisState() {
    if (!mounted) return;
    final s = _jarvis.state.value;
    setState(() {
      _isListening = s == JarvisState.listening;
      _statusText = switch (s) {
        JarvisState.idle => _handsFree ? 'Hands-free On' : 'System Ready',
        JarvisState.listening => _handsFree ? 'Say "Jarvis"...' : 'Listening...',
        JarvisState.thinking => 'Processing...',
        JarvisState.speaking => 'Speaking...',
      };
    });
  }

  @override
  void dispose() {
    _jarvis.state.removeListener(_onJarvisState);
    _animController.dispose();
    _textController.dispose();
    _jarvis.dispose();
    super.dispose();
  }

  void _onReply(String reply) {
    if (!mounted) return;
    setState(() => _lastReply = reply);
  }

  void _onHeard(String words) {
    if (!mounted) return;
    setState(() => _lastSpoken = words);
  }

  void _startListening() {
    _jarvis.listenAndRespond(_onReply, onHeard: _onHeard);
  }

  Future<void> _stopEverything() async {
    await _jarvis.stopListening();
    await _jarvis.stopSpeaking();
    if (!mounted) return;
    setState(() {
      _handsFree = false;
      _isListening = false;
      _statusText = 'Standby Mode';
    });
  }

  Future<void> _toggleHandsFree(bool on) async {
    setState(() => _handsFree = on);
    if (on) {
      await _jarvis.startHandsFree(onReply: _onReply, onHeard: _onHeard);
    } else {
      await _jarvis.stopListening();
    }
  }

  Future<void> _sendTextCommand(String command) async {
    if (command.trim().isEmpty) return;
    _textController.clear();
    setState(() => _lastSpoken = command);
    await _jarvis.processCommand(command, _onReply);
  }

  Future<void> _switchMode(BrainMode mode) async {
    setState(() {
      _mode = mode;
      _statusText = 'Switching brain...';
    });
    await _jarvis.setBrainMode(mode);
    if (!mounted) return;
    _reportBrain();
  }

  Future<void> _downloadModel() async {
    setState(() {
      _downloading = true;
      _downloadProgress = null;
    });
    try {
      await for (final p in _jarvis.downloadModel()) {
        if (!mounted) return;
        setState(() {
          _downloadProgress = p.progress;
          _statusText = p.message;
        });
        if (p.isComplete && p.modelPath != null) {
          await _jarvis.useLocalModel(p.modelPath!);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _lastReply = 'Download error: $e');
    }
    if (!mounted) return;
    setState(() => _downloading = false);
    _reportBrain();
  }

  @override
  Widget build(BuildContext context) {
    final needsModel = _mode == BrainMode.onDevice && !_jarvis.brainReady;

    return Scaffold(
      appBar: AppBar(
        title: const Text('J.A.R.V.I.S.', style: TextStyle(letterSpacing: 2.0)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Text(
                _statusText.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.cyanAccent.withValues(alpha: 0.8),
                  fontSize: 12,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Brain switch: server <-> on-device
              SegmentedButton<BrainMode>(
                segments: [
                  const ButtonSegment(
                    value: BrainMode.server,
                    label: Text('Server'),
                    icon: Icon(Icons.dns),
                  ),
                  ButtonSegment(
                    value: BrainMode.onDevice,
                    label: const Text('On-device'),
                    icon: const Icon(Icons.phone_android),
                    enabled: !kIsWeb && _jarvis.hasLocalProvider,
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => _switchMode(s.first),
              ),

              if (needsModel) ...[
                const SizedBox(height: 8),
                if (_downloading)
                  LinearProgressIndicator(value: _downloadProgress)
                else
                  TextButton.icon(
                    onPressed: _downloadModel,
                    icon: const Icon(Icons.download),
                    label: const Text('Download model (~2 GB)'),
                  ),
              ],
              // Orb takes the leftover space and shrinks if the screen is small
              // (keyboard open, small phone) -> no more overflow.
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedBuilder(
                      animation: _animController,
                      builder: (context, child) {
                        return Container(
                          width: 160 + (_animController.value * 20),
                          height: 160 + (_animController.value * 20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.cyanAccent.withValues(alpha: 0.4),
                                Colors.blue.withValues(alpha: 0.1),
                                Colors.transparent,
                              ],
                            ),
                            border: Border.all(
                              color: Colors.cyanAccent.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.cyanAccent
                                    .withValues(alpha: _isListening ? 0.6 : 0.2),
                                blurRadius: 20 + (_animController.value * 10),
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              _isListening ? Icons.mic : Icons.bolt,
                              size: 50,
                              color: Colors.cyanAccent,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Conversation card
              if (_lastSpoken.isNotEmpty || _lastReply.isNotEmpty)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.cyanAccent.withValues(alpha: 0.2)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_lastSpoken.isNotEmpty)
                          Text(
                            'You: "$_lastSpoken"',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                          ),
                        if (_lastSpoken.isNotEmpty && _lastReply.isNotEmpty)
                          const SizedBox(height: 8),
                        if (_lastReply.isNotEmpty)
                          Text(
                            'Jarvis: "$_lastReply"',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // Hands-free wake word toggle
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Hands-free ("Jarvis ...")'),
                value: _handsFree,
                onChanged: _toggleHandsFree,
              ),

              // Text input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type a command...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      onSubmitted: _sendTextCommand,
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () => _sendTextCommand(_textController.text),
                    icon: const Icon(Icons.send, color: Colors.cyanAccent),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Bottom buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _stopEverything,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                      foregroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: (_isListening || _handsFree) ? null : _startListening,
                    icon: const Icon(Icons.mic),
                    label: const Text('Speak'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent.withValues(alpha: 0.2),
                      foregroundColor: Colors.cyanAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}