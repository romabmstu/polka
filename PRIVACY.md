# Privacy

Polka is built to work entirely on your Mac.

## What is stored, and where

| Data | Location | Notes |
| --- | --- | --- |
| Tab groups | `~/Library/Application Support/Polka/library.json` | Readable only by your user account (permissions `0600`). |
| Exchange rates | `~/Library/Application Support/Polka/rates.json` | Public data, only if rates are turned on. |
| Settings and scenarios | `~/Library/Preferences/io.github.romabmstu.Polka.plist` | Standard app preferences. |
| Clipboard history | Memory only | Never written to disk; gone when Polka quits. |
| Files on the shelf | Memory only | Polka keeps references, it never copies or moves your files. |

## Network

Polka makes one kind of request: when you turn on currency conversion, it downloads public exchange rates from `https://open.er-api.com` (operated by ExchangeRate-API) a few times a day. The request carries no identifiers, cookies or personal data. Nothing else goes over the network. Polka does not download site icons, so the sites you save never see a request from it.

## Permissions

Polka asks for each permission only when you use the feature that needs it.

| Permission | Why |
| --- | --- |
| Automation › Safari | Read the address and title of open tabs to save them; open a group in a new window. |
| Calendars | Show today’s events and the next meeting. Read-only. |
| Accessibility | Send the media play/pause and track keys. Polka does not read the screen or other apps’ content. |

VPN switching uses the system `scutil` tool and needs no permission. Global shortcuts use the Carbon hot key API, which sees only Polka’s own key combinations — Polka does not monitor your typing.

## Clipboard

When clipboard history is on, Polka checks the pasteboard twice a second for new text. Content that password managers mark as concealed or transient (see [nspasteboard.org](http://nspasteboard.org)) is skipped without being read. History is kept in memory only.
