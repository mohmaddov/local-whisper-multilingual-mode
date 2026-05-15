# LocalWisprFlow

<p align="center">
  <strong>On-device voice-to-text and AI note taking for macOS</strong><br>
  100% offline · Apple Silicon optimized · Menu bar app
</p>

<p align="center">
  <a href="https://github.com/mohmaddov/local-whisper-multilingual-mode/releases/latest"><img src="https://img.shields.io/github/v/release/mohmaddov/local-whisper-multilingual-mode" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-required-black" alt="Apple Silicon">
</p>

---

**LocalWisprFlow** is a menu bar app for macOS that turns your voice into text and structured notes — entirely on your device. It combines [WhisperKit](https://github.com/argmaxinc/WhisperKit) for transcription with a local LLM (Qwen / Phi-3.5 via [MLX](https://github.com/ml-explore/mlx)) for AI-generated meeting notes. No cloud. No telemetry. Your audio never leaves your Mac.

> This project is a fork of [t2o2/local-whisper](https://github.com/t2o2/local-whisper) with a substantially expanded feature set. See **Credits** below.

## Highlights

- 🌍 **Seamless multilingual dictation** — switch between English, French, Russian, Spanish, Chinese, and more inside a single sentence
- 🧠 **AI notes** — record a meeting, get a structured markdown note back (Summary · Key Points · Action Items · Decisions)
- ⌨️ **Global hotkey dictation** — hold a key, speak, release; transcribed text is typed into the focused app
- 🎚️ **Live recording overlay** — floating panel with waveform while you speak
- 📊 **History & statistics** — every transcription stored locally with per-segment language detection, processing speed, language breakdown
- 🎙️ **Dictation commands** — say "new line", "period", "question mark" and they become the actual characters
- 🔇 **Mute system output while recording** — prevent feedback from speakers
- 🌐 **Proxy support** — HTTP / HTTPS / SOCKS5 for model downloads behind firewalls
- 🔄 **Hot-swap models** — switch between Whisper / LLM models without losing the current one (downloads in the background)
- 📤 **Export** — `.srt`, `.vtt`, `.txt` for transcripts; `.md` for AI notes

## Install

### From a release (recommended)

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/mohmaddov/local-whisper-multilingual-mode/releases/latest)
2. Open the DMG, drag **LocalWisprFlow** to your Applications folder
3. Right-click the app and choose **Open** the first time (the app is ad-hoc signed; macOS will otherwise refuse to launch it)
4. Grant **Microphone** and **Accessibility** permissions when prompted

### From source

```bash
git clone https://github.com/mohmaddov/local-whisper-multilingual-mode.git
cd local-whisper-multilingual-mode
swift run
```

### Build your own `.dmg`

```bash
./scripts/release.sh 1.2.0
```

Outputs `LocalWisprFlow.app`, `LocalWisprFlow-1.2.0.dmg`, and `LocalWisprFlow-1.2.0.zip` to `dist/`.

## Usage

### Dictation (push-to-talk)

1. **Hold** the configured shortcut (default `Ctrl+Shift+Space`)
2. Speak — switch languages freely if Multilingual Mode is on
3. **Release** to stop and transcribe; text is auto-inserted into the focused application

### AI Notes (long-form)

1. Click the menu bar icon → **New Recording** (or open Settings → Notes)
2. Speak for as long as you need (meetings, interviews, brainstorms)
3. Press **Stop**; the app transcribes the audio, then summarizes it into a structured markdown note
4. Browse notes in the **Notes** tab, edit titles inline, toggle between Summary and Transcript views, and export to `.md`

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1 / M2 / M3 / M4)
- 8 GB RAM minimum (16 GB+ recommended for Large Whisper and Phi-3.5 LLM)

## Recommended models

| Use case | Whisper | LLM (Notes) |
|---|---|---|
| Day-to-day dictation | Medium | Qwen 0.5B |
| Professional note taking | Large v3 Turbo | Phi-3.5 Mini |
| Low-end Mac | Distil Large v3 Turbo | Qwen 0.5B |

## Privacy

LocalWisprFlow runs entirely on your device. There is no telemetry, no analytics, no cloud calls. Models are downloaded from Hugging Face once and cached at `~/Documents/huggingface/`. Transcriptions and notes are stored at `~/Documents/LocalWhisper/`.

## Documentation

- [Model Guide](docs/models.md) — model comparison and recommendations
- [Architecture](docs/architecture.md) — project structure for contributors

## License

MIT.

## Credits

This fork is built and maintained by **[mohmaddov](https://github.com/mohmaddov)** — added multilingual mode, AI notes, recording overlay, statistics, hot-swap models, and the LocalWisprFlow UI redesign.

The project would not exist without:

- **[t2o2](https://github.com/t2o2)** — author of the original [LocalWhisper](https://github.com/t2o2/local-whisper). The menu bar app, hotkey infrastructure, text injection, model loading and overall architecture are their work. **Massive thanks.**
- **[WhisperKit](https://github.com/argmaxinc/WhisperKit)** by Argmax — Swift bindings to OpenAI Whisper with CoreML acceleration
- **[MLX](https://github.com/ml-explore/mlx)** & **[MLX-LM](https://github.com/ml-explore/mlx-swift-lm)** by Apple — on-device LLM inference
- **[OpenAI Whisper](https://github.com/openai/whisper)** — the original speech-recognition model
- **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)** by Sindre Sorhus — global hotkey handling
