# Whisper67

System-wide AI dictation for macOS — Superwhisper / Wispr Flow style.

Hold **Control** to talk, double-tap for sticky mode, or use a classic hotkey. Transcripts paste at your cursor. Local WhisperKit, OpenAI, or Groq.

## Install (DMG)

1. Download **Whisper67-x.y.z.dmg** from [Releases](../../releases)
2. Open the DMG and drag **Whisper67** into **Applications**
3. Launch Whisper67 and grant **Microphone** + **Accessibility** (and Input Monitoring if prompted)

> First launch from the internet: right-click → **Open** if Gatekeeper blocks an unsigned build.

## Features

- Control hold / double-tap sticky + custom toggle hotkey
- Floating glass pill with live waveform
- Dictation modes: Formal · Casual · Periods only · Auto list
- Custom dictionary
- Auto-paste at caret
- Local (WhisperKit) or cloud (Groq / OpenAI)

## Build from source

```bash
./scripts/build_dmg.sh
# → dist/Whisper67-<version>.dmg
```

Requirements: macOS 14+, Xcode 15+

## Permissions

Grant for `/Applications/Whisper67.app`:

- Microphone
- Accessibility
- Input Monitoring (if listed)

## License

MIT
