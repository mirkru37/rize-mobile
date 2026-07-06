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

## Documentation

- [Mobile architecture](../documentation/architecture-mobile.md)
- [Sync protocol](../documentation/sync-protocol.md)
- [API reference](../documentation/api-reference.md)
- [Security requirements](../documentation/security.md)

## Git flow

One Linear ticket (`RIZ-<n>`) → one branch `feat/RIZ-<n>-<slug>` (or `fix/`, `docs/`, `chore/`) → one PR titled `[RIZ-<n>] <summary>` into `main`, linking the ticket. Conventional Commits referencing `RIZ-<n>`.
