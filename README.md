# MacPulse

MacPulse is a native macOS system monitor for Apple Silicon Macs. It combines a compact Menu Bar monitor with a detailed SwiftUI dashboard, local history, alerts, and a Mac Health Engine.

MacPulse is built with Swift, SwiftUI, AppKit, Charts, WidgetKit, IOKit, Mach APIs, Network/SystemConfiguration, and small native Objective-C bridges where macOS exposes hardware data. It has no Electron, web runtime, third-party runtime dependencies, account system, or backend.

## Features

- CPU: total and per-core activity where available, cluster information, temperature, and power.
- GPU: utilization, temperature, memory, and power where available.
- Neural Engine: ANE power channel, status, rolling average, peak, and bounded history when the Mac exposes the IOReport channel.
- Memory: physical, used, available, wired, compressed, cached, swap, and memory pressure.
- Thermals: CPU/GPU and other named thermal sensors with honest unavailable states.
- Battery: charge, charging state, health, cycles, capacity, temperature, voltage, current, power, and estimates where supported.
- Power: CPU, GPU, ANE, compute, package/system, and adapter values are kept separate and labelled by their actual source.
- Network: download/upload rates, active interface, local address, and Wi-Fi details where macOS permits access.
- Storage: capacity, used/free space, volumes, and disk activity.
- Processes: read-only CPU, memory, disk, wakeup, and MacPulse Energy Score data with search, sorting, and filters.
- Mac Health Engine: explainable local health conditions for compute, memory, thermals, battery, and storage with duration, hysteresis, baseline, recovery, and recommendations.
- Menu Bar monitoring: user-selectable metrics, saved order, compact formatting, and an overflow indicator when the Menu Bar is full.

## Local-only and privacy

MacPulse is local-only. System metrics, history, preferences, and health analysis stay on the Mac. The application does not send telemetry, metrics, analytics, crash payloads, or personal data to a server. The optional diagnostic scripts in `Scripts/` are separate from the application; one optional network comparison script can make a request when explicitly run by the developer.

## Requirements

- macOS 14.0 or later.
- Xcode with a macOS 14 SDK or newer for building from source.
- Apple Silicon is the primary supported and tested platform.

Intel Macs may be able to compile the project, but Apple Silicon sensor coverage and hardware-specific readings are not validated there. Some metrics also depend on the Mac model, macOS version, permissions, power state, and whether a particular sensor or private IOReport channel is exposed. Missing data is shown as unavailable; it is not replaced with a guessed value.

## Download a release

After the public repository is connected, download `MacPulse-1.0.0.zip` from the repository's GitHub Releases page and move `MacPulse.app` to `Applications`.

The first downloadable artifact is a local ad-hoc build. It is not Developer ID signed, notarized, or distributed through the Mac App Store. macOS may require the user to approve the first launch in Privacy & Security or by using Open from the Finder context menu.

## Build from source

1. Clone the repository.
2. Open `MacPulse.xcodeproj` in Xcode.
3. Select the `MacPulse` scheme and `My Mac` destination.
4. Choose Debug or Release and press Run.

The included script keeps the Xcode selection local to the command:

```sh
./Scripts/build.sh
MACPULSE_CONFIGURATION=Release ./Scripts/build.sh build
MACPULSE_CONFIGURATION=Release ./Scripts/build.sh test
```

The script uses `DEVELOPER_DIR` when it is set, detects an installed `Xcode.app` under `/Applications`, and otherwise falls back to `xcode-select`. If Xcode is installed elsewhere, set it for the command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build.sh
```

The project has no external package or file dependency. All application source, native bridges, icon resources, localizations, entitlements, tests, and the Xcode project are stored in this repository.

## Screenshots

Screenshots of the Dashboard, Menu Bar panel, Menu Bar monitoring, Mac Health Engine, and Settings will be attached to the GitHub release and added here as the public release page is created.

## Architecture

```text
Native sensors and system APIs
            ↓
      SensorWorker → Snapshot
            ↓
      SamplingEngine
       ├── bounded history → Charts
       ├── Menu Bar and Quick Panel
       ├── Dashboard and Settings
       ├── Mac Health Engine and alerts
       └── optional WidgetKit snapshot
```

The UI does not read sensors directly. Sampling is centralized, history is bounded in memory, unavailable readings stay unavailable, and the Processes screen uses a separate read-only sampler only while that screen is open.

## Known limitations

- Hardware sensor names, units, and availability can change between Mac models and macOS releases.
- Several readings use undocumented or private macOS interfaces and may become unavailable after a system update.
- ANE currently reports a power line when available; it does not claim to be ANE utilization, frequency, or workload attribution.
- IOReport values represent the exposed energy model and are not laboratory-calibrated wall-power measurements.
- WidgetKit's shared App Group path requires a valid Apple Development identity and matching entitlements; it is outside the unsigned/ad-hoc release boundary.
- Launch at Login and notification delivery depend on macOS user consent.
- This release is not Developer ID signed, notarized, or an App Store submission.

## License

No license has been selected for this repository yet. Until a `LICENSE` file is added, all rights remain with the copyright holder. For this local-only utility, the recommended choice is the MIT License; it should be added explicitly before public publication.

## Disclaimer

MacPulse is an informational monitoring tool. Hardware metrics can depend on the Mac model, Apple Silicon generation, macOS version, power source, permissions, thermal state, and the sensors exposed by the system. Values may be unavailable, delayed, or reported with different semantics on another Mac. Do not use MacPulse as the sole source for safety, hardware warranty, or power-management decisions.
