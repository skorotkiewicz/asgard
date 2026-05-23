package asgard

import "core:fmt"
import "core:math/rand"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

WINDOW_W :: 1280
WINDOW_H :: 720

MAP_W :: 60
MAP_H :: 24

TILE_PX :: 20

UI_TOP_PX :: 40
UI_BOT_PX :: 160
UI_RIGHT_PX :: 240

ROOM_MIN        :: 4
ROOM_MAX        :: 9
MAX_ROOMS       :: 14
PLACE_ATTEMPTS  :: 80

AGGRO_RADIUS        :: 8
DRAUGR_SPAWN_PCT    :: 55  // per non-starting room

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

Entity :: struct {
	x, y:        int,
	glyph:       cstring,
	name:        string,
	color:       rl.Color,
	hp:          int,
	hp_max:      int,
	power:       int,
	armor:       int,
	alive:       bool,
}

Room :: struct {
	x, y, w, h: int,
}

Game :: struct {
	tiles:   [MAP_W * MAP_H]Tile,
	player:  Entity,
	enemies: [dynamic]Entity,
	realm:   Realm,
	turn:    int,
	seed:    u64,
	log:     [dynamic]string,
	dead:    bool,
	quit:    bool,
}

LOG_LINES :: 6

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

// ---- entities & combat -----------------------------------------------------

make_player :: proc() -> Entity {
	return Entity{
		glyph  = "@",
		name   = "Wanderer",
		color  = PALETTE.player,
		hp     = 20,
		hp_max = 20,
		power  = 4,
		armor  = 1,
		alive  = true,
	}
}

make_draugr :: proc(x, y: int) -> Entity {
	return Entity{
		x = x, y = y,
		glyph  = "d",
		name   = "draugr",
		color  = PALETTE.draugr,
		hp     = 6,
		hp_max = 6,
		power  = 3,
		armor  = 0,
		alive  = true,
	}
}

// Returns pointer to a live enemy at (x,y), or nil. Pointer is stable so long
// as g.enemies isn't appended to between the lookup and use.
enemy_at :: proc(g: ^Game, x, y: int) -> ^Entity {
	for &e in g.enemies {
		if e.alive && e.x == x && e.y == y { return &e }
	}
	return nil
}

is_walkable :: proc(g: ^Game, x, y: int) -> bool {
	if tile_at(g, x, y) == .Wall { return false }
	if enemy_at(g, x, y) != nil  { return false }
	return true
}

sign :: proc(n: int) -> int {
	if n > 0 { return 1 }
	if n < 0 { return -1 }
	return 0
}

abs_int :: proc(n: int) -> int {
	if n < 0 { return -n }
	return n
}

cheb_dist :: proc(ax, ay, bx, by: int) -> int {
	return max(abs_int(ax - bx), abs_int(ay - by))
}

attack :: proc(g: ^Game, attacker, defender: ^Entity) {
	roll := rand.int_max(3) - 1 // -1, 0, +1
	dmg  := max(1, attacker.power - defender.armor + roll)
	defender.hp -= dmg

	if attacker == &g.player {
		log_msg(g, fmt.tprintf("You strike the %s (%d dmg).", defender.name, dmg))
	} else if defender == &g.player {
		log_msg(g, fmt.tprintf("The %s lunges at you (%d dmg).", attacker.name, dmg))
	} else {
		log_msg(g, fmt.tprintf("%s hits %s (%d).", attacker.name, defender.name, dmg))
	}

	if defender.hp <= 0 {
		defender.alive = false
		if defender == &g.player {
			log_msg(g, "You have fallen. The realm grows still.")
			g.dead = true
		} else {
			log_msg(g, fmt.tprintf("The %s crumbles to dust.", defender.name))
		}
	}
}

enemy_turn :: proc(g: ^Game) {
	for &e in g.enemies {
		if !e.alive { continue }
		dist := cheb_dist(e.x, e.y, g.player.x, g.player.y)
		if dist > AGGRO_RADIUS { continue }

		// adjacent → attack
		if dist == 1 {
			attack(g, &e, &g.player)
			if g.dead { return }
			continue
		}

		// greedy chase
		dx := sign(g.player.x - e.x)
		dy := sign(g.player.y - e.y)

		if dx != 0 && dy != 0 && is_walkable(g, e.x + dx, e.y + dy) {
			e.x += dx; e.y += dy
			continue
		}
		if dx != 0 && is_walkable(g, e.x + dx, e.y) {
			e.x += dx
			continue
		}
		if dy != 0 && is_walkable(g, e.x, e.y + dy) {
			e.y += dy
			continue
		}
		// blocked: shuffle awkwardly (skip turn)
	}
}

// ---- map generation --------------------------------------------------------

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

