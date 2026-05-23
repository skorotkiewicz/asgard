package asgard

import "core:math/rand"
import "core:time"

ROOM_MIN         :: 4
ROOM_MAX         :: 9
MAX_ROOMS        :: 14
PLACE_ATTEMPTS   :: 80
DRAUGR_SPAWN_PCT :: 55 // per non-starting room

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

	if len(rooms) > 0 {
		px, py := room_center(rooms[0])
		g.player.x = px
		g.player.y = py

		sx, sy := room_center(rooms[len(rooms) - 1])
		set_tile(g, sx, sy, .Stairs_Down)
	} else {
		// extremely unlikely; fall back to center
		g.player.x = MAP_W / 2
		g.player.y = MAP_H / 2
		set_tile(g, g.player.x, g.player.y, .Floor)
	}

	// spawn draugr in non-starting rooms
	clear(&g.enemies)
	for i in 1 ..< len(rooms) {
		if rand.int_max(100) >= DRAUGR_SPAWN_PCT { continue }
		r := rooms[i]
		ex := r.x + 1 + rand.int_max(max(1, r.w - 2))
		ey := r.y + 1 + rand.int_max(max(1, r.h - 2))
		// avoid landing on stairs
		if tile_at(g, ex, ey) == .Stairs_Down { continue }
		append(&g.enemies, make_draugr(ex, ey))
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
