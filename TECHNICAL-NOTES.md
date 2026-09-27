# Implementation and validation

The user confirmed the basic menu and resurrection path in DOS2 with build 1.0.0.4.
Broader combat, multiplayer, and compatibility testing remains pending.

## Implementation

The client observes `openContextMenu` for keyboard/mouse inventory UI objects. The host returns a
fresh, filtered list from `DB_IsPlayer`. The client adds entries to the built-in context menu's
seven-value button array, and refreshes it when the host responds. Replies are correlated to
the currently open menu; a late response cannot open a dismissed menu.

A custom entry sends a single-use token and target UUID. The host checks player ownership,
inventory ownership, death, party membership, region, story-blocking tags, combat turn and AP
again. Client messages cannot nominate arbitrary actors or spend another user's scroll.

The host finds a nearby valid position, reserves one scroll and the AP cost, and teleports only
the selected corpse. Its `StoryEvent` completion triggers `CharacterResurrect`; the resurrection
event completes the transaction. A timeout refunds costs and restores the body's original position.
Pending jobs are included in extender persistent variables for recovery when a save is loaded.

Stock scrolls are recognized using internal stats/template identifiers containing both `scroll`
and `resurrect`, not translated item names. Overhauls that rename all of these internal identifiers
will need an explicit additional mapping in `Shared.lua`.

There are no new skills, root templates, global skill stat overrides, compiled story goals,
third-party UI assets, native DLLs, or embedded third-party runtime dependencies in the `.pak`.

## Automated validation

`tests/test_mod.py` executes the actual shipped Lua scripts under Lua 5.3 using engine mocks.
It covers a distant co-op teammate, named menus, no eligible targets, AP/turn restrictions,
invalid scrolls, stale menus, malformed messages, caller ownership, repeated requests,
failure refunds, transaction locks, and save/reload recovery. These are logic tests, not gameplay tests.

The package is built with the DOS2DE target in Norbyte's LSLib 1.15.15 and is extracted again
to compare every packaged file byte-for-byte with the source. Project metadata and configuration
are parsed as XML/JSON. Osiris call names and event arities are checked against the DOS2DE story header.

## Manual validation still required

- Additional menu focus and closure cases; the named dropdown now works in the live test.
- Matching the game's UserID to the extender network sender in host and remote sessions.
- The standard scroll's internal stats/template identifiers and nested inventory ownership.
- The engine's actual teleport and resurrection event timing, surfaces and combat transitions.
- In-game visual feedback, mod compatibility, editor project discovery and Workshop upload.

## Primary API and tooling references

- Norbyte Script Extender: https://github.com/Norbyte/ositools
- Lua loading and persistence: https://github.com/Norbyte/ositools/blob/master/Docs/LuaAPIDocs.md
- Current exposed API definitions: https://github.com/Norbyte/ositools/blob/master/ScriptExtender/Misc/ExtIdeHelpers.lua
- DOS2DE story header: https://gist.github.com/PinewoodPip/efa05ecbcf348f905824a6a127b0931e
- Larian teleport semantics: https://docs.larian.game/Osiris/API/TeleportToPosition
- Larian resurrection call: https://docs.larian.game/Osiris/API/CharacterResurrect
- Context-menu format reference in LeaderLib's author-maintained source:
  https://github.com/LaughingLeader-DOS2-Mods/LeaderLib/blob/master/Mods/LeaderLib_543d653f-446c-43d8-8916-54670ce24dd9/Story/RawFiles/Lua/Client/UI/ContextMenu.lua
- LSLib package tool: https://github.com/Norbyte/lslib/releases/tag/v1.15.15

LeaderLib was consulted to verify the native button array format; it is not required or bundled.
The mod implementation is original source.

## Native menu investigation, 2026-09-27

Build 1.0.0.2 was visible, but its menu did not appear. A captured game runtime log showed
GetItem receiving a character handle (factory 23, handle type 22), and CaptureInvokes running
before the Flash player existed. Local inspection of the native inventoryClass and container
UI confirmed the four-argument (owner, item, x, y) and three-argument (item, x, y) callbacks.
Build 1.0.0.3 handles both, retries deferred menu capture, and uses the Flash root function for
refresh. Native contextMenu.updateButtons consumes and replaces buttonArr; the tests now model
this behavior. Native game resources and runtime logs are for local diagnosis and are not
included in the source release.

## Callback phases and network ownership

Live build 1.0.0.3 logged two menu requests for one click and sender=65536 vs character
UserID/ReservedUserID=65537. Norbyte LuaClient.cpp confirms that UICall and UIInvoke both
dispatch Before and After through the same event. Build 1.0.0.4 filters to Before, which
preserves the original menu captured during the engine action. BaseTypes.h defines
UserId::GetPeerId as Id >> 16; ownership now uses that connection component and rejects
unassigned IDs. Tests model native callback nesting, both callback phases, distinct
network/player IDs, and denial of a different connection. These checks address observed
runtime defects, but do not by themselves confirm successful resurrection in-game.

## Successful in-game test, build 1.0.0.4

On 2026-09-27 the user reported success and supplied before/after screenshots showing
Revive Ifan ben-Mezd alongside Cast skill, then Ifan alive beside the caster with the
mod's completion message. This confirms the basic live menu, network request, teleport,
and resurrection path. Remote-client co-op, combat AP behavior, and refunds remain unverified
in the actual game. The screenshots and private runtime logs are not included in the release.
