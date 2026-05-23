# Asgard

A turn-based roguelike set across the Nine Realms of Norse mythology, written in [Odin](https://odin-lang.org) using [raylib](https://www.raylib.com).

## Status

Early prototype. Currently: procedurally generated dungeons across all Nine Realms via Yggdrasil descent, each with its own palette and flavor; draugr ambush from the shadows; field-of-view-limited vision with explored memory; mead, runes of fire, and runes of sight scattered across the world; pack (6 slots) persists between realms.

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
| `R`                       | Restart from Midgard (full HP, empty pack) |
| `Esc` / `q`               | Quit                         |

## Roadmap

- [x] Tile grid + walls + player movement
- [x] Turn counter, message log
- [x] Procedural map generation (rooms + corridors)
- [x] First enemy + bump combat (draugr with greedy chase AI)
- [x] Field of view (recursive shadowcasting, explored memory)
- [x] Stairs between the Nine Realms via Yggdrasil (per-realm palette + flavor)
- [x] Items + inventory (mead heals; rune of fire burns visible foes; rune of sight reveals map)
- [ ] More enemies (jotnar, trolls, Hel's hounds) — tougher in deeper realms
- [ ] More item kinds (weapons, armor, throwing axes, scrolls of recall)
- [ ] Bosses (Fenrir, Jormungandr, Surtr, Hel)
- [ ] Saving / loading
