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
	flash_frames: int,       // counts down each frame; > 0 = render with hit-flash color
	attack_sound: SoundKind, // played when THIS entity lands a hit
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
	play_realm_music(g.realm)
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
	play_realm_music(g.realm)
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
	play_realm_music(g.realm)

	log_msg(g, fmt.tprintf("You descend to %s. (depth %d)", realm_name(g.realm), g.depth))
	if flavor := realm_flavor(g.realm); flavor != "" {
		log_msg(g, flavor)
	}
}

// ---- input / turn loop -----------------------------------------------------

// ---- hold-to-repeat movement -----------------------------------------------

HOLD_INITIAL_DELAY :: f64(0.20) // seconds before auto-repeat kicks in
HOLD_REPEAT_PERIOD :: f64(0.08) // seconds between auto-repeats

@(private="file")
move_hold: struct {
	key:     rl.KeyboardKey,
	dx, dy:  int,
	first_t: f64,
	last_t:  f64,
}

@(private="file")
start_hold :: proc(key: rl.KeyboardKey, dx, dy: int) -> (int, int, bool) {
	now := rl.GetTime()
	move_hold.key     = key
	move_hold.dx      = dx
	move_hold.dy      = dy
	move_hold.first_t = now
	move_hold.last_t  = now
	return dx, dy, true
}

// Called by handle_input when a move fails (wall bump) so the player doesn't
// auto-spam the same blocked direction.
cancel_hold :: proc() {
	move_hold.key = .KEY_NULL
}

read_move :: proc() -> (dx: int, dy: int, acted: bool) {
	// Initial press: each binding checked individually so we know exactly
	// which key to track for the held-down check below.
	if rl.IsKeyPressed(.LEFT)  { return start_hold(.LEFT,  -1,  0) }
	if rl.IsKeyPressed(.H)     { return start_hold(.H,     -1,  0) }
	if rl.IsKeyPressed(.RIGHT) { return start_hold(.RIGHT,  1,  0) }
	if rl.IsKeyPressed(.L)     { return start_hold(.L,      1,  0) }
	if rl.IsKeyPressed(.UP)    { return start_hold(.UP,     0, -1) }
	if rl.IsKeyPressed(.K)     { return start_hold(.K,      0, -1) }
	if rl.IsKeyPressed(.DOWN)  { return start_hold(.DOWN,   0,  1) }
	if rl.IsKeyPressed(.J)     { return start_hold(.J,      0,  1) }
	if rl.IsKeyPressed(.Y)     { return start_hold(.Y,     -1, -1) }
	if rl.IsKeyPressed(.U)     { return start_hold(.U,      1, -1) }
	if rl.IsKeyPressed(.B)     { return start_hold(.B,     -1,  1) }
	if rl.IsKeyPressed(.N)     { return start_hold(.N,      1,  1) }

	if rl.IsKeyPressed(.PERIOD) { return 0, 0, true } // wait — no auto-repeat

	// Hold-repeat for the currently tracked key
	if move_hold.key != .KEY_NULL {
		if rl.IsKeyDown(move_hold.key) {
			now := rl.GetTime()
			if (now - move_hold.first_t) >= HOLD_INITIAL_DELAY &&
			   (now - move_hold.last_t)  >= HOLD_REPEAT_PERIOD {
				move_hold.last_t = now
				return move_hold.dx, move_hold.dy, true
			}
		} else {
			move_hold.key = .KEY_NULL // released; stop tracking
		}
	}

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
	} else {
		// blocked (wall bump): break the hold so we don't spam the saga log
		cancel_hold()
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
