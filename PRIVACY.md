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

- **Updates.** Every six hours (and when you click *Check Now*) it reads a small `update.json` from this project's GitHub releases. Turn this off in Settings › Updates.
- **Exchange rates.** Only if you turn on currency conversion: public rates from `https://open.er-api.com` (ExchangeRate-API), a few times a day.

Nothing else goes over the network. Polka does not download site icons, so the sites you save never see a request from it.

## Permissions

Polka asks for each permission only when you use the feature that needs it.

| Permission | Why |
| --- | --- |
| Automation › your browsers | Read the address and title of open tabs in Safari, Chrome, Arc, Brave, Edge or Yandex Browser to save them; open a group in a new window. Asked separately for each browser you use. |
| Automation › System Events | Only if a scenario switches dark mode. |
| Calendars | Show today’s events and the next meeting. Read-only. |
| Accessibility | Only as a fallback for the media keys if the Now Playing helper cannot run. Polka does not read the screen or other apps’ content. |

Now Playing information (title, artist, artwork) is read on your Mac through the bundled MediaRemote adapter and never leaves it.

VPN switching uses the system `scutil` tool and needs no permission. For proxy clients such as FSNT Client, Polka opens and quits the app and reads the proxy settings (`scutil --proxy`) and the default route to show whether it is connected; it never changes network settings itself. Global shortcuts use the Carbon hot key API, which sees only Polka’s own key combinations — Polka does not monitor your typing.

## Clipboard

When clipboard history is on, Polka checks the pasteboard twice a second for new text or pictures. Pictures over 15 MB are skipped, and at most 8 are kept. Content that password managers mark as concealed or transient (see [nspasteboard.org](http://nspasteboard.org)) is skipped without being read. History is kept in memory only.
