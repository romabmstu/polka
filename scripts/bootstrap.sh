#!/bin/bash
# One-time setup on the maintainer's Mac, with signing files outside the clone:
#   1. installs the GitHub CLI if needed and signs in (in the browser),
#   2. uploads signing secrets from ~/PolkaSigning/ to the repository,
#   3. pushes local commits and waits for CI to publish the beta,
#   4. installs that beta into /Applications and switches Polka to the beta
#      channel, so every later push arrives as an in-app update.
#
#   scripts/bootstrap.sh
set -euo pipefail

repo="romabmstu/polka"
bundle_id="io.github.romabmstu.Polka"
root="$(cd "$(dirname "$0")/.." && pwd)"
signing_dir="${POLKA_SIGNING_DIR:-$HOME/PolkaSigning}"
cd "$root"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

for file in update-signing-key.txt codesign-p12-base64.txt codesign-p12-password.txt; do
  [[ -s "$signing_dir/$file" ]] || fail "Missing $signing_dir/$file"
done

# 1. GitHub CLI
# shellcheck source=lib/github-cli.sh
source "$root/scripts/lib/github-cli.sh"
ensure_github_cli

# 2. Secrets, read straight from the files so nothing is mistyped.
say "Uploading signing secrets…"
for pair in UPDATE_SIGNING_KEY:update-signing-key.txt CODESIGN_P12_BASE64:codesign-p12-base64.txt \
  CODESIGN_P12_PASSWORD:codesign-p12-password.txt; do
  name="${pair%%:*}"; file="${pair#*:}"
  tr -d '\r\n' < "$signing_dir/$file" | gh secret set "$name" -R "$repo"
done

# 3. Push and wait for the beta.
say "Pushing to GitHub…"
git push origin HEAD:main
sha=$(git rev-parse HEAD)

say "Waiting for the CI run of ${sha:0:7}…"
run_id=""
for _ in $(seq 1 60); do
  run_id=$(gh run list -R "$repo" -w CI -c "$sha" -L 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
  if [[ -n "$run_id" ]]; then break; fi
  sleep 5
done
[[ -n "$run_id" ]] || fail "No CI run appeared for $sha. Check https://github.com/$repo/actions"
gh run watch "$run_id" -R "$repo" --exit-status --interval 15 ||
  fail "The build failed: https://github.com/$repo/actions/runs/$run_id"

# 4. Install the beta.
say "Downloading the beta…"
tmp=$(mktemp -d)
name=$(gh release view nightly -R "$repo" --json assets --jq '.assets[].name' |
  perl -ne 'if (/^Polka-[A-Za-z0-9._-]+-(\d+)\.zip$/ && (!defined($n) || $1 > $n)) { $n=$1; $best=$_ } END { print $best if defined $best }')
[[ -n "$name" ]] || fail "No beta archive found on the release page."
gh release download nightly -R "$repo" -p "$name" -D "$tmp"
zip="$tmp/$name"
ditto -x -k "$zip" "$tmp/app"
[[ -d "$tmp/app/Polka.app" ]] || fail "The downloaded archive has no Polka.app"

say "Installing into /Applications…"
osascript -e 'tell application id "io.github.romabmstu.Polka" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 30); do
  pgrep -x Polka >/dev/null 2>&1 || break
  sleep 1
done
if pgrep -x Polka >/dev/null 2>&1; then
  fail "Polka is still running. Resolve any save error and close it before installing."
fi
for old in /Applications/Polka.app /Applications/Polka-2.app; do
  # To the Trash rather than deleted, in case anything needs to come back.
  if [[ -e "$old" ]]; then
    mv "$old" "$HOME/.Trash/$(basename "$old" .app) $(date +%H.%M.%S).app"
  fi
done
mv "$tmp/app/Polka.app" /Applications/Polka.app
xattr -dr com.apple.quarantine /Applications/Polka.app 2>/dev/null || true
rm -rf "$tmp"

defaults write "$bundle_id" updateChannel -string beta
defaults write "$bundle_id" checkForUpdatesAutomatically -bool true
open /Applications/Polka.app

say "Done. Polka $(defaults read /Applications/Polka.app/Contents/Info CFBundleShortVersionString) is running on the beta channel."
echo "From now on, every push to main shows up in the notch as an update."
