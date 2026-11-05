#!/usr/bin/env bash
# Renders the Homebrew formula (CLI) and cask (app) for a release and pushes them to SachsA/homebrew-tap.
# Usage: TAP_TOKEN=... scripts/update-tap.sh VERSION path/to/SHA256SUMS
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$1"
SUMS="$2"
APP_SHA="$(grep "Fidget-$VERSION.zip" "$SUMS" | cut -d' ' -f1)"
CLI_SHA="$(grep "fidget-cli-$VERSION.tar.gz" "$SUMS" | cut -d' ' -f1)"
TAP_DIR="$(mktemp -d)/homebrew-tap"

git clone --depth 1 "https://x-access-token:${TAP_TOKEN}@github.com/SachsA/homebrew-tap.git" "$TAP_DIR"
mkdir -p "$TAP_DIR/Formula" "$TAP_DIR/Casks"
render() { sed -e "s/__VERSION__/$VERSION/g" -e "s/__APP_SHA__/$APP_SHA/g" -e "s/__CLI_SHA__/$CLI_SHA/g" "$1" > "$2"; }
render packaging/homebrew/fidget.rb "$TAP_DIR/Formula/fidget.rb"
render packaging/homebrew/fidget-cask.rb "$TAP_DIR/Casks/fidget.rb"

cd "$TAP_DIR"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git commit -m "fidget $VERSION" || { echo "Tap already up to date"; exit 0; }
git push origin HEAD
