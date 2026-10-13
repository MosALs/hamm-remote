# HAAM Remote

A phone remote for HAAM (TCL-built) Android TVs, for Android and iPhone. It works over Wi-Fi with the same protocol as Google's official TV remote ("Android TV Remote Service", protocol v2), so it needs no app on the TV.

Every key on the physical remote is included: power, input, settings, mute, the D-pad with OK, back, home, menu, volume, channels, live TV, the number pad, the **red / green / yellow / blue keys** (used in the satellite tuning menu), guide, info, subtitles, media keys, typing into search boxes, and one-tap launch of Netflix, YouTube, Prime Video and Shahid. The arrows, volume and channel keys repeat while you hold them, which makes long frequency lists quick to scroll.

## Install

Every push to `main` builds the app on GitHub Actions and publishes it under **Releases → latest**:

| Phone | File | How to install |
|---|---|---|
| Android | `haam-remote.apk` | Open the release page on the phone, download the file, open it, and allow "install unknown apps" for your browser when asked. Later builds install over the old one. |
| iPhone | `haam-remote-unsigned.ipa` | Apple only allows App Store installs, or sideloading with your Apple ID through [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io). With a free Apple ID the app must be refreshed every 7 days. A paid developer account ($99/yr) removes that limit, and you can then use TestFlight. |

## First use

1. Put the phone on the same Wi-Fi as the TV.
2. Open the app. The TV appears under *On this network*. If it doesn't, tap **Enter TV IP address**; you can find the address on the TV under Settings → Network & Internet → your Wi-Fi.
3. The TV shows a 6-character code. Type it in the app. You only do this once.

If the TV is ever reset, the app asks you to pair again.

## Project layout

```
lib/src/protocol/   Android TV Remote v2: protobuf, framing, TLS, pairing, remote session
lib/src/crypto/     RSA key + self-signed certificate (pure Dart), DER, pairing secret
lib/src/app/        Saved TVs, mDNS discovery, connection controller (auto-reconnect)
lib/src/ui/         Screens and the remote's widgets
tool/mock_tv/       A simulated TV (Python) used by the tests, plus its validation
                    against the reference client androidtvremote2
tool/icons/         Generates the app icons
```

Only the customised platform files are committed: the manifest, Info.plist, icons and launch theme. CI runs `flutter create` to fill in the rest. To build locally:

```sh
flutter create --org com.haam --project-name haam_remote --platforms android,ios .
flutter pub get
flutter run
```

## Tests

```sh
pip install pyopenssl cryptography androidtvremote2
python tool/mock_tv/validate_mock.py   # mock TV vs. the reference client
flutter analyze
flutter test                            # unit, widget, and end-to-end vs. the mock TV
flutter test --tags screenshots --run-skipped --update-goldens   # renders screens to test/screenshots/goldens/
```

The end-to-end tests run the real Dart client against `tool/mock_tv/mock_tv.py`. They cover pairing (including a mistyped code), refusing unpaired phones, key events with long presses, volume updates, app launch, text input, ping keep-alive, the TV disappearing, and pinning of the TV's identity.

## Signing

`android/signing/sideload.p12` (alias `haam`, password `haamremote`) signs the APK, so updates install over earlier versions. It only suits a private, personal repo. If the repo becomes public, generate a new key, store it as a repository secret, and change the "Sign" step in `.github/workflows/build.yml`.
