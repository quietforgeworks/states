# States

States is a macOS menu bar monitor for system performance, power, and Codex usage.

## Features

- CPU, memory, disk, and network activity in one panel.
- Battery, power, and available temperature readings.
- Codex quota, recovery countdown, and local token usage.
- Adjustable glass appearance, including transparency, intensity, and color.
- JSON export of system and SMC metrics.

## Requirements and download

Requires **macOS 26 or later on Apple Silicon (arm64)**.

The source is at **1.0.6 (build 7)**. The current [release download](https://github.com/quietforgeworks/states/releases) is `States-1.0.3-macOS-arm64.zip`. Extract the ZIP and move `States.app` to Applications. Releases also include a source ZIP and SHA-256 checksums.

## Current limitations

- Sensor availability varies by Mac model and macOS version. Some readings are estimates; unavailable readings are distinct from zero.
- Codex token totals come from local session statistics, while quota queries use the installed Codex CLI account interface and may access the network. These are not a cross-device billing total.
- Distribution uses ad-hoc signing rather than Developer ID signing and Apple notarization, so macOS may block the first launch.
- Clean-install, upgrade, account-query, and broader hardware compatibility testing remain development work.

## Development directions

- Expand sensor and device compatibility.
- Improve Codex usage reporting and unavailable-data handling.
- Complete installation, upgrade, and permission testing for future releases.

## Build and documentation

Source and build scripts are in `Source/`. With an Xcode toolchain supporting the macOS 26 SDK, run `bash Build.command` from that directory.

See the [usage and build guide](Source/README.md) for sampling controls, data behavior, and detailed requirements.

## License

[MIT](LICENSE). Dependency and attribution information is in [THIRD-PARTY.md](Source/THIRD-PARTY.md).
