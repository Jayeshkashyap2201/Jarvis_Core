# jarvis_core 0.2

Voice assistant core: Hinglish speech in/out, wake word ("Jarvis ..."),
built-in + custom tools, and a **switchable brain**:

| Mode | Model runs | Platforms |
|---|---|---|
| `BrainMode.server` | Ollama on your PC / server | Android, iOS, Web, Windows, macOS |
| `BrainMode.onDevice` | GGUF via llama.cpp (`llm_llamacpp`) | Android, iOS, Windows, macOS (**not Web**) |

Default model: **Qwen2.5-3B-Instruct** (Q4_K_M). No API key anywhere.

## 1. Server mode (quickest way to test)
```
ollama pull qwen2.5:3b
ollama serve
```
- Real phone -> start Ollama with `OLLAMA_HOST=0.0.0.0` and use `http://<PC-IP>:11434`.
- Android emulator -> `http://10.0.2.2:11434`.
- Flutter Web -> start Ollama with `OLLAMA_ORIGINS=*` (CORS).

## 2. On-device mode
In the app tap **On-device -> Download model** (~2 GB, Wi-Fi recommended), or:
```dart
await jarvis.useLocalModel('/path/to/model.gguf');
```
Any GGUF instruct model works (Llama 3.2 3B, Phi-3.5-mini, Qwen2.5 1.5B for weak phones...).

## 3. Add your own tool
```dart
Jarvis(
  config: JarvisConfig(...),
  tools: [
    FunctionTool(
      name: 'flashlight',
      description: 'Turns the flashlight on or off.',
      parameters: {'state': '"on" or "off"'},
      run: (args) async {
        // your code here
        return 'Flashlight ${args['state']} kar di, sir.';
      },
    ),
  ],
);
```
Or extend `JarvisTool`. The LLM decides when to call it; simple phrases
(time, date, timer, "youtube kholo", "search karo ...") are handled instantly
by `FastCommandRouter` without the LLM.

## 4. Permissions
**Android** (`AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<queries>
  <intent><action android:name="android.speech.RecognitionService"/></intent>
  <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>
  <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
</queries>
<!-- inside <application ...> : needed for http:// LAN server -->
android:usesCleartextTraffic="true"
```
**iOS** (`Info.plist`): `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`
(plain-http servers also need an ATS exception or HTTPS).

**macOS** (`DebugProfile.entitlements` / `Release.entitlements`):
`com.apple.security.network.client`, `com.apple.security.device.audio-input`.

## Known limits
- Hands-free uses the OS speech recognizer in a loop: extra battery use and, on some
  Android phones, a small beep per restart. A dedicated wake-word engine
  (e.g. Porcupine) can replace it later.
- 3B models handle tool calls reasonably but not perfectly; that is why the
  fast router exists.
- `en-IN` TTS reads Roman Hinglish acceptably; for pure Hindi set `languageCode: 'hi-IN'`.
- Timers are in-app (work while the app is alive), not system alarms.
