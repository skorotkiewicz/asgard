# Asgard

A turn-based roguelike set across the Nine Realms of Norse mythology, written in [Odin](https://odin-lang.org) using [raylib](https://www.raylib.com).

## Status

Playable end-to-end prototype. Currently: procedurally generated dungeons across all Nine Realms via Yggdrasil descent, each with its own palette, music, and enemy mix; draugr, jotnar, hounds, trolls, and wraiths hunt you depending on realm; Fenrir, Jormungandr, and Surtr guard deeper stairs; **Hel waits in Helheim — defeat her to win**; field-of-view-limited vision with explored memory; mead, runes of fire, and runes of sight scattered across the world; pack (6 slots) persists between realms.

## Source layout

All files are in the same `asgard` package, so cross-file references are free.

| File              | Concern                                                |
|-------------------|--------------------------------------------------------|
| `src/main.odin`   | Entry point, window setup, game loop                   |
| `src/game.odin`   | Types (Tile / Realm / Entity / Room / Game), lifecycle, input/turn loop |
| `src/worldgen.odin` | Seeded map generation: rooms, corridors, enemy spawn |
| `src/combat.odin` | Entity factories, combat math, enemy AI                |
| `src/fov.odin`    | Recursive shadowcasting field of view                  |
| `src/items.odin`  | Item kinds, pickup, use effects                        |
| `src/menu.odin`   | Esc-opened pause menu                                  |
| `src/audio.odin`  | Procedurally-synthesized SFX (no asset files)          |
| `src/music.odin`  | Per-realm looping drone music, also synthesized        |
| `src/render.odin` | Palette and all raylib drawing                         |

## Build

Requires `odin` on PATH (raylib ships in `vendor:raylib` — no extra install).

```sh
./build.sh run        # build + launch
./build.sh debug      # debug build only
./build.sh release    # optimized build
```

## Controls

| Key                       | Action                       |
|---------------------------|------------------------------|
| Arrows / `h j k l`        | Move one tile                |
| `y u b n`                 | Diagonal move                |
| `.`                       | Wait one turn                |
| `1`–`6`                   | Use that pack slot           |
| `F5`                      | Save the current run         |
| `F9`                      | Load the saved run           |
| `R`                       | Restart from Midgard (full HP, empty pack) |
| `Esc`                     | Open menu (Resume / New Game / Exit) |

## Roadmap

- [x] Tile grid + walls + player movement
- [x] Turn counter, message log
- [x] Procedural map generation (rooms + corridors)
- [x] First enemy + bump combat (draugr with greedy chase AI)
- [x] Field of view (recursive shadowcasting, explored memory)
- [x] Stairs between the Nine Realms via Yggdrasil (per-realm palette + flavor)
- [x] Items + inventory (mead heals; rune of fire burns visible foes; rune of sight reveals map)
- [x] Hit flash + screen shake + procedurally-synthesized SFX
- [x] Per-realm background music (looping drones with realm-specific tonality)
- [x] More enemies — jotnar (slow tanks) and Hel's hounds (fast packs) with realm-weighted spawn tables
- [x] Bosses + victory condition — Hel guards Helheim; defeating her ends Ragnarok
- [x] Even more enemies (trolls, wraiths) and realm-end mini-bosses (Fenrir, Surtr, Jormungandr)
- [ ] More item kinds (weapons, armor, throwing axes, scrolls of recall)
- [x] Bosses (Fenrir, Jormungandr, Surtr, Hel)
- [x] Saving / loading
