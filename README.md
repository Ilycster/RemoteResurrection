# Remote Resurrection — Scroll Menu

A mod for **Divinity: Original Sin 2 — Definitive Edition** that adds named revival
options to a Resurrection Scroll's right-click menu. Choose **Revive [character name]**
to bring a dead teammate beside the caster, even when the body is far away on the same map.
The normal **Cast skill** option remains available.

## Download and install

Current version: **1.0.0.4**. Download the `.pak` from the [latest release](https://github.com/Ilycster/RemoteResurrection/releases/latest).

1. Install [Norbyte's Script Extender v60 or later](https://github.com/Norbyte/ositools/releases).
2. Close the game and copy `RemoteResurrection_397de034-e6ad-4aad-8b89-1dbb7b5bda9a.pak` into:
   `Documents/Larian Studios/Divinity Original Sin 2 Definitive Edition/Mods`.
   Use the OneDrive Documents folder if your game stores its profiles there.
3. Enable **Remote Resurrection - Scroll Menu** in the main-menu Mods list.
4. Load your game, select the caster, and right-click a Resurrection Scroll in their inventory.

If you installed an earlier build named `RemoteResurrection.pak`, remove that old copy before
installing the UUID-named package. Do not keep duplicate packages for this mod.

## Behavior

- Lists eligible dead teammates on the same loaded map/region, without a distance or line-of-sight check.
- Revives the selected teammate near the caster. Stand in a clear area; the landing position may contain harmful surfaces.
- Costs one Resurrection Scroll and 3 AP during the caster's combat turn; revives at 20% vitality.
- Uses fixed AP and vitality values; talent discounts and resurrection bonuses are not reproduced.
- Shows a disabled message when there are no eligible dead teammates.
- Invalid or stale selections spend nothing. Failed/timed-out transactions are designed to refund costs.

Windows, keyboard and mouse, and the original Story campaign are supported. Controller menus,
split-screen, custom campaigns, and mods replacing inventory/context menus are not supported.
This does not retrieve characters from previous acts or unloaded regions, and excludes summons,
NPCs and characters blocked from resurrection. No LeaderLib dependency is required.
For co-op testing, install the same package and Script Extender on every participating PC.

## Validation

The basic named menu and successful revival beside the caster were confirmed in-game on
2026-09-27 with build 1.0.0.4. The 22 automated tests execute the Lua scripts with simulated
engine APIs; the package was independently unpacked and compared byte-for-byte with the source.

Remote-client co-op, combat AP charging, failure refunds and broad mod compatibility still need
live testing. See [VALIDATION.json](VALIDATION.json) for the exact scope and
[TECHNICAL-NOTES.md](TECHNICAL-NOTES.md) for implementation details.

## Source, tests and rebuilding

The original Lua code is in `source/Mods/RemoteResurrection_397de034-e6ad-4aad-8b89-1dbb7b5bda9a/Story/RawFiles/Lua`.
`source/Projects/RemoteResurrection` contains editor project metadata.

Run the behavior tests with Python and the `lupa` package:

```sh
python -m pip install lupa
python tests/test_mod.py
```

Build on Windows with PowerShell and [LSLib 1.15.15](https://github.com/Norbyte/lslib/releases/tag/v1.15.15):

```powershell
.\Build.ps1 -DivinePath 'C:\Tools\LSLib\divine.exe'
```

The build uses PAK v13 with the AllowMemoryMapping flag. LSLib and game assets are not bundled.
Checksums for the distributed files are in `SHA256.json`.

## Steam Workshop

The mod has not been published to Steam Workshop yet. [STEAM-WORKSHOP.md](STEAM-WORKSHOP.md)
describes how to open the source in the Definitive Edition editor and publish it.
Keep the module UUID unchanged when publishing updates.

## License

Original mod code is available under the [MIT license](LICENSE.txt).
See [CHANGELOG.md](CHANGELOG.md) for release notes.
