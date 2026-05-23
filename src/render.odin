package asgard

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

TILE_PX :: 20

UI_TOP_PX   :: 40
UI_BOT_PX   :: 160
UI_RIGHT_PX :: 240

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

// ---- low-level drawing -----------------------------------------------------

draw_glyph :: proc(ch: cstring, x, y, size: i32, col: rl.Color) {
	rl.DrawText(ch, x, y, size, col)
}

map_origin :: proc() -> (ox: i32, oy: i32) {
	return 12, UI_TOP_PX
}

// ---- world drawing ---------------------------------------------------------

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

// ---- UI chrome -------------------------------------------------------------

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

// ---- frame -----------------------------------------------------------------

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
