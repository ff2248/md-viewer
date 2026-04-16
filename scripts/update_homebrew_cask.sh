#!/bin/bash
set -euo pipefail

# Update the Homebrew cask in ff2248/homebrew-mdviewer.
# Used by release.yml after DMG upload.
#
# Usage: scripts/update_homebrew_cask.sh <version> <sha256>
#   version  — semver without "v" prefix (e.g. 1.0.2)
#   sha256   — hex digest of the DMG

VERSION="${1:?Usage: scripts/update_homebrew_cask.sh <version> <sha256>}"
SHA256="${2:?Usage: scripts/update_homebrew_cask.sh <version> <sha256>}"

command -v brew >/dev/null || { echo "Error: brew not found"; exit 1; }
command -v git >/dev/null || { echo "Error: git not found"; exit 1; }

REPO="git@github.com:ff2248/homebrew-mdviewer.git"
WORK_DIR=/tmp/tap
trap 'rm -rf "$WORK_DIR"' EXIT

rm -rf "$WORK_DIR"
git clone "$REPO" "$WORK_DIR"
cd "$WORK_DIR"
mkdir -p Casks

{
  printf 'cask "mdviewer" do\n'
  printf '  version "%s"\n' "$VERSION"
  printf '  sha256 "%s"\n' "$SHA256"
  cat << 'CASK'

  url "https://github.com/ff2248/md-viewer/releases/download/v#{version}/MDViewer-v#{version}.dmg"
  name "MDViewer"
  desc "Minimal Markdown viewer with Quick Look support"
  homepage "https://github.com/ff2248/md-viewer"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "MDViewer.app"

  zap trash: [
    "~/Library/Containers/io.github.ff2248.MDViewer.QuickLook",
    "~/Library/HTTPStorages/io.github.ff2248.MDViewer",
    "~/Library/Preferences/io.github.ff2248.MDViewer.plist",
    "~/Library/Saved Application State/io.github.ff2248.MDViewer.savedState",
  ]
end
CASK
} > Casks/mdviewer.rb

HOMEBREW_NO_AUTO_UPDATE=1 brew style --fix Casks/mdviewer.rb

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add Casks/mdviewer.rb
git diff --cached --quiet || { git commit -m "Update MDViewer to ${VERSION}" && git push; }
