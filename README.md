# rize-mobile

iOS client for Rize-Clone with hybrid Screen Time tracking. Part of the [Rize-Clone](../README.md) master repo.

**The three-tier tracking model:** exact per-app usage is rendered on-device by a `DeviceActivityReport` extension and never leaves the device (Apple isolates that extension from network and shared storage). Approximate usage is captured by a `DeviceActivityMonitor` extension via threshold events, handed to the app through the App Group, and synced to the backend flagged `precision: approximate`. Manual timers and focus sessions are exact and sync fully.

## Stack

- **Swift**, **SwiftUI**; DeviceActivity + FamilyControls + ManagedSettings frameworks
- App Group: `group.com.rizeclone.shared` (Monitor extension → app handoff)
- GRDB or SwiftData local store; `BGAppRefreshTask` for periodic sync

## Entitlements

- `com.apple.developer.family-controls` — works in development with the capability enabled, but **App Store distribution requires Apple approval via their request form (typically weeks — see RIZ-20)**
- App Groups, Sign in with Apple, Background Tasks

## Configuration

Build-time settings live in `Config.example.xcconfig` (committed, safe defaults) and flow through `project.yml` → `Info.plist` → app code. To override a value locally without touching git-tracked files, copy `Config.example.xcconfig` to `Config.local.xcconfig` (gitignored) and edit it there — it's included automatically by `Config.example.xcconfig` and takes precedence. Run `make generate` after changing either file to regenerate the Xcode project.

| Setting | Where it lives | Default | Description |
|---|---|---|---|
| `RIZE_BACKEND_BASE_URL` | `Config.example.xcconfig` / `Config.local.xcconfig` → Info.plist key `RIZE_BACKEND_BASE_URL` | `http://localhost:8080` | Base URL of the sync/auth API (RIZ-46), read at runtime by `BackendConfigProvider.resolve()`. |
| `com.rizeclone.mobile.backendBaseURL` | `UserDefaults` (standard suite) | unset (falls through to the Info.plist value above) | Runtime override of the backend base URL for on-device QA/staging without a rebuild. Takes priority over the Info.plist/xcconfig value; see `BackendConfigProvider`. |

Coverage thresholds and other CI-only knobs (e.g. `COVERAGE_THRESHOLD` in the `Makefile`) are not app runtime configuration and stay in `Makefile`/CI workflow files.

## Documentation

- [Mobile architecture](../documentation/architecture-mobile.md)
- [Sync protocol](../documentation/sync-protocol.md)
- [API reference](../documentation/api-reference.md)
- [Security requirements](../documentation/security.md)

## Git flow

One Linear ticket (`RIZ-<n>`) → one branch `feat/RIZ-<n>-<slug>` (or `fix/`, `docs/`, `chore/`) → one PR titled `[RIZ-<n>] <summary>` into `main`, linking the ticket. Conventional Commits referencing `RIZ-<n>`.
