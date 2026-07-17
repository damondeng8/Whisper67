# Whisper67

System-wide voice dictation for macOS. Hold **Control**, speak, release — clean text pastes where your cursor is.

**Download (macOS):** [Whisper67-1.0.0.dmg](https://github.com/damondeng8/Whisper67/releases/latest/download/Whisper67-1.0.0.dmg)

---

## Install (DMG)

1. Download [Whisper67-1.0.0.dmg](https://github.com/damondeng8/Whisper67/releases/latest/download/Whisper67-1.0.0.dmg)
2. Open the DMG and drag **Whisper67** into **Applications**
3. Open **Whisper67** from Applications  
   - If Gatekeeper blocks it: right‑click the app → **Open** → **Open**
4. Grant when prompted:
   - **Microphone**
   - **Accessibility** (required for hotkeys + paste)
   - **Input Monitoring** if macOS asks

Leave the app running (menu bar waveform). You don’t need the settings window open to dictate.

---

## How to use

| Action | What it does |
|--------|----------------|
| **Hold ⌃ Control** | Push-to-talk — release to transcribe & paste |
| **Double-tap ⌃** | Sticky dictation — speak freely |
| **Enter** | Send (sticky or hold) |
| **Esc** | Cancel |
| **⌥ Space** (default) | Toggle sticky start/send (change in Settings) |

Text is pasted at the **caret** in the app you were using (Notes, Slack, Cursor, browsers, etc.).

### Settings (menu bar → Open Whisper67)

- **Home** — status, shortcuts, engine
- **History** — past dictations; copy any entry
- **Modes** — Casual / Normal / Formal, Auto list, OSS fixer strength
- **API** — Groq or OpenAI key for cloud Whisper (+ optional OSS polish)
- **Dictionary** — preferred spellings (names, products)
- **General** — auto-paste, menu bar icon, launch at login

### Engines

| Engine | Notes |
|--------|--------|
| **Local** | On-device WhisperKit (no key) |
| **Groq** | Fast cloud Whisper — free tier at [console.groq.com](https://console.groq.com) |
| **OpenAI** | Cloud Whisper API |

Optional **OSS fixer** (Groq `openai/gpt-oss-20b`): cleans fillers, intention, lists. Toggle + strength slider under **Modes**.

---

## Build from source

**Requirements:** macOS 14+, Xcode 15+

```bash
git clone https://github.com/damondeng8/Whisper67.git
cd Whisper67
open Whisper67.xcodeproj
```

In Xcode: select the **Whisper67** scheme → **Run** (or Product → Archive).

### Build a signed (+ optional notarized) DMG

```bash
# One-time: store Apple notary credentials (fixes Gatekeeper “malware” warning)
xcrun notarytool store-credentials "whisper67-notary" \
  --apple-id "you@email.com" \
  --team-id PPPFP5Z7VS \
  --password "app-specific-password"   # appleid.apple.com → App-Specific Passwords

export NOTARY_PROFILE=whisper67-notary
./scripts/build_dmg.sh
# → dist/Whisper67-1.0.0.dmg  (signed, notarized, stapled when credentials present)
```

Skip notarization: `SKIP_NOTARIZE=1 ./scripts/build_dmg.sh`

Uses **Developer ID Application** if installed (with microphone entitlements).

---

## Privacy

- **Local engine:** audio stays on your Mac  
- **Cloud engine:** audio is sent to OpenAI or Groq for transcription (and OSS polish if enabled)  
- Dictionary, history, and settings stay on your machine (UserDefaults / Keychain for API keys)

---

## License

Personal / source-available project. Use at your own risk. Not affiliated with OpenAI, Groq, or Apple.
