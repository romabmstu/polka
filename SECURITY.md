# Security

## Reporting a vulnerability

Please do not open a public issue. Use [private vulnerability reporting](https://github.com/romabmstu/polka/security/advisories/new) instead. You will get a reply within a week. Fixes are released as soon as they are ready and credited in the release notes unless you prefer otherwise.

Only the latest release is supported.

## Design

Polka runs with your user’s privileges and touches sensitive things (browser tabs, VPN, calendar, clipboard), so it follows a few rules.

**No shell for user input.** External tools (`scutil`, `route`, `osascript`, `shortcuts`) are started by absolute path with an argument list. Arguments are not interpreted by a shell. The update relaunch uses a fixed shell script with the process ID and app path passed as positional arguments.

**No string-built scripts.** AppleScript sources are constants. URLs and other values reach scripts only as `argv`, so a page address cannot change what runs.

**Validate everything that crosses a boundary.**
- Only `http`, `https` and `file` URLs are saved or opened; `javascript:`, `data:` and app schemes are rejected.
- VPN service IDs must be UUIDs before they reach `scutil`; app bundle identifiers must look like `com.vendor.app`; shortcut names are length-limited and may not start with `-`; volume is clamped to 0–100.
- Links from the Services menu are taken from the selection's HTML or text and pass the same URL checks; nothing else on the pasteboard is used.
- The calculator is a small parser over `Decimal`, not an evaluator; input is never executed. Nesting depth and exponent size are capped.
- Exchange-rate responses are size-limited, schema-checked and sanity-checked before use.

**Minimal network surface.** HTTPS requests for update checks and optional exchange rates, using an ephemeral `URLSession` with no cookies, cache or credentials, TLS 1.2 or later. The optional Throne integration uses an authenticated encrypted TCP connection restricted to loopback; its control key is stored in Keychain.

**Careful storage.** The library is written atomically with `0600` permissions in a `0700` folder. Previous versions are kept in the adjacent `Recovery` folder. A file that fails to parse is moved aside instead of being overwritten, and a file written by a newer version is left untouched. Polka waits for pending library changes before quitting or installing an update; if saving fails, it reports the error and does not proceed.

**Least privilege.** Hardened Runtime is on. The only entitlements are Apple Events and Calendars. Each system permission is requested when the related feature is first used.

**Signed updates.** The update metadata and archive are verified against the embedded Ed25519 public key. Each update ships with an `update.json` holding its size, SHA-256 and an Ed25519 signature made in CI with a key kept in GitHub secrets. Polka has the public key built in and installs nothing that does not match; it also checks that the unpacked app has the same bundle identifier and a valid code signature. Downloads are only accepted from this repository's releases.

**Code identity.** Published builds require the project signing certificate; publication fails if it cannot be used. This keeps a consistent code identity across releases, although changing from an older ad hoc build may require granting permissions again. The self-signed certificate does not replace Apple notarization.

**Supply chain.** One vendored component: the [MediaRemote Adapter](Vendor/MediaRemoteAdapter) (BSD 3-Clause), pinned to a reviewed commit and built from source with the app; Polka runs it inside `/usr/bin/perl` with fixed arguments. No package-manager dependencies. GitHub Actions are pinned to commit SHAs. CI uses GitHub-hosted runners with permissions scoped per job; tagged releases carry SHA-256 checksums and build provenance attestations.

Maintainer signing files belong outside the checkout, by default in `~/PolkaSigning` with access restricted to the maintainer. `POLKA_SIGNING_DIR` overrides this location for `scripts/bootstrap.sh`. Back up the signing keys securely: replacing the update key without a migration would prevent installed copies from trusting new updates.

## Known limitations

- Release builds are not notarized by Apple yet, so macOS cannot vouch for them. Verify the attestation (see README) or build from source.
- Polka is not sandboxed: the App Sandbox does not allow controlling other apps’ VPN configurations or sending media keys.
