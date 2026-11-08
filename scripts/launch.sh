#!/bin/bash
# Prepares the GitHub page for visitors and publishes a stable release:
#   1. description, website, topics and Discussions for the repository,
#   2. pushes main and waits for CI to pass,
#   3. tags the version and waits for the release with Polka.dmg.
#
#   scripts/launch.sh [version]      # default: MARKETING_VERSION from Config/Base.xcconfig
#
# Needs the GitHub CLI signed in; scripts/bootstrap.sh sets that up.
set -euo pipefail

repo="romabmstu/polka"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
command -v gh >/dev/null 2>&1 || export PATH="$HOME/.local/gh/bin:$PATH"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || fail "GitHub CLI not found. Run scripts/bootstrap.sh first."
gh auth status -h github.com >/dev/null 2>&1 || gh auth login -h github.com -p https -w -s repo,workflow
gh auth setup-git -h github.com

version="${1:-$(sed -n 's/^MARKETING_VERSION *= *//p' Config/Base.xcconfig | tr -d ' ')}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version '$version' is not X.Y.Z"
tag="v$version"

# 1. How the repository looks to visitors
say "Updating the repository page…"
gh repo edit "$repo" \
  --description "Your MacBook’s notch, finally useful: tabs from any browser, VPNs, music, calendar, translator and clipboard in one panel. Free and open source." \
  --homepage "https://romabmstu.github.io/polka/" \
  --enable-discussions --enable-issues \
  --add-topic macos,notch,menu-bar,macbook,swift,swiftui,productivity,vpn,tab-manager,dynamic-island,open-source,translator
echo "Description, website, topics and Discussions are set."

# 2. Main must be pushed and green before tagging
say "Pushing main…"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "Switch to main first."
git push origin main
sha=$(git rev-parse HEAD)

wait_for_run() { # workflow, commit
  local id=""
  for _ in $(seq 1 60); do
    id=$(gh run list -R "$repo" -w "$1" -c "$2" -L 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
    if [[ -n "$id" ]]; then break; fi
    sleep 5
  done
  [[ -n "$id" ]] || fail "No $1 run appeared for ${2:0:7}: https://github.com/$repo/actions"
  gh run watch "$id" -R "$repo" --exit-status --interval 15 >/dev/null ||
    fail "$1 failed: https://github.com/$repo/actions/runs/$id"
}

say "Waiting for CI on ${sha:0:7}…"
wait_for_run CI "$sha"
echo "CI passed."

# 3. Stable release
if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then
  say "$tag is already released: https://github.com/$repo/releases/tag/$tag"
else
  say "Tagging $tag…"
  if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    git tag -a "$tag" -m "Polka $version"
  fi
  git push origin "$tag"
  say "Waiting for the release build…"
  wait_for_run Release "$sha"
  echo "Released: https://github.com/$repo/releases/tag/$tag"
fi

say "Almost done — one thing GitHub only lets you do in the browser:"
echo "Settings › General › Social preview › Edit › upload docs/assets/og.png"
open "https://github.com/$repo/settings" 2>/dev/null || true
