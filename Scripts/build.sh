#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    macpulse_xcode_dir=$(/usr/bin/find /Applications -maxdepth 4 -path '*/Xcode.app/Contents/Developer' -print -quit)
    export DEVELOPER_DIR="${macpulse_xcode_dir:-$(xcode-select -p)}"
fi
if (( $# == 0 )); then set -- build; fi
xcodebuild -project MacPulse.xcodeproj -scheme MacPulse -configuration "${MACPULSE_CONFIGURATION:-Debug}" -destination 'platform=macOS,arch=arm64' -derivedDataPath build "$@"
