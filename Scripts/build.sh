#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/work/Xcode.app/Contents/Developer}"
if (( $# == 0 )); then set -- build; fi
xcodebuild -project MacPulse.xcodeproj -scheme MacPulse -configuration "${MACPULSE_CONFIGURATION:-Debug}" -destination 'platform=macOS,arch=arm64' -derivedDataPath build "$@"
