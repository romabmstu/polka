#!/bin/bash
# Signs a built Polka.app, zips it and writes the signed update.json.
#
#   scripts/package.sh <Polka.app> <stable|beta> <release-tag> <out-dir>
#
# Optional environment:
#   CODESIGN_P12_BASE64, CODESIGN_P12_PASSWORD  re-sign with the project certificate
#   UPDATE_SIGNING_KEY                          sign update.json (required)
set -euo pipefail

app="$1"; channel="$2"; tag="$3"; out="$4"
mkdir -p "$out"

info="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")

if [[ -n "${CODESIGN_P12_BASE64:-}" ]]; then
  keychain="$RUNNER_TEMP/polka-signing.keychain-db"
  keychain_password=$(uuidgen)
  security create-keychain -p "$keychain_password" "$keychain"
  security set-keychain-settings -lut 900 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"
  # Secrets pasted from a text file often keep its trailing newline.
  p12_password=$(printf '%s' "${CODESIGN_P12_PASSWORD:-}" | tr -d '\r\n')
  printf '%s' "$CODESIGN_P12_BASE64" | tr -d '\r\n ' | base64 --decode > "$RUNNER_TEMP/polka.p12"
  if ! security import "$RUNNER_TEMP/polka.p12" -k "$keychain" -P "$p12_password" -T /usr/bin/codesign; then
    rm -f "$RUNNER_TEMP/polka.p12"
    security delete-keychain "$keychain"
    echo "Could not import the signing certificate: check CODESIGN_P12_BASE64 and CODESIGN_P12_PASSWORD" >&2
    exit 1
  fi
  rm -f "$RUNNER_TEMP/polka.p12"
  security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
  security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
  identity="Polka Code Signing"
  # Inside out: the embedded framework first, then the app.
  for item in "$app"/Contents/Frameworks/*.framework; do
    [[ -e "$item" ]] && codesign --force --options runtime --timestamp=none --keychain "$keychain" --sign "$identity" "$item"
  done
  codesign --force --options runtime --timestamp=none --keychain "$keychain" \
    --entitlements App/Polka.entitlements --sign "$identity" "$app"
  security delete-keychain "$keychain"
fi
codesign --verify --deep --strict "$app"

name="Polka-$version-$build.zip"
ditto -c -k --keepParent "$app" "$out/$name"

git log -1 --format='%s%n%n%b' > "$out/notes.txt"
swift scripts/make-update-manifest.swift "$out/$name" "$version" "$build" "$channel" \
  "https://github.com/romabmstu/polka/releases/download/$tag/$name" "$minimum" "$out/notes.txt" \
  > "$out/update.json"
shasum -a 256 "$out/$name" > "$out/$name.sha256"
echo "name=$name" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "version=$version" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "build=$build" >> "${GITHUB_OUTPUT:-/dev/null}"
