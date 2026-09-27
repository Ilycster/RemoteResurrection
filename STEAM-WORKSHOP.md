# Publishing Remote Resurrection to Steam Workshop

The download contains both the tested package (`RemoteResurrection_397de034-e6ad-4aad-8b89-1dbb7b5bda9a.pak`) and editable source.
The `.pak` is for local installation. The editor project is for creating and updating your Workshop listing.
**Build 1.0.0.4 passed an in-game menu and resurrection test. Remote-client co-op and combat behavior still need live testing.**

## 1. Set up the Definitive Edition editor

In Steam, enable DOS2's free **Divinity Engine 2 Data** DLC and install
**The Divinity Engine 2 Definitive Edition** from the Tools section of your library.
Run Steam under the account that will own the Workshop listing.

Point the editor at the game's **DefEd\Data** directory, typically:
`C:\Program Files (x86)\Steam\steamapps\common\Divinity Original Sin 2\DefEd\Data`.
Use your actual Steam library path if different. Do not point it at Classic's `Data` directory.

Larian's instructions:
- https://docs.larian.game/Setup:_Editor_Steam
- https://docs.larian.game/Definitive_Edition

## 2. Add the supplied project

Close the editor. Merge the two folders inside this download's **source** folder into **DefEd\Data**:

```text
DefEd\Data\
  Mods\
    RemoteResurrection_397de034-e6ad-4aad-8b89-1dbb7b5bda9a\
      meta.lsx
      OsiToolsConfig.json
      Story\RawFiles\Lua\...
  Projects\
    RemoteResurrection\
      meta.lsx
```

Reopen the editor and choose **RemoteResurrection** / **Remote Resurrection - Scroll Menu** in
the project browser. If it does not appear, first check that there is no extra `source` directory
between `DefEd\Data` and `Mods` / `Projects`.

Do not use **Import Project** for this source: Larian documents that button for converting Classic
projects and assigning new IDs. This project already targets Definitive Edition.

Keep the module UUID `397de034-e6ad-4aad-8b89-1dbb7b5bda9a` when publishing updates to this mod.

## 3. Set the listing information

Open **Project Settings**, then the **Publishing** tab:

1. Set the title to **Remote Resurrection - Scroll Menu**.
2. Replace **Your Steam name** with your author name.
3. Paste the text from `WORKSHOP-DESCRIPTION.txt` into the description.
4. Use **Open Thumbnail...** to select a screenshot showing the working resurrection dropdown.
5. Save the project settings.

Reference: https://docs.larian.game/Project_settings_window

The extender is a DLL dependency, not a Workshop mod. State its requirement in the description
and link to https://github.com/Norbyte/ositools/releases . Steam subscribing to this mod will not
install the extender for other players.

## 4. Publish privately and test

Open the editor's **Publish Project** window, select **Steam Workshop**, and choose **Private**
visibility for the first upload. Publish from your own Steam account and complete any Steam
Workshop agreement prompt it presents.

Larian documents local and Steam publishing, including Private, Friends Only and Public visibility:
https://docs.larian.game/Publish_project_window

Test the local `.pak` or the published download on a disposable save:

- Dead teammate on the far side of the map appears by name in the scroll menu.
- Selecting the name moves and revives only that teammate next to the caster.
- A stack of scrolls decreases by exactly one; the last scroll is handled correctly.
- In combat, another character's turn and fewer than 3 AP prevent casting.
- An invalid selection, closing the menu and no-dead-player case spend nothing.
- A second PC in co-op sees the correct names and can revive the host's dead companion.
- Reloading a save and changing maps do not leave stale menu entries.

When testing a Workshop copy, temporarily move the manually installed `.pak` out of the game's
Mods folder, so you can confirm which copy you are testing. Keep the copy supplied in this download.

## 5. Make the tested listing public

Once the game checks pass, set the Workshop item's visibility to Public or Friends Only.
For updates, edit the same project and publish again; preserve the publisher metadata and Workshop
item ID that the editor adds. A new project/UUID can create a separate listing instead of updating yours.

No Steam upload or account login has been performed as part of creating this package.
