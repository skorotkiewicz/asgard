package asgard

import "core:math/rand"
import "core:time"

ROOM_MIN         :: 4
ROOM_MAX         :: 9
MAX_ROOMS        :: 14
PLACE_ATTEMPTS   :: 80
ENEMY_SPAWN_PCT  :: 55 // per non-starting room

// Weighted spawn tables per realm. Weight 0 (or omitted) means that kind
// never appears via random spawn. Bosses are placed deterministically
// elsewhere and so are never listed here — #partial lets us omit them.
realm_spawn_weights :: proc(r: Realm) -> [EnemyKind]int {
	switch r {
	case .Midgard:      return #partial {.Draugr = 10}                                             // intro: draugr only
	case .Asgard:       return #partial {.Draugr =  6, .Jotunn = 2, .Hound = 1, .Wraith = 1}
	case .Jotunheim:    return #partial {.Draugr =  2, .Jotunn = 5, .Hound = 1, .Troll = 3}          // giants' country
	case .Niflheim:     return #partial {.Draugr =  3, .Jotunn = 2, .Hound = 2, .Wraith = 4}         // mixed mist
	case .Muspelheim:   return #partial {.Draugr =  2, .Jotunn = 2, .Hound = 4, .Troll = 1, .Wraith = 1}
	case .Alfheim:      return #partial {.Draugr =  7, .Jotunn = 1, .Hound = 1, .Wraith = 2}         // lighter realm
	case .Svartalfheim: return #partial {.Draugr =  3, .Jotunn = 3, .Hound = 1, .Troll = 3, .Wraith = 1}
	case .Vanaheim:     return #partial {.Draugr =  3, .Jotunn = 2, .Hound = 2, .Troll = 2, .Wraith = 1}
	case .Helheim:      return #partial {.Draugr =  2, .Jotunn = 2, .Hound = 4, .Troll = 1, .Wraith = 3}
	}
	return #partial {.Draugr = 10}
}

realm_miniboss_kind :: proc(r: Realm) -> (EnemyKind, bool) {
	switch r {
	case .Midgard:      return .Draugr, false
	case .Asgard:       return .Fenrir, true
	case .Jotunheim:    return .Draugr, false
	case .Niflheim:     return .Jormungandr, true
	case .Muspelheim:   return .Surtr, true
	case .Alfheim:      return .Draugr, false
	case .Svartalfheim: return .Draugr, false
	case .Vanaheim:     return .Draugr, false
	case .Helheim:      return .Draugr, false
	}
	return .Draugr, false
}

pick_enemy_kind :: proc(weights: [EnemyKind]int) -> EnemyKind {
	total := 0
	for w in weights { total += w }
	if total <= 0 { return .Draugr }
	roll := rand.int_max(total)
	sum := 0
	for w, k in weights {
		sum += w
		if roll < sum { return k }
	}
	return .Draugr
}

// True if (x,y) is free for spawning a new enemy or item: walkable tile,
// not stairs, no existing enemy or item there.
spawnable :: proc(g: ^Game, x, y: int) -> bool {
	t := tile_at(g, x, y)
	if t == .Wall                  { return false }
	if t == .Stairs_Down           { return false }
	if enemy_at(g, x, y) != nil    { return false }
	if item_at(g, x, y) >= 0       { return false }
	return true
}

// Try to place a packmate of `kind` on any adjacent walkable tile.
try_spawn_packmate :: proc(g: ^Game, x, y: int, kind: EnemyKind) {
	for dx in -1 ..= 1 {
		for dy in -1 ..= 1 {
			if dx == 0 && dy == 0 { continue }
			nx := x + dx
			ny := y + dy
			if !spawnable(g, nx, ny) { continue }
			append(&g.enemies, make_enemy(kind, nx, ny))
			return
		}
	}
}

// ---- seed ------------------------------------------------------------------

fresh_seed :: proc() -> u64 {
	return u64(time.now()._nsec)
}

// ---- room helpers ----------------------------------------------------------

room_center :: proc(r: Room) -> (int, int) {
	return r.x + r.w / 2, r.y + r.h / 2
}

rooms_overlap :: proc(a, b: Room) -> bool {
	return a.x <= b.x + b.w &&
	       a.x + a.w >= b.x &&
	       a.y <= b.y + b.h &&
	       a.y + a.h >= b.y
}

carve_room :: proc(g: ^Game, r: Room) {
	for y in r.y ..< r.y + r.h {
		for x in r.x ..< r.x + r.w {
			set_tile(g, x, y, .Floor)
		}
	}
}

carve_h_corridor :: proc(g: ^Game, x1, x2, y: int) {
	a, b := min(x1, x2), max(x1, x2)
	for x in a ..= b { set_tile(g, x, y, .Floor) }
}

carve_v_corridor :: proc(g: ^Game, y1, y2, x: int) {
	a, b := min(y1, y2), max(y1, y2)
	for y in a ..= b { set_tile(g, x, y, .Floor) }
}

