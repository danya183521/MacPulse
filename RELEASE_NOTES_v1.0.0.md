# MacPulse v1.0.0

## First public release

MacPulse is a native, local-only macOS monitor focused on Apple Silicon.

### Highlights

- CPU, GPU, Neural Engine, Memory, Thermals, Battery, Power, Network, Storage, and Processes monitoring.
- Mac Health Engine with explainable local conditions, history, recovery, and recommendations.
- Menu Bar monitoring with selectable metrics, saved order, and compact formatting.
- SwiftUI Dashboard, Quick Panel, settings, bounded charts, alerts, and local preferences.
- No telemetry, accounts, analytics SDK, backend, or web runtime.

### Supported systems

- macOS 14.0 or later.
- Apple Silicon is the supported and tested platform.
- Intel builds may compile, but sensor coverage is not validated.

### Known limitations

- Some hardware metrics depend on the Mac model and macOS version.
- A few sensors use undocumented/private macOS interfaces and can be unavailable after system updates.
- The first artifact is ad-hoc and is not Developer ID signed or notarized.
- WidgetKit shared-container runtime requires Apple Development signing and matching App Group entitlements.

### Installation

Download `MacPulse-1.0.0.zip` from the GitHub Release, unzip it, and move `MacPulse.app` to `Applications`. On the first launch, macOS may require approval in Privacy & Security or through Finder's Open command.

To build from source, open `MacPulse.xcodeproj` in Xcode or run `MACPULSE_CONFIGURATION=Release ./Scripts/build.sh build`.
