# Changelog

## 1.0.0.4 — 2026-09-27

- First release with a user-confirmed working named scroll menu and resurrection beside the caster.
- Support both native inventory callback argument formats.
- Wait until the Flash menu is initialized before capturing its invokes.
- Handle UI callbacks in the Before phase so asynchronous replies preserve the menu context.
- Validate character ownership using the network connection part of the player ID.
- Display Revive [name], with visible feedback for timeout and ownership errors.
- Include 22 automated behavioral tests and independently verified package contents.

Remote-client co-op and combat behavior still need live testing.

## Earlier local test builds

1.0.0.2 corrected mod discovery through metadata/package compatibility changes.
1.0.0.3 corrected inventory item arguments and delayed Flash initialization.
Neither was a working public release of the complete menu flow.