generate_map :: proc(g: ^Game, seed: u64) {
	rand.reset(seed)
	g.seed = seed

	// start filled with walls
	for i in 0 ..< len(g.tiles) { g.tiles[i] = .Wall }

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
}

fresh_seed :: proc() -> u64 {
	return u64(time.now()._nsec)
}

regenerate :: proc(g: ^Game) {
	g.player = make_player()
	g.dead   = false
	g.turn   = 0
	generate_map(g, fresh_seed())
	log_msg(g, fmt.tprintf("The realm reshapes itself. (seed %d)", g.seed))
}

new_game :: proc(seed: u64) -> Game {
	g := Game{}
	g.realm   = .Midgard
	g.turn    = 0
	g.player  = make_player()
	g.enemies = make([dynamic]Entity, 0, 16)
	g.log     = make([dynamic]string, 0, 32)
	generate_map(&g, seed)
	log_msg(&g, "You awaken in a stone chamber. Cold mist clings to the floor.")
	log_msg(&g, "Somewhere, Yggdrasil's roots stir. Draugr stir with them.")
	log_msg(&g, fmt.tprintf("(seed %d - press R to reshape the realm)", g.seed))
	return g
}

destroy_game :: proc(g: ^Game) {
	for s in g.log { delete(s) }
	delete(g.log)
	delete(g.enemies)
}

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
	if tile_at(g, nx, ny) == .Stairs_Down {
		log_msg(g, "Stairs spiral down into Yggdrasil's deeper roots.")
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
	dx, dy, acted := read_move()
	if !acted { return }
	if try_step(g, dx, dy) {
		g.turn += 1
		if !g.dead {
			enemy_turn(g)
		}
	}
}

// ---- rendering --------------------------------------------------------------

PALETTE := struct {
	bg:        rl.Color,
	wall:      rl.Color,
	floor:     rl.Color,
	floor_dim: rl.Color,
	stairs:    rl.Color,
	player:    rl.Color,
	draugr:    rl.Color,
	ui_fg:     rl.Color,
	ui_dim:    rl.Color,
	ui_panel:  rl.Color,
	hp_full:   rl.Color,
	hp_low:    rl.Color,
	dead_tint: rl.Color,
}{
	bg        = {12, 12, 18, 255},
	wall      = {90, 80, 70, 255},
	floor     = {55, 55, 65, 255},
	floor_dim = {35, 35, 45, 255},
	stairs    = {120, 200, 220, 255},
	player    = {240, 200, 80, 255},
	draugr    = {150, 180, 130, 255},
	ui_fg     = {220, 220, 210, 255},
	ui_dim    = {130, 130, 140, 255},
	ui_panel  = {22, 22, 30, 255},
	hp_full   = {120, 200, 110, 255},
	hp_low    = {200, 80, 70, 255},
	dead_tint = {30, 0, 0, 180},
}

draw_glyph :: proc(ch: cstring, x, y, size: i32, col: rl.Color) {
	rl.DrawText(ch, x, y, size, col)
}

map_origin :: proc() -> (ox: i32, oy: i32) {
	return 12, UI_TOP_PX
}

draw_map :: proc(g: ^Game) {
	ox, oy := map_origin()
	for y in 0 ..< MAP_H {
		for x in 0 ..< MAP_W {
			px := ox + i32(x) * TILE_PX
			py := oy + i32(y) * TILE_PX
			t := g.tiles[y * MAP_W + x]
			switch t {
			case .Wall:
				draw_glyph("#", px, py, TILE_PX, PALETTE.wall)
			case .Floor:
				draw_glyph(".", px, py, TILE_PX, PALETTE.floor)
			case .Stairs_Down:
				draw_glyph(">", px, py, TILE_PX, PALETTE.stairs)
			}
		}
	}
}

draw_entity :: proc(e: ^Entity) {
	if !e.alive { return }
	ox, oy := map_origin()
	px := ox + i32(e.x) * TILE_PX
	py := oy + i32(e.y) * TILE_PX
	draw_glyph(e.glyph, px, py, TILE_PX, e.color)
}

draw_entities :: proc(g: ^Game) {
	for &e in g.enemies { draw_entity(&e) }
	draw_entity(&g.player) // draw player on top
}

draw_game_over :: proc(g: ^Game) {
	if !g.dead { return }
	rl.DrawRectangle(0, 0, WINDOW_W, WINDOW_H, PALETTE.dead_tint)
	msg : cstring = "YOU HAVE FALLEN"
	hint: cstring = "press R to rise in a new realm  -  Esc to depart"
	mw := rl.MeasureText(msg, 56)
	hw := rl.MeasureText(hint, 20)
	rl.DrawText(msg,  (WINDOW_W - mw) / 2, WINDOW_H / 2 - 60, 56, PALETTE.hp_low)
	rl.DrawText(hint, (WINDOW_W - hw) / 2, WINDOW_H / 2 + 10, 20, PALETTE.ui_fg)
}

