#!/bin/sh
# Run interactively: the official installer may request macOS administrator authentication.
set -eu
if [ "$(uname -s)" != Darwin ]; then
  echo 'This project supports macOS only.' >&2
  exit 1
fi
if command -v brew >/dev/null 2>&1; then
  brew --version
elif [ -x /usr/local/bin/brew ]; then
  /usr/local/bin/brew --version
elif [ -x /opt/homebrew/bin/brew ]; then
  /opt/homebrew/bin/brew --version
else
  installer=$(mktemp -t kcl-homebrew)
  trap 'rm -f "$installer"' EXIT HUP INT TERM
  if [ "$(uname -m)" = x86_64 ]; then
    # Upstream HEAD no longer installs Intel macOS. Pin the last pre-removal installer.
    echo 'Intel macOS is Homebrew Tier 3; using the last Intel-capable official installer.'
    /usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/f4aa1b1ca5b256954dbde0315455fb259cdfc45a/install.sh -o "$installer"
    actual=$(/usr/bin/shasum -a 256 "$installer")
    actual=${actual%% *}
    if [ "$actual" != 12479a24be3f5307eecac7cde670fad7118640f031229e964f544b1367b52a41 ]; then
      echo 'Homebrew installer checksum mismatch.' >&2
      exit 1
    fi
  else
    /usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"
  fi
  /bin/bash "$installer"
fi
printf '%s\n' 'Follow the official installer’s shell setup instructions, then run: brew install go'
