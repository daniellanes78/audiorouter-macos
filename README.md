# 🎧 AudioRouter — Per-App Audio Output for macOS

**Send each app to a different audio device.** Music on the MacBook speakers, calls on your headphones, browser on the external monitor — at the same time.

Free and open-source alternative to SoundSource for per-app audio routing on Mac.

![macOS](https://img.shields.io/badge/macOS-14.2%2B-black?logo=apple) ![Swift](https://img.shields.io/badge/Swift-5-orange?logo=swift) ![License](https://img.shields.io/badge/license-MIT-blue)

---

## Why

macOS sends **all** audio to a single output device. There's no built-in way to say "Spotify → speakers, Teams → AirPods". AudioRouter adds exactly that, using Apple's native **Core Audio Process Taps** API (macOS 14.2+). No virtual audio driver, no kernel extension.

## Features

- 🎚️ Route any app to any output device (built-in speakers, Bluetooth, USB, HDMI/DisplayPort)
- 💾 Routes are remembered per app and re-applied when the app reopens
- 🟢 Shows which apps are currently playing audio
- 🌐 Groups browser helper processes (Chrome, Safari/WebKit, Edge, Brave)
- 🪟 Regular window + menu bar icon
- 🔒 No drivers, no system extensions, no network access

## Install

1. Download **`AudioRouter.dmg`** from [Releases](../../releases/latest)
2. Open the DMG and drag **AudioRouter** to **Applications**
3. First launch: the app is not notarized, so macOS will block it. Either:
   - Try to open it, then go to **System Settings → Privacy & Security → Open Anyway**, or
   - Run: `xattr -dr com.apple.quarantine /Applications/AudioRouter.app`

## How to use

1. Open **AudioRouter** (Spotlight: `⌘ Space` → "AudioRouter")
2. Start playing something (Spotify, YouTube, a call…). The app shows up with a 🟢
3. Pick the output device in the menu next to the app
4. On the first route, macOS asks for **System Audio Recording** permission → **Allow**
   (required to capture the app's audio; if you denied it: System Settings → Privacy & Security → Screen & System Audio Recording)
5. Choose **"Padrão"** (Default) to send the app back to the system output

Toggle **"Todos"** to list every app with audio, not only the ones playing now.

## Build from source

Requirements: macOS 14.2+, Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
git clone https://github.com/daniellanes78/audiorouter-macos.git
cd audiorouter-macos
./make-dmg.sh          # builds Release and creates AudioRouter.dmg
```

Or open in Xcode: `xcodegen && open AudioRouter.xcodeproj`, then `⌘R`.

## How it works

For each routed app:

1. `CATapDescription` + `AudioHardwareCreateProcessTap` capture the app's audio and mute it on the original output (`mutedWhenTapped`)
2. A private aggregate device is created with the target output as the clock and the tap as input
3. An IOProc copies the tapped audio to the target device in real time

## Known limitations

- **Wired 3.5mm headphones:** on MacBooks, plugging into the headphone jack may cut the internal speakers at hardware level. Bluetooth/USB headphones work fine.
- No per-app volume yet (planned)
- Not notarized (requires a paid Apple Developer account)

## Roadmap

- [ ] Per-app volume and mute
- [ ] Launch at login
- [ ] Send one app to multiple outputs at once
- [ ] English UI / localization

---

## 🇧🇷 Em português

**AudioRouter** permite mandar cada app do Mac pra uma saída de áudio diferente. Por exemplo, música no alto-falante e reunião no fone, ao mesmo tempo. É gratuito, open source e não instala driver.

**Instalar:** baixe o `AudioRouter.dmg` em [Releases](../../releases/latest) e arraste pra Aplicativos. Na primeira abertura, libere em **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**.

**Usar:** abra o app e dê play em algo. Na lista, escolha a saída de cada app. Quando o macOS pedir a permissão de **gravação de áudio do sistema**, clique em Permitir.

---

**Keywords:** macOS per-app audio output, route app audio to different speakers, separate audio output per application Mac, volume mixer macOS, SoundSource alternative free, AirPods and speakers at the same time, Core Audio Process Tap example.

## License

MIT © daniellanes78
