# LocalWhisper — Multilingual Mode Fork

<p align="center">
  <strong>Local voice-to-text for macOS — with seamless multilingual transcription</strong><br>
  100% offline • Apple Silicon optimized • Menu bar app
</p>

<p align="center">
  <a href="https://github.com/mohmaddov/local-whisper-multilingual-mode/releases/latest"><img src="https://img.shields.io/github/v/release/mohmaddov/local-whisper-multilingual-mode" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
</p>

---

A macOS menu bar app for local speech-to-text powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit). Press a hotkey, speak in **any language (or mix of languages)**, and text appears in any app — no internet required.

> **This is a fork of [t2o2/local-whisper](https://github.com/t2o2/local-whisper)** with added **multilingual mode** — switch languages mid-sentence (like Wispr Flow) and get per-segment language detection in the logs.

## ✨ What's new in this fork

### 🌍 Multilingual mode
Speak in multiple languages within a single recording — French, Russian, English, Spanish, Chinese, etc. — and each segment is transcribed in its **original language** (Cyrillic stays Cyrillic, French stays French, no forced translation to English).

- **VAD-based segmentation** — silence detection splits your speech into independent regions
- **Per-segment language detection** — each region is analyzed independently to avoid language bias from previous chunks
- **Faithful transcription** — Russian → Cyrillic, Arabic → Arabic, Chinese → 中文 (no auto-translation)

Example output mixing French and Russian in one recording:
> 🇫🇷 *Je m'appelle Hugo et j'ai 16 ans.*
> 🇫🇷 *Ma sœur s'appelle Laura.*
> 🇷🇺 *Знакомьтесь, это Татьяна, моя учительница русского языка.*
> 🇫🇷 *Nous sommes à l'aéroport, direction Barcelone en Espagne.*
> 🇷🇺 *Она встает в 7 утра и едет в школу на машине.*

### 📊 Rich transcription logs
A new **Logs** tab in Settings shows every transcription with:
- Detected language(s) with flag emojis 🇫🇷 🇷🇺 🇬🇧 🇪🇸 🇨🇳 ...
- Per-segment language breakdown with timestamps
- Processing time, duration, model used, app context
- Search + filter by language
- Export to plain text

All records are stored as JSONL at `~/Documents/LocalWhisper/transcriptions.jsonl`.

### 🔇 Mute system audio while recording
Optional toggle to mute speakers during recording so your microphone doesn't pick up speaker audio.

### 🌐 Proxy support
HTTP / HTTPS / SOCKS5 proxy configuration for model downloads behind corporate firewalls.

### 🛠 Misc fixes
- Recovery from stale audio state (prevents "Recording is already in progress" lockup after a crash or Xcode forced stop)
- Improved error logging at `~/Library/Logs/LocalWhisper/errors.log`

## Quick Start

### Install (Recommended)

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/mohmaddov/local-whisper-multilingual-mode/releases/latest)
2. Open the DMG and drag **LocalWhisper** to your Applications folder
3. Open LocalWhisper from Applications
4. Grant **Microphone** and **Accessibility** permissions when prompted

> **Note**: On first launch, macOS may show "unidentified developer" warning (the app is ad-hoc signed). Right-click the app and select "Open" to bypass, or go to System Settings → Privacy & Security → "Open Anyway".

### Install from source

```bash
git clone https://github.com/mohmaddov/local-whisper-multilingual-mode.git
cd local-whisper-multilingual-mode
swift build -c release && swift run
```

### Build your own .dmg

```bash
./scripts/release.sh 1.1.0
```

Outputs `.app`, `.dmg`, and `.zip` into `dist/`.

### Use

1. Grant **Microphone** and **Accessibility** permissions when prompted
2. **Hold** your shortcut key (default: `Ctrl+Shift+Space`) to start recording
3. Speak — switch languages freely if multilingual mode is enabled
4. **Release** to stop recording and transcribe

Text is automatically typed into your focused app.

## Features

- 🌍 **Multilingual mode** — Speak multiple languages in one recording with per-segment detection
- 🎤 **Global Hotkey** — Hold to record, release to transcribe (default: `Ctrl+Shift+Space`)
- 🔒 **100% Offline** — All processing on-device, no data leaves your Mac
- ⚡ **Fast** — CoreML + Neural Engine acceleration on Apple Silicon
- 📝 **Auto-inject** — Transcribed text typed directly into focused field
- 📖 **Custom Dictionary** — Add words/names for accurate transcription of technical terms, proper nouns, etc.
- 📊 **Rich logs** — Per-segment language detection, JSONL storage, search & export
- 🔇 **Mute system audio** — Avoid feedback while recording
- 🌐 **Proxy support** — HTTP / HTTPS / SOCKS5 for model downloads

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1/M2/M3/M4)
- 8GB RAM minimum (16GB+ for large models)

## Configuration

Click the menu bar icon → **Settings** to:
- Toggle **Multilingual Mode** (auto-detect language per segment)
- Change keyboard shortcut
- Select transcription model (tiny → large-v3)
- Add custom vocabulary (product names, technical terms, proper nouns)
- View transcription logs with per-segment language breakdown
- Configure proxy

### Multilingual Mode tips

- Works best with `medium` or `large-v3` models — smaller models have weaker language detection
- Each speech region needs to be at least ~0.5s for reliable detection
- Mixing 2–3 languages in one recording works well; very rapid code-switching within a single sentence may merge segments

### Custom Dictionary

Add words you want transcribed correctly in Settings → Vocabulary. This helps the model recognize:
- Product names (e.g., "WhisperKit", "CoreML")
- Technical terms (e.g., "Kubernetes", "PostgreSQL")
- Proper nouns (names of people, places, companies)

## Documentation

- [Model Guide](docs/models.md) — Model comparison, benchmarks, recommendations
- [Architecture](docs/architecture.md) — Project structure, development guide

## Privacy

All transcription happens locally. No audio is sent over the network. No analytics or telemetry.

## License

MIT

## 🙏 Acknowledgments

This project would not exist without the incredible work of:

- **[t2o2](https://github.com/t2o2)** — Creator of the original [local-whisper](https://github.com/t2o2/local-whisper) project. The entire architecture, menu bar app, hotkey handling, text injection, and overall UX of LocalWhisper is their work. This fork only adds multilingual capabilities on top of their solid foundation. **Huge thanks!** 🚀
- **[WhisperKit](https://github.com/argmaxinc/WhisperKit)** by Argmax — Swift Whisper with CoreML acceleration
- **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)** by Sindre Sorhus — Global hotkeys
- **[OpenAI Whisper](https://github.com/openai/whisper)** — The original speech recognition model