draw_top_bar :: proc(g: ^Game) {
	rl.DrawRectangle(0, 0, WINDOW_W, UI_TOP_PX - 4, PALETTE.ui_panel)
	title := fmt.ctprintf("ASGARD  -  %s  -  Turn %d", realm_name(g.realm), g.turn)
	rl.DrawText(title, 12, 10, 22, PALETTE.ui_fg)
	seed_label := fmt.ctprintf("seed %d", g.seed)
	rl.DrawText(seed_label, WINDOW_W - UI_RIGHT_PX + 12, 14, 16, PALETTE.ui_dim)
}

draw_sidebar :: proc(g: ^Game) {
	x: i32 = WINDOW_W - UI_RIGHT_PX
	rl.DrawRectangle(x, UI_TOP_PX, UI_RIGHT_PX, WINDOW_H - UI_TOP_PX - UI_BOT_PX, PALETTE.ui_panel)

	rl.DrawText(fmt.ctprintf("%s", g.player.name), x + 12, UI_TOP_PX + 12, 20, PALETTE.ui_fg)

	hp_col := PALETTE.hp_full
	if g.player.hp <= g.player.hp_max / 3 {
		hp_col = PALETTE.hp_low
	}
	rl.DrawText(
		fmt.ctprintf("HP  %d / %d", g.player.hp, g.player.hp_max),
		x + 12, UI_TOP_PX + 44, 18, hp_col,
	)

	// HP bar
	bar_x := x + 12
	bar_y := i32(UI_TOP_PX + 72)
	bar_w := i32(UI_RIGHT_PX - 24)
	bar_h := i32(10)
	rl.DrawRectangle(bar_x, bar_y, bar_w, bar_h, {50, 50, 60, 255})
	if g.player.hp_max > 0 {
		fill := i32(f32(bar_w) * f32(g.player.hp) / f32(g.player.hp_max))
		rl.DrawRectangle(bar_x, bar_y, fill, bar_h, hp_col)
	}

	alive_foes := 0
	for &e in g.enemies { if e.alive { alive_foes += 1 } }
	rl.DrawText(
		fmt.ctprintf("Foes  %d", alive_foes),
		x + 12, UI_TOP_PX + 92, 16, PALETTE.ui_fg,
	)

	hint_y := i32(UI_TOP_PX + 140)
	rl.DrawText("Controls",            x + 12, hint_y,        16, PALETTE.ui_fg)
	rl.DrawText("Arrows / h j k l",    x + 12, hint_y + 24,   14, PALETTE.ui_dim)
	rl.DrawText("y u b n  diagonals",  x + 12, hint_y + 44,   14, PALETTE.ui_dim)
	rl.DrawText(".  wait",             x + 12, hint_y + 64,   14, PALETTE.ui_dim)
	rl.DrawText("R  reshape realm",    x + 12, hint_y + 84,   14, PALETTE.ui_dim)
	rl.DrawText("Esc / q  quit",       x + 12, hint_y + 104,  14, PALETTE.ui_dim)
}

draw_log :: proc(g: ^Game) {
	y := i32(WINDOW_H - UI_BOT_PX)
	rl.DrawRectangle(0, y, WINDOW_W, UI_BOT_PX, PALETTE.ui_panel)
	rl.DrawText("Saga", 12, y + 8, 18, PALETTE.ui_dim)

	line_y := y + 32
	for msg, i in g.log {
		fade: u8 = 220
		if i < len(g.log) - 3 { fade = 140 }
		col := rl.Color{fade, fade, fade - 10, 255}
		c := strings.clone_to_cstring(msg, context.temp_allocator)
		rl.DrawText(c, 12, line_y, 18, col)
		line_y += 20
	}
}

render :: proc(g: ^Game) {
	rl.BeginDrawing()
	rl.ClearBackground(PALETTE.bg)
	draw_top_bar(g)
	draw_map(g)
	draw_entities(g)
	draw_sidebar(g)
	draw_log(g)
	draw_game_over(g)
	rl.EndDrawing()
	free_all(context.temp_allocator)
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_HIGHDPI, .VSYNC_HINT})
	rl.InitWindow(WINDOW_W, WINDOW_H, "Asgard")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL) // we handle quit ourselves

	g := new_game(fresh_seed())
	defer destroy_game(&g)

	for !rl.WindowShouldClose() && !g.quit {
		handle_input(&g)
		render(&g)
	}

	fmt.printfln("Farewell. You walked %d turns through %s.", g.turn, realm_name(g.realm))
}
