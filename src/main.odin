package asgard

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

WINDOW_W :: 1280
WINDOW_H :: 720

MAP_W :: 60
MAP_H :: 24

TILE_PX :: 20

UI_TOP_PX :: 40
UI_BOT_PX :: 160
UI_RIGHT_PX :: 240

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

Player :: struct {
	x, y:    int,
	hp:      int,
	hp_max:  int,
	name:    string,
}

Game :: struct {
	tiles:  [MAP_W * MAP_H]Tile,
	player: Player,
	realm:  Realm,
	turn:   int,
	log:    [dynamic]string,
	quit:   bool,
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

init_map :: proc(g: ^Game) {
	for y in 0 ..< MAP_H {
		for x in 0 ..< MAP_W {
			if x == 0 || y == 0 || x == MAP_W - 1 || y == MAP_H - 1 {
				set_tile(g, x, y, .Wall)
			} else {
				set_tile(g, x, y, .Floor)
			}
		}
	}

	// A few inner walls for shape — to be replaced by procgen later.
	for x in 14 ..= 24 { set_tile(g, x, 8, .Wall) }
	for y in 8 ..= 14  { set_tile(g, 24, y, .Wall) }
	for x in 34 ..= 44 { set_tile(g, x, 16, .Wall) }
	set_tile(g, 19, 8, .Floor)  // doorway
	set_tile(g, 24, 11, .Floor) // doorway
	set_tile(g, 39, 16, .Floor) // doorway

	set_tile(g, MAP_W - 3, MAP_H - 3, .Stairs_Down)
}

new_game :: proc() -> Game {
	g := Game{}
	g.realm   = .Midgard
	g.turn    = 0
	g.player  = Player{
		x = MAP_W / 4,
		y = MAP_H / 2,
		hp = 20,
		hp_max = 20,
		name = "Wanderer",
	}
	g.log = make([dynamic]string, 0, 32)
	init_map(&g)
	log_msg(&g, "You awaken in a stone chamber. Cold mist clings to the floor.")
	log_msg(&g, "Somewhere, Yggdrasil's roots stir.")
	return g
}

destroy_game :: proc(g: ^Game) {
	for s in g.log { delete(s) }
	delete(g.log)
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
	dx, dy, acted := read_move()
	if !acted { return }
	if try_step(g, dx, dy) {
		g.turn += 1
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
	ui_fg:     rl.Color,
	ui_dim:    rl.Color,
	ui_panel:  rl.Color,
	hp_full:   rl.Color,
	hp_low:    rl.Color,
}{
	bg        = {12, 12, 18, 255},
	wall      = {90, 80, 70, 255},
	floor     = {55, 55, 65, 255},
	floor_dim = {35, 35, 45, 255},
	stairs    = {120, 200, 220, 255},
	player    = {240, 200, 80, 255},
	ui_fg     = {220, 220, 210, 255},
	ui_dim    = {130, 130, 140, 255},
	ui_panel  = {22, 22, 30, 255},
	hp_full   = {120, 200, 110, 255},
	hp_low    = {200, 80, 70, 255},
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

draw_player :: proc(g: ^Game) {
	ox, oy := map_origin()
	px := ox + i32(g.player.x) * TILE_PX
	py := oy + i32(g.player.y) * TILE_PX
	draw_glyph("@", px, py, TILE_PX, PALETTE.player)
}

draw_top_bar :: proc(g: ^Game) {
	rl.DrawRectangle(0, 0, WINDOW_W, UI_TOP_PX - 4, PALETTE.ui_panel)
	title := fmt.ctprintf("ASGARD  -  %s  -  Turn %d", realm_name(g.realm), g.turn)
	rl.DrawText(title, 12, 10, 22, PALETTE.ui_fg)
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

	hint_y := i32(UI_TOP_PX + 120)
	rl.DrawText("Controls",            x + 12, hint_y,       16, PALETTE.ui_fg)
	rl.DrawText("Arrows / h j k l",    x + 12, hint_y + 24,  14, PALETTE.ui_dim)
	rl.DrawText("y u b n  diagonals",  x + 12, hint_y + 44,  14, PALETTE.ui_dim)
	rl.DrawText(".  wait",             x + 12, hint_y + 64,  14, PALETTE.ui_dim)
	rl.DrawText("Esc / q  quit",       x + 12, hint_y + 84,  14, PALETTE.ui_dim)
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
	draw_player(g)
	draw_sidebar(g)
	draw_log(g)
	rl.EndDrawing()
	free_all(context.temp_allocator)
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_HIGHDPI, .VSYNC_HINT})
	rl.InitWindow(WINDOW_W, WINDOW_H, "Asgard")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL) // we handle quit ourselves

	g := new_game()
	defer destroy_game(&g)

	for !rl.WindowShouldClose() && !g.quit {
		handle_input(&g)
		render(&g)
	}

	fmt.printfln("Farewell. You walked %d turns through %s.", g.turn, realm_name(g.realm))
}
