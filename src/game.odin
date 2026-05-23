package asgard

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// Map dimensions sized so the play area (MAP_W * TILE_PX + 12 left margin)
// fits within WINDOW_W - UI_RIGHT_PX. Bumping these requires re-checking layout.
MAP_W :: 50
MAP_H :: 24

LOG_LINES :: 6

Tile :: enum u8 {
	Floor,
	Wall,
	Stairs_Down,
}

Realm :: enum {
	Midgard,
	Asgard,
	Jotunheim,
	Niflheim,
	Muspelheim,
	Alfheim,
	Svartalfheim,
	Vanaheim,
	Helheim,
}

realm_name :: proc(r: Realm) -> string {
	switch r {
	case .Midgard:      return "Midgard"
	case .Asgard:       return "Asgard"
	case .Jotunheim:    return "Jotunheim"
	case .Niflheim:     return "Niflheim"
	case .Muspelheim:   return "Muspelheim"
	case .Alfheim:      return "Alfheim"
	case .Svartalfheim: return "Svartalfheim"
	case .Vanaheim:     return "Vanaheim"
	case .Helheim:      return "Helheim"
	}
	return "?"
}

// One-line atmosphere blurb shown in the saga log on arrival.
realm_flavor :: proc(r: Realm) -> string {
	switch r {
	case .Midgard:      return "Cold mist clings to mortal stone."
	case .Asgard:       return "Golden halls thrum with the breath of gods."
	case .Jotunheim:    return "Frost rasps the walls of giants' country."
	case .Niflheim:     return "Endless mist swallows your footfalls."
	case .Muspelheim:   return "The air itself burns. Surtr stirs."
	case .Alfheim:      return "Light pours from the stones; the world breathes."
	case .Svartalfheim: return "Hammers ring in deeper dark."
	case .Vanaheim:     return "Old magic stirs in the green half-light."
	case .Helheim:      return "Silence. Even the dead hold their breath."
	}
	return ""
}

Entity :: struct {
	x, y:         int,
	glyph:        cstring,
	name:         string,
	color:        rl.Color,
	hp:           int,
	hp_max:       int,
	power:        int,
	armor:        int,
	alive:        bool,
	flash_frames: int, // counts down each frame; > 0 = render with hit-flash color
}

Room :: struct {
	x, y, w, h: int,
}

Game :: struct {
	tiles:           [MAP_W * MAP_H]Tile,
	visible:         [MAP_W * MAP_H]bool,
	explored:        [MAP_W * MAP_H]bool,
	player:          Entity,
	enemies:         [dynamic]Entity,
	items:           [dynamic]Item,     // on the ground in current realm
	inventory:       [dynamic]ItemKind, // in the player's pack (persists across realms)
	realm:           Realm,
	depth:           int,
	turn:            int,
	seed:            u64,
	log:             [dynamic]string,
	dead:            bool,
	quit:            bool,
	descend_pending: bool,

	// visual feedback state (updated by tick_anim each frame)
	shake_frames:    int,
	shake_dx:        i32,
	shake_dy:        i32,
}

// ---- tile helpers ----------------------------------------------------------

tile_at :: proc(g: ^Game, x, y: int) -> Tile {
	if x < 0 || y < 0 || x >= MAP_W || y >= MAP_H {
		return .Wall
	}
	return g.tiles[y * MAP_W + x]
}

set_tile :: proc(g: ^Game, x, y: int, t: Tile) {
	if x < 0 || y < 0 || x >= MAP_W || y >= MAP_H { return }
	g.tiles[y * MAP_W + x] = t
}

log_msg :: proc(g: ^Game, msg: string) {
	append(&g.log, strings.clone(msg))
	for len(g.log) > LOG_LINES {
		delete(g.log[0])
		ordered_remove(&g.log, 0)
	}
}

// ---- lifecycle -------------------------------------------------------------

new_game :: proc(seed: u64) -> Game {
	g := Game{}
	g.realm     = .Midgard
	g.depth     = 1
	g.turn      = 0
	g.player    = make_player()
	g.enemies   = make([dynamic]Entity,   0, 16)
	g.items     = make([dynamic]Item,     0, 16)
	g.inventory = make([dynamic]ItemKind, 0, INVENTORY_CAP)
	g.log       = make([dynamic]string,   0, 32)
	generate_map(&g, seed)
	compute_fov(&g, g.player.x, g.player.y, FOV_RADIUS)
	log_msg(&g, "You awaken in a stone chamber. Cold mist clings to the floor.")
	log_msg(&g, "Somewhere, Yggdrasil's roots stir. Draugr stir with them.")
	log_msg(&g, fmt.tprintf("(seed %d - press R to reshape the realm)", g.seed))
	return g
}

