<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="Polka icon">
</p>

<h1 align="center">Polka</h1>

<p align="center">
  A control center that lives in your MacBook’s notch.<br>
  Saved tabs, VPN, music, your next meeting, a calculator and a clipboard — one hover away.
</p>

<p align="center">
  <a href="https://github.com/romabmstu/polka/releases/latest"><img src="https://img.shields.io/github/v/release/romabmstu/polka?label=download" alt="Latest release"></a>
  <a href="https://github.com/romabmstu/polka/actions/workflows/ci.yml"><img src="https://github.com/romabmstu/polka/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

<p align="center"><a href="README.ru.md">Читать по-русски</a> · <a href="https://romabmstu.github.io/polka/">Website</a></p>

---

Point at the notch and it opens into a panel. Move away and it tucks back in. On displays without a notch Polka sits in the center of the menu bar as a compact control, and by default it follows the pointer to whichever display you are using.

While closed, the notch shows what matters right now: a shield when your VPN is on and a countdown when a meeting is about to start.

## What it does

**Tabs.** Keep pages in named, colored groups instead of a hundred open tabs. Save the current tab from Safari, Chrome, Arc, Brave, Edge or Yandex Browser with <kbd>⌥⇧S</kbd> and pick the group right in the notch — or the whole window at once. *Save to Polka…* in the Services menu (right-click a selection or a link) does the same from any app. Drag links from anywhere onto a group, paste a whole list (plain links, Markdown or a OneTab export). Sort by title, site, date or recent use, search across everything, open a group in the current or a new window.

**VPN.** Every VPN registered in System Settings — WireGuard, Happ, V2Box, corporate L2TP and others — with a switch, plus every Tunnelblick (OpenVPN) configuration and FSNT Client / Throne through its local API. In Polka’s FSNT settings, enter the port and key of the enabled API; the key is stored in Keychain. Some FSNT versions expose the API only in advanced mode. Other apps without a supported integration have unknown connection status. Connections are controlled independently; whether they work together depends on the clients and their routes.

**Music.** Title, artist, artwork and a seekable progress bar for whatever is playing — Yandex Music, Music, Spotify, a video in the browser — and which app that is, so play and pause always act where you expect.

**Calendar.** Today’s events from the calendars already on your Mac (Google, iCloud, Exchange) and a Join button for Google Meet, Zoom, Teams, Telemost, Jitsi and Webex links.

**Calculator and currencies.** Type `1250 × 1.2 + 15%`, get the answer. Convert between your favorite currencies.

**Clipboard.** The last 30 things you copied, screenshots and pictures included. Content marked as concealed or transient is skipped, but passwords from apps that do not mark them may still be recorded.

**Shelf.** Drop files into the notch and drag them out later, or send them over AirDrop.

**Scenarios.** One click for several things at once — for example *Work*: quit the messengers, connect the VPN, switch to dark mode, set the volume, open the work tabs and apps, start music. Focus modes switch through a shortcut.

## Install

1. Download `Polka-vX.Y.Z.zip` from [Releases](https://github.com/romabmstu/polka/releases/latest) and move **Polka** to Applications.
2. The app is not notarized by Apple yet, so the first launch is blocked. Run once in Terminal:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Polka.app
   ```
   or open it, then go to System Settings › Privacy & Security and click **Open Anyway**.
3. Point at the notch.

Each release lists a SHA-256 checksum and carries a [build provenance attestation](https://github.com/romabmstu/polka/attestations): you can check that the zip was built by this repository’s workflow from the tagged commit:

```sh
gh attestation verify Polka-vX.Y.Z.zip --repo romabmstu/polka
```

## Updates

Polka updates itself: Settings › Updates › *Check Now*, or wait for the *Update* button in the panel. Choose **Every new build (beta)** to get each change as soon as it is merged, or **Releases** for tagged versions. Updates are verified against a signing key built into the app before anything is replaced.

## Keyboard

| Shortcut | Action |
| --- | --- |
| <kbd>⌥⇧K</kbd> | Open or close Polka |
| <kbd>⌥⇧S</kbd> | Save the current browser tab, choosing the group |
| <kbd>⌘1</kbd> … <kbd>⌘8</kbd> | Switch sections |
| <kbd>⌘V</kbd> | Paste links into the open group |
| <kbd>Esc</kbd> | Close the panel |

## Privacy

Polka has no account, no analytics and no telemetry. Your tabs are stored in a single file only you can read: `~/Library/Application Support/Polka/library.json`.

It uses the network to check for updates and, if enabled, to fetch exchange rates. Details and the full list of permissions are in [PRIVACY.md](PRIVACY.md).

## Build from source

Requirements: macOS 14 or later, Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone https://github.com/romabmstu/polka.git
cd polka
brew install xcodegen
make project      # generates Polka.xcodeproj
open Polka.xcodeproj
```

Builds are signed to run locally, so no Apple developer account is needed. `make test` runs the unit tests.

The code is split in two:

- `Packages/PolkaKit` — the logic, with tests. `PolkaCore` holds models and parsers with no system dependencies; `PolkaSystem` wraps `scutil`, AppleScript, EventKit and the pasteboard.
- `App` — the notch window and SwiftUI views.

## Contributing

Bug reports and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Please report security problems privately as described in [SECURITY.md](SECURITY.md).

## Support

Polka is free and will stay free — no ads, no subscriptions, no paid tier. If it saves you a few minutes a day and you’d like to say thanks, you can buy me a coffee:

| Currency | Network | Address |
| --- | --- | --- |
| USDT | Tron (TRC-20) | `TNxyTAuSRBcLpCbfTURjDiJHdhFjQHwBnd` |
| USDT | Ethereum (ERC-20) | `0xf080C9113c0D2Ba28b1cF23adbbEc7Aafe907D35` |
| Bitcoin | Bitcoin | `bc1q6exu9tgl2d29z9t3eczksjj4e4jrqwnd7zt22l` |

> [!IMPORTANT]
> Send only on the network shown next to the address. Coins sent on another network cannot be recovered.

Not into crypto? A ⭐ on GitHub, a bug report or telling a friend helps just as much.

## License

[MIT](LICENSE)
