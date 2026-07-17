# CLAUDE.md

## Project Overview

Whisper67 is a macOS system-wide AI dictation app (Superwhisper / Wispr Flow style):

- Global hotkey → floating liquid-glass pill with waveform
- Transcribe via **Groq Whisper**, **OpenAI Whisper**, or **local WhisperKit**
- Auto-paste at cursor
- Custom dictionary, word count, API usage stats
- Menu bar + home dashboard

## Build

```bash
xcodebuild -project Whisper67.xcodeproj -scheme Whisper67 -configuration Debug \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" build

open Whisper67.xcodeproj
```

Team **PPPFP5Z7VS** is available for Developer ID signing (Release). Debug uses ad-hoc (`-`).

## Architecture

| Layer | Files |
|-------|--------|
| App entry / menu bar | `Whisper67App.swift` |
| State | `Models/AppState.swift` |
| Hotkey | `Services/GlobalHotkeyService.swift` |
| Record | `Services/AudioRecorderService.swift` |
| Cloud STT | `Services/CloudWhisperAPI.swift` |
| Local STT | `Services/WhisperService.swift` + WhisperKit |
| Orchestration | `Services/TranscriptionManager.swift` |
| Paste | `Services/ClipboardService.swift` |
| Floating pill | `Views/TranscriptionOverlayView.swift` |
| Home UI | `Views/SettingsView.swift`, `HomeDashboardView.swift`, `APISettingsTab.swift`, `DictionaryTab.swift`, `HotkeysTab.swift`, `GeneralTab.swift` |

## Design

Ice-white liquid glass: `.ultraThinMaterial`, soft gradients, continuous corner radii, floating capsule pill with live bars.
