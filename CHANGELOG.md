# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org).

## [Unreleased]

## [0.1.0] - 2026-11-08

The first public release.

### Panel

- Opens from the MacBook notch on hover or with ⌥⇧K; on other displays it is a slim capsule in the menu bar and follows the pointer between screens.
- The closed notch shows what is playing, an active VPN and a countdown to the next meeting.
- English and Russian.

### Sections

- **Tabs:** groups and nested groups; ⌥⇧S saves the current tab or the whole window from Safari, Chrome, Arc, Brave, Edge or Yandex Browser and asks which group; *Save to Polka…* in the Services menu; paste lists, Markdown and OneTab exports; search and sorting.
- **VPN:** system VPN connections, Tunnelblick configurations, and FSNT Client / Throne through its local API.
- **Music:** title, artist, artwork, seeking and the app that is playing.
- **Translator:** on-device translation with Apple’s Translation framework (macOS 15+), ⌥⇧T for selected text, *Translate with Polka* in the Services menu.
- **Calendar:** browse days and weeks, choose calendars, one-click join for Meet, Zoom, Teams, Telemost, Jitsi and Webex.
- **Calculator** with currency conversion.
- **Clipboard history** in memory, pictures included.
- **Shelf** for files, with AirDrop.
- **Scenarios:** VPN, music, tabs, links, Shortcuts, opening and quitting apps, dark mode and volume in one click.

### Distribution

- Disk image and Homebrew cask.
- Built-in updates verified with an Ed25519 signature; a beta channel gets every build from `main`.
- Release builds carry a build provenance attestation.

