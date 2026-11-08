# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added

- If an update closes right after it starts, Polka puts the previous version back, says so, and offers to report it. That build is not installed automatically again.

### Changed

- Links opened from Polka go to a new tab in the browser window you have open (Safari, Chrome, Arc, Brave, Edge, Yandex Browser) instead of a new window. Opening a whole group in a new window works as before.

### Fixed

- Copying a large picture no longer makes the panel stutter: pictures are converted in the background, and clipboard history keeps them under 40 MB in total.
- A panel layout saved by a newer version no longer resets after going back to an older one.

### Security

- Updates are installed only if they are signed with the same certificate as the running app, so macOS keeps the permissions you granted.

## [0.1.0] - 2026-11-08

The first public release.

### Panel

- Opens from the MacBook notch on hover or with ⌥⇧K; on other displays it is a slim capsule in the menu bar and follows the pointer between screens.
- The closed notch shows what is playing, an active VPN and a countdown to the next meeting.
- English and Russian.
- A welcome window on first launch shows the live status of every permission (each installed browser, calendars, accessibility) with one-click requests, open at login and the shortcuts. It is available again from Settings › About.

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

### Help

- **Report a Problem** opens a pre-filled GitHub issue with diagnostics (versions, Mac model, displays, permission status; no personal data). **Copy Diagnostics** puts the same text on the clipboard.
- After a crash, the next launch offers to report it with the crash summary and shows the crash file to attach.

### Distribution

- A disk image with a drag-to-Applications window, and a Homebrew cask. Every image is mounted and its app signature checked before it is published.
- Every build is launched on CI and must keep running before it reaches anyone.
- Built-in updates verified with an Ed25519 signature; a beta channel gets every build from `main`.
- Release builds carry a build provenance attestation.

[Unreleased]: https://github.com/romabmstu/polka/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/romabmstu/polka/releases/tag/v0.1.0