destroy_game :: proc(g: ^Game) {
	for s in g.log { delete(s) }
	delete(g.log)
	delete(g.enemies)
	delete(g.items)
	delete(g.inventory)
}

regenerate :: proc(g: ^Game) {
	g.player          = make_player()
	g.dead            = false
	g.turn            = 0
	g.depth           = 1
	g.realm           = .Midgard
	g.descend_pending = false
	clear(&g.inventory)
	generate_map(g, fresh_seed())
	compute_fov(g, g.player.x, g.player.y, FOV_RADIUS)
	log_msg(g, fmt.tprintf("The realm reshapes itself. (seed %d)", g.seed))
}

// Descend the World Tree: advance realm, regenerate the map with a fresh
// seed, keep player HP and turn count. Clamps at Helheim.
descend :: proc(g: ^Game) {
	g.descend_pending = false
	g.depth += 1

	next := int(g.realm) + 1
	if next > int(Realm.Helheim) {
		next = int(Realm.Helheim)
	}
	g.realm = Realm(next)

	generate_map(g, fresh_seed())
	compute_fov(g, g.player.x, g.player.y, FOV_RADIUS)
	play_sound(.Descend)

	log_msg(g, fmt.tprintf("You descend to %s. (depth %d)", realm_name(g.realm), g.depth))
	if flavor := realm_flavor(g.realm); flavor != "" {
		log_msg(g, flavor)
	}
}

// ---- input / turn loop -----------------------------------------------------

read_move :: proc() -> (dx: int, dy: int, acted: bool) {
	if rl.IsKeyPressed(.LEFT)  || rl.IsKeyPressed(.H) { return -1,  0, true }
	if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.L) { return  1,  0, true }
	if rl.IsKeyPressed(.UP)    || rl.IsKeyPressed(.K) { return  0, -1, true }
	if rl.IsKeyPressed(.DOWN)  || rl.IsKeyPressed(.J) { return  0,  1, true }
	if rl.IsKeyPressed(.Y) { return -1, -1, true }
	if rl.IsKeyPressed(.U) { return  1, -1, true }
	if rl.IsKeyPressed(.B) { return -1,  1, true }
	if rl.IsKeyPressed(.N) { return  1,  1, true }
	if rl.IsKeyPressed(.PERIOD) { return 0, 0, true } // wait
	return 0, 0, false
}

try_step :: proc(g: ^Game, dx, dy: int) -> (took_turn: bool) {
	if dx == 0 && dy == 0 {
		log_msg(g, "You wait, listening to the wind.")
		return true
	}
	nx := g.player.x + dx
	ny := g.player.y + dy
	if tile_at(g, nx, ny) == .Wall {
		log_msg(g, "A wall blocks your path.")
		return false
	}
	if target := enemy_at(g, nx, ny); target != nil {
		attack(g, &g.player, target)
		return true
	}
	g.player.x = nx
	g.player.y = ny
	if idx := item_at(g, nx, ny); idx >= 0 {
		pickup_item(g, idx)
	}
	if tile_at(g, nx, ny) == .Stairs_Down {
		log_msg(g, "Stairs spiral down into Yggdrasil's deeper roots.")
		g.descend_pending = true
	}
	return true
}

handle_input :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.Q) {
		g.quit = true
		return
	}
	if rl.IsKeyPressed(.R) {
		regenerate(g)
		return
	}
	if g.dead {
		return // only R/Esc/Q respond when fallen
	}

	if slot := read_item_slot(); slot >= 0 {
		if use_item(g, slot) {
			g.turn += 1
			compute_fov(g, g.player.x, g.player.y, FOV_RADIUS)
			if !g.dead {
				enemy_turn(g)
			}
		}
		return
	}

	dx, dy, acted := read_move()
	if !acted { return }
	if try_step(g, dx, dy) {
		g.turn += 1
		compute_fov(g, g.player.x, g.player.y, FOV_RADIUS)
		if !g.dead {
			enemy_turn(g)
		}
		if g.descend_pending && !g.dead {
			descend(g)
		}
	}
}

read_item_slot :: proc() -> int {
	if rl.IsKeyPressed(.ONE)   { return 0 }
	if rl.IsKeyPressed(.TWO)   { return 1 }
	if rl.IsKeyPressed(.THREE) { return 2 }
	if rl.IsKeyPressed(.FOUR)  { return 3 }
	if rl.IsKeyPressed(.FIVE)  { return 4 }
	if rl.IsKeyPressed(.SIX)   { return 5 }
	return -1
}
