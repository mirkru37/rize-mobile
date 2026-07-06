# rize-mobile

iOS client with hybrid Screen Time tracking. Stack: Swift, SwiftUI, DeviceActivity/FamilyControls/ManagedSettings, App Group `group.com.rizeclone.shared`, GRDB or SwiftData.

## Hard rules

- **Never attempt network calls or shared-container writes from the DeviceActivityReport extension.** Apple blocks both at the OS level; code that tries is an automatic HIGH-severity review finding. Exact usage data is display-only inside that extension (Tier A).
- All threshold-derived usage events (Tier B, from the DeviceActivityMonitor extension via App Group) must be flagged `precision: approximate` before sync, and the UI must label them as approximate.
- Keep extension targets minimal — no app-level dependencies compiled into extensions.

## Conventions

- Same Swift conventions as rize-desktop: MVVM with `@Observable`, async/await only, SwiftFormat + SwiftLint, XCTest.
- **Consult `../documentation/` before changing any contract.** Sync payload types mirror `api-reference.md` / `sync-protocol.md`; see `architecture-mobile.md` for the three-tier model.
- Tokens live in the Keychain, never UserDefaults. iOS Data Protection: `completeUntilFirstUserAuthentication` for the local store.

## Git flow

One Linear ticket (`RIZ-<n>`) → one branch `feat/RIZ-<n>-<slug>` (or `fix/`, `docs/`, `chore/`) → one PR `[RIZ-<n>] <summary>` into `main`, linking the ticket. Conventional Commits referencing `RIZ-<n>`. Never open a PR with failing tests or lint.
