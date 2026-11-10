# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org).

## [Unreleased]

### Fixed

- A file dragged from the Files section into Mail or another app keeps its name. The receiving app now gets the file itself instead of a copy it had to name on its own.
- Files follows a file that was renamed or moved after it was added: the tile shows the current name and dragging it out still works. A deleted file is marked as not found instead of dragging out as nothing.
- A file dropped onto the panel or pasted as a link is stored by its real path, not by a system reference that has no name.
- Two pictures sent to Files from clipboard history within the same second no longer overwrite each other.

## [0.1.2] - 2026-11-09

### Fixed

- The notch is recognized on a MacBook with an external monitor attached, including right after the monitor is connected and after waking from sleep. Polka looks at the display again once macOS has finished rearranging displays.
- "Built-in display" in settings picks the MacBook screen even when its notch is hidden by the chosen resolution or the monitor is the main display.
- The volume in the Music section follows the volume keys, Control Center and a Bluetooth speaker's own buttons straight away, and shows when the sound is muted. It used to catch up only every few seconds.
- The wings beside the notch no longer overflow when music, a meeting countdown and VPN are shown together: they widen evenly and the countdown stays on one line.

### Changed

- Diagnostics list every display with its size and notch, to make display problems easier to report.

## [0.1.1] - 2026-11-08

### Added

- If an update closes right after it starts, Polka puts the previous version back, says so, and offers to report it. That build is not installed automatically again.

### Changed

- New installs get updates from releases. The beta channel, with every build from `main`, is one switch away in Settings › Updates.
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

[Unreleased]: https://github.com/romabmstu/polka/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/romabmstu/polka/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/romabmstu/polka/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/romabmstu/polka/releases/tag/v0.1.0
