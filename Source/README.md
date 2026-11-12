# States 1.0.6 (build 7)

States is a macOS menu bar monitor for CPU, memory, disk, network traffic, battery, power, available temperature sensors, and local Codex usage.

## Requirements and installation

- macOS 26 or later on Apple Silicon (arm64).
- The downloadable app uses an ad-hoc signature and is not Apple-notarized. macOS may require approval on first launch.
- Download the release ZIP, extract it, and move `States.app` to Applications.

Open the menu bar panel to view metrics and settings. Sampling defaults to 2 seconds, with 1-, 2-, and 5-second options. Monitoring can be paused, and launch at login can be enabled in settings.

## Metrics and data

- System metrics come from local macOS interfaces. Network usage uses cumulative interface counters.
- Codex usage reads token statistics from `sessions` and `archived_sessions` under the local `CODEX_HOME` (default `~/.codex`). Quotas are queried through the installed Codex CLI's app-server account interface, which may access the network. Missing CLI or account information is displayed as unknown.
- Daily Codex totals use the `Asia/Shanghai` date boundary and cover local logs, rather than a cross-device billing total. Pausing monitoring also stops Codex usage monitoring.
- Settings are stored in local preferences. Export Current Status writes system and SMC metrics to a JSON file at the selected location.
- AppleSMC temperature and power sensor availability varies by model and macOS version. Missing readings and estimates are distinguished from measured zero values.
- The project has no separate telemetry-upload implementation.

## Updating and removing the app

Quit the old version before replacing the app. The new version can reuse existing preferences. Removing `States.app` leaves separately exported JSON files and system preference records in place. Launch at login can be disabled in settings.

## Build and test

Use Xcode or command-line tools with the macOS 26 SDK and a Swift 6 toolchain. From this directory, run:

```sh
./Build.command
swift test
```

The build script creates an ad-hoc-signed app. Dependencies are Apple system frameworks and the included CSMC interface code; there are no external Swift package dependencies.

The recorded local validation on 2026-11-09 passed 16 Swift tests, a release build, and `States --self-test`.

## Current limitations and next steps

Intel Macs and older macOS versions are not supported. Fresh-install, upgrade, permission, CLI account-query, and cross-model sensor testing remain incomplete. Further validation across supported Macs and Codex account states is the next development step.

## License and sources

Released under the [MIT license](LICENSE). Apple frameworks and third-party materials retain their respective rights.

The CSMC source credits the AppleSMC protocol research in exelban/stats. Dependency and source details are in [THIRD-PARTY.md](THIRD-PARTY.md).
