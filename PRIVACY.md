# Privacy

Polka is built to work entirely on your Mac.

## What is stored, and where

| Data | Location | Notes |
| --- | --- | --- |
| Tab groups | `~/Library/Application Support/Polka/library.json` | Readable only by your user account (permissions `0600`). |
| Exchange rates | `~/Library/Application Support/Polka/rates.json` | Public data, only if rates are turned on. |
| Settings and scenarios | `~/Library/Preferences/io.github.romabmstu.Polka.plist` | Standard app preferences. |
| Clipboard history | Memory only | Text and pictures; never written to disk, gone when Polka quits. A picture is written to a private temporary folder only if you choose *Add to Shelf*. |
| Files on the shelf | Memory only | Polka keeps references, it never copies or moves your files. |

## Network

Polka makes two kinds of requests, both without cookies, identifiers or personal data:

- **Updates.** Every 15 minutes (and when you click *Check Now*) it reads a small `update.json` from this project's GitHub releases. Turn this off in Settings › Updates.
- **Exchange rates.** Only if you turn on currency conversion: public rates from `https://open.er-api.com` (ExchangeRate-API), a few times a day.

Nothing else goes over the network. Polka does not download site icons, so the sites you save never see a request from it. To tell you why music stopped, it asks macOS whether the Mac is online; that is a local question and sends nothing.

## Permissions

Polka asks for each permission only when you use the feature that needs it.

| Permission | Why |
| --- | --- |
| Automation › your browsers | Read the address and title of open tabs in Safari, Chrome, Arc, Brave, Edge or Yandex Browser to save them; open a group in a new window. Asked separately for each browser you use. |
| Automation › System Events | Only if a scenario switches dark mode. |
| Automation › Tunnelblick | Only if Tunnelblick is installed: list its configurations, their state, connect and disconnect. |
| Calendars | Show today’s events and the next meeting. Read-only. |
| Accessibility | Only as a fallback for the media keys if the Now Playing helper cannot run. Polka does not read the screen or other apps’ content. |

Now Playing information (title, artist, artwork) is read on your Mac through the bundled MediaRemote adapter and never leaves it.

VPN switching uses the system `scutil` tool and needs no permission. For FSNT / Throne, an optional local API integration connects only to 127.0.0.1 using the API key you provide; the key is stored in macOS Keychain. The key grants control of the client. For other apps without an integration, Polka cannot determine or control their connection. Global shortcuts use the Carbon hot key API, which sees only Polka’s own key combinations — Polka does not monitor your typing.

## Clipboard

When clipboard history is on, Polka checks the pasteboard twice a second for new text or pictures. Pictures over 15 MB are skipped, and at most 8 are kept. Content that password managers mark as concealed or transient (see [nspasteboard.org](http://nspasteboard.org)) is skipped without being read. History is kept in memory only.

## Bug reports

Polka never sends reports by itself. **Report a Problem** (Settings › About, or the **…** menu in the panel) opens a GitHub issue in your browser with the form already filled in, and you decide whether to post it. The filled-in diagnostics are: Polka version and update channel, macOS version, Mac model identifier and architecture, number of displays and whether one has a notch, your preferred language, the enabled sections, whether clipboard history is on, and which permissions are granted (browser automation per browser, calendars, accessibility, open at login). No tabs, links, events, clipboard contents, VPN names or files are included.

After an unexpected quit, Polka looks in `~/Library/Logs/DiagnosticReports` for its own crash report from that session and offers to report it the same way: the summary (exception and the top of the crashed thread) goes into the form, and Finder shows the full file so you can attach it if you want. Reports of other apps are never read.

