#!/bin/bash
# Signs a built Polka.app, zips it and writes the signed update.json.
#
#   scripts/package.sh <Polka.app> <stable|beta> <release-tag> <out-dir>
#
# Optional environment:
#   CODESIGN_P12_BASE64, CODESIGN_P12_PASSWORD  re-sign with the project certificate
#   UPDATE_SIGNING_KEY                          Ed25519 seed matching the app public key
set -euo pipefail

app="$1"; channel="$2"; tag="$3"; out="$4"
mkdir -p "$out"

info="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")

# Re-signs with the project certificate so every build keeps the same code
# identity and macOS remembers its permissions across updates. Returns
# non-zero instead of silently changing the application's signing identity.
sign_with_certificate() {
  local p12="$RUNNER_TEMP/polka.p12"
  local keychain="$RUNNER_TEMP/polka-signing.keychain-db"
  local keychain_password p12_password item
  keychain_password=$(uuidgen)
  # Secrets pasted from a text file may carry line breaks, spaces, quotes or
  # a URL-safe alphabet; keep only what base64 allows and pad it.
  if ! printf '%s' "$CODESIGN_P12_BASE64" | python3 -c '
import base64, re, sys
text = sys.stdin.read().replace("-", "+").replace("_", "/")
data = re.sub(r"[^A-Za-z0-9+/]", "", text)
sys.stdout.buffer.write(base64.b64decode(data + "=" * (-len(data) % 4)))
' > "$p12" || [[ ! -s "$p12" ]]; then
    echo "CODESIGN_P12_BASE64 could not be decoded (${#CODESIGN_P12_BASE64} characters)"
    rm -f "$p12"
    return 1
  fi
  p12_password=$(printf '%s' "${CODESIGN_P12_PASSWORD:-}" | tr -d '\r\n')

  security create-keychain -p "$keychain_password" "$keychain" || return 1
  security set-keychain-settings -lut 900 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain" || return 1
  if ! security import "$p12" -k "$keychain" -P "$p12_password" -T /usr/bin/codesign; then
    echo "The certificate did not import: CODESIGN_P12_PASSWORD may not match ($(wc -c < "$p12" | tr -d ' ') bytes decoded)"
    rm -f "$p12"
    security delete-keychain "$keychain"
    return 1
  fi
  rm -f "$p12"
  security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
  security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')

  local identity="Polka Code Signing" status=0
  # Inside out: the embedded framework first, then the app.
  for item in "$app"/Contents/Frameworks/*.framework; do
    if [[ -e "$item" ]]; then
      codesign --force --options runtime --timestamp=none --keychain "$keychain" --sign "$identity" "$item" || status=1
    fi
  done
  if [[ $status -eq 0 ]]; then
    codesign --force --options runtime --timestamp=none --keychain "$keychain" \
      --entitlements App/Polka.entitlements --sign "$identity" "$app" || status=1
  fi
  security delete-keychain "$keychain"
  return $status
}

if [[ -z "${CODESIGN_P12_BASE64:-}" ]] || ! sign_with_certificate; then
  echo "::error title=Signing failed::The project certificate is missing or could not be used; refusing to publish a build with a different identity."
  exit 1
fi
echo "Signed with the project certificate"
codesign --verify --deep --strict "$app"

name="Polka-$version-$build.zip"
ditto -c -k --keepParent "$app" "$out/$name"

# A disk image for people: drag Polka onto Applications. The zip above stays
# the format the in-app updater uses. The image has a fixed name so
# releases/latest/download/Polka.dmg always points at the newest one.
# Designed window when dmgbuild is available (CI installs it), plain image
# otherwise; either way the disk image is never what fails a release.
#
# Mounts the image and checks what a user would get: a validly signed app and
# the Applications link.
dmg_is_sound() {
  local mount status=0
  mount=$(mktemp -d)
  hdiutil attach "$out/Polka.dmg" -nobrowse -readonly -mountpoint "$mount" >/dev/null || { rmdir "$mount"; return 1; }
  codesign --verify --deep --strict "$mount/Polka.app" || status=1
  [[ -L "$mount/Applications" ]] || status=1
  hdiutil detach "$mount" -force >/dev/null || true
  rmdir "$mount" 2>/dev/null || true
  return $status
}

if command -v dmgbuild >/dev/null 2>&1; then
  background="$(mktemp -d)/background.tiff"
  if tiffutil -cathidpicheck scripts/dmg/background.png scripts/dmg/background@2x.png -out "$background" >/dev/null 2>&1 &&
    dmgbuild -s scripts/dmg/settings.py -D app="$app" -D background="$background" Polka "$out/Polka.dmg" >/dev/null &&
    dmg_is_sound; then
    echo "Built the designed disk image"
  else
    rm -f "$out/Polka.dmg"
    echo "::warning title=Plain disk image::dmgbuild failed; publishing a plain disk image instead."
  fi
  rm -rf "$(dirname "$background")"
fi
if [[ ! -f "$out/Polka.dmg" ]]; then
  dmg_root="$(mktemp -d)/Polka"
  mkdir -p "$dmg_root"
  ditto "$app" "$dmg_root/Polka.app"
  ln -s /Applications "$dmg_root/Applications"
  for attempt in 1 2 3; do
    # hdiutil occasionally reports "Resource busy" on CI runners; retry.
    if hdiutil create -volname Polka -srcfolder "$dmg_root" -fs HFS+ -format UDZO -ov "$out/Polka.dmg" >/dev/null; then
      break
    fi
    rm -f "$out/Polka.dmg"
    sleep $((attempt * 5))
  done
  rm -rf "$(dirname "$dmg_root")"
fi
if [[ -f "$out/Polka.dmg" ]] && ! { hdiutil verify "$out/Polka.dmg" >/dev/null && dmg_is_sound; }; then
  rm -f "$out/Polka.dmg"
fi
if [[ -f "$out/Polka.dmg" ]]; then
  shasum -a 256 "$out/Polka.dmg" > "$out/Polka.dmg.sha256"
  echo "dmg=Polka.dmg" >> "${GITHUB_OUTPUT:-/dev/null}"
else
  echo "::warning title=No disk image::The disk image could not be built or did not verify; the zip is still published."
fi

git log -1 --format='%s%n%n%b' > "$out/notes.txt"
# Never publish an update the installed app cannot authenticate.
export EXPECTED_UPDATE_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :PolkaUpdatePublicKey' "$info")
if ! swift scripts/make-update-manifest.swift "$out/$name" "$version" "$build" "$channel" \
  "https://github.com/romabmstu/polka/releases/download/$tag/$name" "$minimum" "$out/notes.txt" \
  > "$out/update.json"; then
  rm -f "$out/update.json"
  echo "::error title=Update signing failed::The signing key is missing, invalid, or does not match the public key in the app."
  exit 1
fi
shasum -a 256 "$out/$name" > "$out/$name.sha256"
echo "name=$name" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "version=$version" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "build=$build" >> "${GITHUB_OUTPUT:-/dev/null}"
