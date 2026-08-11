# PR draft for upstream (issue #133: "2.0 Port?")

**Title:** Port to Factorio 2.1

**Body:**

This ports FactorioMaps to Factorio 2.x (tested end-to-end on 2.1.14, macOS arm64, with a Space Age save). Closes #133, fixes #116.

Verified by generating a two-snapshot timeline across 20 surfaces — Nauvis, Vulcanus, Fulgora, Gleba and 16 space platforms — in both day and night.

## Runtime API changes (2.0)
- `game.write_file` / `game.remove_path` → `helpers.*`
- `game.item_prototypes` / `game.recipe_prototypes` → `prototypes.*`
- `game.active_mods` → `script.active_mods`
- `flying-text` entity type no longer exists (no-path signs aren't entities anymore)
- entity type `player` → `character` in count filters
- `LuaEntity::active` is read-only for some 2.x types (e.g. plants) — surface freezing now skips those
- chart tag `SignalID.type` can be `nil` (= `"item"`) since 2.0
- `take_screenshot` gained `hide_clouds` / `hide_fog` — both enabled so 2.0's cloud/fog layers don't dirty tiles
- `connect_types`: `curved-rail` split into `curved-rail-a/b` + `half-diagonal-rail`; legacy + elevated rail types, ramps and supports added

## Data stage changes (2.0)
- `item-request-proxy` lost its `picture` property (it uses an alert icon now) — override guarded
- item subtypes enumerated via `defines.prototypes` instead of the hardcoded list
- alert-icon blanking moved to a guarded loop so a missing sprite doesn't crash

## Multi-surface capture fix (#116)
The surface loop only ever captured the first surface: after finishing one it set `fm.done`, so the game sat on the "finished capturing" screen while the script waited forever for the next `done.txt`. It now resets the tick counter while surfaces remain, so all surfaces are captured in a single launch.

## Web interface
- Surface selector rebuilt as two panels: planets left, space platforms right, each with the surface icon, the platform's in-game name and the planet it is stationed at. Rich text in platform names renders as icons.
- Info button (bottom left) opens map details, the player list with playtimes, the mod list and credits.
- Opengraph/Twitter card tags are filled in per map, so a shared link previews the Nauvis thumbnail plus snapshot, surface and mod counts.

## Python tooling
- macOS support: binary autodetection (standalone + Steam), user-data-folder detection, system libturbojpeg (`brew install jpeg-turbo`), app-bundle data dir for tag icons; Space Age DLC mods treated as built-in data mods
- `--all-surfaces`: capture every charted surface — visited planets and space platforms
- kill only the spawned factorio process instead of `killall` (#102)
- deprecated `pkg_resources` check replaced with plain imports (#123), setuptools requirement dropped
- fixed a latent crash in the API's `surface_set_hidden(surface, false)` path

`info.json` targets `factorio_version: 2.1` / v5.0.0; 1.1 users keep using the 4.4.0 release.

Windows and Linux code paths were kept intact but only macOS was tested — testers welcome.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
