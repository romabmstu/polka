# Sourced by the maintainer scripts. Makes sure the GitHub CLI is installed
# and signed in, installing it with Homebrew or, without Homebrew, into
# ~/.local/gh. Expects say and fail to be defined.

ensure_github_cli() {
  command -v gh >/dev/null 2>&1 || export PATH="$HOME/.local/gh/bin:$PATH"
  if ! command -v gh >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      say "Installing the GitHub CLI with Homebrew…"
      brew install gh
    else
      say "Installing the GitHub CLI into ~/.local/gh…"
      install_github_cli_locally || fail "Could not install the GitHub CLI. Install it from https://cli.github.com and run this again."
    fi
  fi
  command -v gh >/dev/null 2>&1 || fail "The GitHub CLI did not install. Install it from https://cli.github.com and run this again."

  if ! gh auth status -h github.com >/dev/null 2>&1; then
    say "Sign in to GitHub: copy the one-time code shown below, then paste it in the browser window that opens…"
    gh auth login -h github.com -p https -w -s repo,workflow
  fi
  gh auth setup-git -h github.com
}

# Downloads the official build for this Mac's processor. The version comes from
# the redirect of releases/latest, so no API call (and no rate limit) is needed.
install_github_cli_locally() {
  local arch latest version url tmp binary
  case "$(uname -m)" in
    arm64) arch=arm64 ;;
    x86_64) arch=amd64 ;;
    *) echo "Unsupported processor: $(uname -m)" >&2; return 1 ;;
  esac
  latest=$(curl -fsSL -S -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest) || return 1
  version="${latest##*/v}"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unexpected GitHub CLI release address: $latest" >&2
    return 1
  fi
  url="https://github.com/cli/cli/releases/download/v$version/gh_${version}_macOS_${arch}.zip"
  echo "Downloading $url"
  tmp=$(mktemp -d)
  if ! curl -fSL --progress-bar "$url" -o "$tmp/gh.zip" || ! ditto -x -k "$tmp/gh.zip" "$tmp/unpacked"; then
    rm -rf "$tmp"
    return 1
  fi
  binary=$(find "$tmp/unpacked" -path '*/bin/gh' -type f | head -1)
  if [[ -z "$binary" ]]; then
    echo "The download has no bin/gh inside." >&2
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$HOME/.local/gh"
  mkdir -p "$HOME/.local"
  mv "$(dirname "$(dirname "$binary")")" "$HOME/.local/gh"
  rm -rf "$tmp"
  "$HOME/.local/gh/bin/gh" --version | head -1
}
