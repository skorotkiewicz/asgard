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

| Key                       | Action                       |
|---------------------------|------------------------------|
| Arrows / `h j k l`        | Move one tile                |
| `y u b n`                 | Diagonal move                |
| `.`                       | Wait one turn                |
| `R`                       | Regenerate the map (new seed)|
| `Esc` / `q`               | Quit                         |

## Roadmap

- [x] Tile grid + walls + player movement
- [x] Turn counter, message log
- [x] Procedural map generation (rooms + corridors)
- [x] First enemy + bump combat (draugr with greedy chase AI)
- [ ] Field of view (shadowcasting)
- [ ] More enemies (jotnar, trolls, Hel's hounds)
- [ ] Items + inventory (runes, mead, weapons)
- [ ] Stairs between the Nine Realms via Yggdrasil
- [ ] Bosses (Fenrir, Jormungandr, Surtr, Hel)
- [ ] Saving / loading
