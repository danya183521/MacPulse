#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    macpulse_xcode_dir=$(/usr/bin/find /Applications -maxdepth 4 -path '*/Xcode.app/Contents/Developer' -print -quit)
    export DEVELOPER_DIR="${macpulse_xcode_dir:-$(xcode-select -p)}"
fi
mkdir -p .research Evidence
xcrun clang -fobjc-arc -fmodules -framework Foundation -framework IOKit -framework CoreWLAN -framework SystemConfiguration -I Sources/PrivateSensors Sources/PrivateSensors/MPNativeSensors.m Sources/PrivateSensors/MPNetworkCounters.m Scripts/probe.m -o .research/probe
xcrun clang -fobjc-arc -framework Foundation -framework IOKit Scripts/smc-audit.m -o .research/smc-audit
xcrun clang -fobjc-arc -framework Foundation Scripts/energy-audit.m -o .research/energy-audit
xcrun clang -fobjc-arc -framework Foundation Scripts/hid-probe.m -o .research/hid-probe
xcrun swiftc Scripts/gpu-load.swift -o .research/gpu-load
