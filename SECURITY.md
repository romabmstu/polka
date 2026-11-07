# Security

## Reporting a vulnerability

Please do not open a public issue. Use [private vulnerability reporting](https://github.com/romabmstu/polka/security/advisories/new) instead. You will get a reply within a week. Fixes are released as soon as they are ready and credited in the release notes unless you prefer otherwise.

Only the latest release is supported.

## Design

Polka runs with your user’s privileges and touches sensitive things (browser tabs, VPN, calendar, clipboard), so it follows a few rules.

**No shell.** External tools (`scutil`, `osascript`, `shortcuts`) are started by absolute path with an argument list. Nothing is passed through `/bin/sh`, and the environment is reduced to a fixed `PATH` and locale.

**No string-built scripts.** AppleScript sources are constants. URLs and other values reach scripts only as `argv`, so a page address cannot change what runs.

**Validate everything that crosses a boundary.**
- Only `http`, `https` and `file` URLs are saved or opened; `javascript:`, `data:` and app schemes are rejected.
- VPN service IDs must be UUIDs before they reach `scutil`; shortcut names are length-limited and may not start with `-`.
- The calculator is a small parser over `Decimal`, not an evaluator; input is never executed. Nesting depth and exponent size are capped.
- Exchange-rate responses are size-limited, schema-checked and sanity-checked before use.

**Minimal network surface.** One optional HTTPS endpoint, an ephemeral `URLSession` with no cookies, cache or credentials, TLS 1.2 or later.

**Careful storage.** The library is written atomically with `0600` permissions in a `0700` folder. A file that fails to parse is moved aside instead of being overwritten, and a file written by a newer version is left untouched.

**Least privilege.** Hardened Runtime is on. The only entitlements are Apple Events and Calendars. Each system permission is requested when the related feature is first used.

**Supply chain.** No third-party runtime dependencies. CI uses GitHub-hosted runners with read-only tokens; releases are built in CI from tags and carry SHA-256 checksums and build provenance attestations.

## Known limitations

- Release builds are not notarized by Apple yet, so macOS cannot vouch for them. Verify the attestation (see README) or build from source.
- Polka is not sandboxed: the App Sandbox does not allow controlling other apps’ VPN configurations or sending media keys.
