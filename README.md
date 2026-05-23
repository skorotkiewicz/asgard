# Asgard

A turn-based roguelike set across the Nine Realms of Norse mythology, written in [Odin](https://odin-lang.org) using [raylib](https://www.raylib.com).

## Status

Early prototype. Currently: a single chamber in Midgard, one wandering hero, no enemies, no items, no real Yggdrasil yet.

## Build

Requires `odin` on PATH (raylib ships in `vendor:raylib` — no extra install).

```sh
./build.sh run        # build + launch
./build.sh debug      # debug build only
./build.sh release    # optimized build
```

## Controls

| Key                       | Action          |
|---------------------------|-----------------|
| Arrows / `h j k l`        | Move one tile   |
| `y u b n`                 | Diagonal move   |
| `.`                       | Wait one turn   |
| `Esc` / `q`               | Quit            |

## Roadmap

- [x] Tile grid + walls + player movement
- [x] Turn counter, message log
- [ ] Procedural map generation (rooms + corridors)
- [ ] Field of view (shadowcasting)
- [ ] Enemies + combat (draugr, jotnar, trolls)
- [ ] Items + inventory (runes, mead, weapons)
- [ ] Stairs between the Nine Realms via Yggdrasil
- [ ] Bosses (Fenrir, Jormungandr, Surtr, Hel)
- [ ] Saving / loading