rand_in_range :: proc(lo, hi: int) -> int {
	// inclusive [lo, hi]
	return lo + rand.int_max(hi - lo + 1)
}

// ---- generator -------------------------------------------------------------

generate_map :: proc(g: ^Game, seed: u64) {
	rand.reset(seed)
	g.seed = seed

	// start filled with walls; clear all FOV state
	for i in 0 ..< len(g.tiles) {
		g.tiles[i]    = .Wall
		g.visible[i]  = false
		g.explored[i] = false
	}

	rooms := make([dynamic]Room, 0, MAX_ROOMS)
	defer delete(rooms)

	for _ in 0 ..< PLACE_ATTEMPTS {
		if len(rooms) >= MAX_ROOMS { break }

		w := rand_in_range(ROOM_MIN, ROOM_MAX)
		h := rand_in_range(ROOM_MIN, ROOM_MAX)
		x := rand_in_range(1, MAP_W - w - 2)
		y := rand_in_range(1, MAP_H - h - 2)
		candidate := Room{x, y, w, h}

		// require a 1-tile gap from any existing room
		padded := Room{x - 1, y - 1, w + 2, h + 2}
		clash := false
		for r in rooms {
			if rooms_overlap(padded, r) { clash = true; break }
		}
		if clash { continue }

		carve_room(g, candidate)

		if len(rooms) > 0 {
			cx1, cy1 := room_center(rooms[len(rooms) - 1])
			cx2, cy2 := room_center(candidate)
			if rand.int_max(2) == 0 {
				carve_h_corridor(g, cx1, cx2, cy1)
				carve_v_corridor(g, cy1, cy2, cx2)
			} else {
				carve_v_corridor(g, cy1, cy2, cx1)
				carve_h_corridor(g, cx1, cx2, cy2)
			}
		}

		append(&rooms, candidate)
	}

	// Helheim is the bottom of Yggdrasil — no stairs onward, and the final
	// room hosts Hel instead. The player must find and defeat her to win.
	is_final_realm := g.realm == .Helheim
	stair_x, stair_y := -1, -1

	if len(rooms) > 0 {
		px, py := room_center(rooms[0])
		g.player.x = px
		g.player.y = py

		if !is_final_realm {
			sx, sy := room_center(rooms[len(rooms) - 1])
			set_tile(g, sx, sy, .Stairs_Down)
			stair_x, stair_y = sx, sy
		}
	} else {
		// extremely unlikely; fall back to center
		g.player.x = MAP_W / 2
		g.player.y = MAP_H / 2
		set_tile(g, g.player.x, g.player.y, .Floor)
	}

	// Spawn Hel first (in Helheim) so the normal spawn pass treats her tile
	// as occupied and won't drop a hound on top of the queen of the dead.
	clear(&g.enemies)
	if is_final_realm && len(rooms) > 0 {
		hx, hy := room_center(rooms[len(rooms) - 1])
		if spawnable(g, hx, hy) {
			append(&g.enemies, make_hel(hx, hy))
		}
	} else if stair_x >= 0 {
		boss_kind, has_boss := realm_miniboss_kind(g.realm)
		if has_boss {
			append(&g.enemies, make_enemy(boss_kind, stair_x, stair_y))
		}
	}

	// spawn enemies in non-starting rooms using the realm's spawn weights;
	// the boss room (last room in Helheim) is left to Hel alone.
	weights := realm_spawn_weights(g.realm)
	for i in 1 ..< len(rooms) {
		if is_final_realm && i == len(rooms) - 1 { continue }
		if rand.int_max(100) >= ENEMY_SPAWN_PCT { continue }
		r := rooms[i]
		ex := r.x + 1 + rand.int_max(max(1, r.w - 2))
		ey := r.y + 1 + rand.int_max(max(1, r.h - 2))
		if !spawnable(g, ex, ey) { continue }
		kind := pick_enemy_kind(weights)
		append(&g.enemies, make_enemy(kind, ex, ey))
		// Hounds run in packs — try to place a companion adjacent.
		if kind == .Hound {
			try_spawn_packmate(g, ex, ey, .Hound)
		}
	}

	// scatter items in non-starting rooms (avoid stairs, avoid enemies)
	clear(&g.items)
	for i in 1 ..< len(rooms) {
		if rand.int_max(100) >= ITEM_SPAWN_PCT { continue }
		r := rooms[i]
		ix := r.x + 1 + rand.int_max(max(1, r.w - 2))
		iy := r.y + 1 + rand.int_max(max(1, r.h - 2))
		if tile_at(g, ix, iy) == .Stairs_Down { continue }
		if enemy_at(g, ix, iy) != nil          { continue }
		if item_at(g, ix, iy) >= 0             { continue }
		append(&g.items, Item{x = ix, y = iy, kind = pick_item_kind()})
	}
}
