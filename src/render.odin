package asgard

import "core:fmt"
import "core:math/rand"
import "core:strings"
import rl "vendor:raylib"

TILE_PX :: 20

UI_TOP_PX   :: 40
UI_BOT_PX   :: 160
UI_RIGHT_PX :: 240

// ---- combat-feedback tuning ------------------------------------------------

HIT_FLASH_FRAMES :: 6                          // ~100ms at 60fps
HIT_FLASH_COLOR  :: rl.Color{230, 80, 70, 255} // red tint applied to defender

SHAKE_MAX_FRAMES :: 8                          // ~130ms at 60fps
SHAKE_MAX_PX     :: 4                          // peak amplitude in pixels

PALETTE := struct {
	bg:        rl.Color,
	wall:      rl.Color,
	floor:     rl.Color,
	floor_dim: rl.Color,
	stairs:    rl.Color,
	player:    rl.Color,
	draugr:    rl.Color,
	jotunn:    rl.Color,
	hound:     rl.Color,
	troll:       rl.Color,
	wraith:      rl.Color,
	fenrir:      rl.Color,
	surtr:       rl.Color,
	jormungandr: rl.Color,
	hel:       rl.Color,
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
	jotunn    = {180, 200, 220, 255}, // pale icy blue
	hound     = {200,  70,  60, 255}, // dark red
	troll        = {120, 170,  95, 255},
	wraith       = {150, 160, 210, 255},
	fenrir       = {210, 210, 190, 255},
	surtr        = {240, 100,  35, 255},
	jormungandr = { 80, 190, 160, 255},
	hel       = {200, 150, 210, 255}, // pale violet, half-corpse
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

// Top-left of the map area, including any active screen-shake offset.
map_origin :: proc(g: ^Game) -> (ox: i32, oy: i32) {
	return 12 + g.shake_dx, UI_TOP_PX + g.shake_dy
}

// Tick down visual-feedback counters and pick a fresh shake offset for the
// upcoming frame. Called once per frame from the main loop (before render).
tick_anim :: proc(g: ^Game) {
	if g.player.flash_frames > 0 { g.player.flash_frames -= 1 }
	for &e in g.enemies {
		if e.flash_frames > 0 { e.flash_frames -= 1 }
	}

	if g.shake_frames > 0 {
		g.shake_frames -= 1
	}
	if g.shake_frames > 0 {
		mag := f32(g.shake_frames) / f32(SHAKE_MAX_FRAMES)
		amp := int(f32(SHAKE_MAX_PX) * mag) + 1
		g.shake_dx = i32(rand.int_max(amp * 2 + 1) - amp)
		g.shake_dy = i32(rand.int_max(amp * 2 + 1) - amp)
	} else {
		g.shake_dx = 0
		g.shake_dy = 0
	}
}

// Multiply RGB channels by `factor` (alpha preserved). Used to dim explored-
// but-not-visible tiles.
dim :: proc(c: rl.Color, factor: f32) -> rl.Color {
	return rl.Color{
		u8(f32(c.r) * factor),
		u8(f32(c.g) * factor),
		u8(f32(c.b) * factor),
		c.a,
	}
}

VIS_DIM :: f32(0.35)

// ---- realm palettes --------------------------------------------------------

RealmColors :: struct {
	bg, wall, floor: rl.Color,
}

realm_colors :: proc(r: Realm) -> RealmColors {
	switch r {
	case .Midgard:      return RealmColors{bg = { 12,  12,  18, 255}, wall = { 90,  80,  70, 255}, floor = { 55,  55,  65, 255}}
	case .Asgard:       return RealmColors{bg = { 18,  16,  30, 255}, wall = {170, 140,  80, 255}, floor = { 70,  65,  90, 255}}
	case .Jotunheim:    return RealmColors{bg = { 16,  22,  30, 255}, wall = {130, 140, 160, 255}, floor = { 60,  70,  90, 255}}
	case .Niflheim:     return RealmColors{bg = { 22,  30,  40, 255}, wall = {170, 200, 220, 255}, floor = { 80, 100, 120, 255}}
	case .Muspelheim:   return RealmColors{bg = { 30,  10,  10, 255}, wall = {210,  90,  40, 255}, floor = {120,  50,  30, 255}}
	case .Alfheim:      return RealmColors{bg = { 14,  28,  22, 255}, wall = {180, 220, 170, 255}, floor = { 70, 110,  90, 255}}
	case .Svartalfheim: return RealmColors{bg = { 10,  10,  14, 255}, wall = { 80,  70,  95, 255}, floor = { 38,  40,  55, 255}}
	case .Vanaheim:     return RealmColors{bg = { 18,  30,  24, 255}, wall = {140, 170, 140, 255}, floor = { 70,  95,  80, 255}}
	case .Helheim:      return RealmColors{bg = { 12,   6,  14, 255}, wall = { 90,  50,  70, 255}, floor = { 40,  20,  35, 255}}
	}
	return RealmColors{bg = PALETTE.bg, wall = PALETTE.wall, floor = PALETTE.floor}
}

// ---- world drawing ---------------------------------------------------------

draw_map :: proc(g: ^Game) {
	ox, oy := map_origin(g)
	colors := realm_colors(g.realm)
	for y in 0 ..< MAP_H {
		for x in 0 ..< MAP_W {
			i := y * MAP_W + x
			if !g.explored[i] { continue } // never seen → leave as background
			factor: f32 = VIS_DIM
			if g.visible[i] { factor = 1.0 }
			px := ox + i32(x) * TILE_PX
			py := oy + i32(y) * TILE_PX
			switch g.tiles[i] {
			case .Wall:
				draw_glyph("#", px, py, TILE_PX, dim(colors.wall, factor))
			case .Floor:
				draw_glyph(".", px, py, TILE_PX, dim(colors.floor, factor))
			case .Stairs_Down:
				draw_glyph(">", px, py, TILE_PX, dim(PALETTE.stairs, factor))
			}
		}
	}
}

draw_items :: proc(g: ^Game) {
	ox, oy := map_origin(g)
	for &it in g.items {
		if !g.visible[it.y * MAP_W + it.x] { continue }
		px := ox + i32(it.x) * TILE_PX
		py := oy + i32(it.y) * TILE_PX
		draw_glyph(item_glyph(it.kind), px, py, TILE_PX, item_color(it.kind))
	}
}

draw_entity :: proc(g: ^Game, e: ^Entity) {
	if !e.alive { return }
	ox, oy := map_origin(g)
	px := ox + i32(e.x) * TILE_PX
	py := oy + i32(e.y) * TILE_PX
	col := e.color
	if e.flash_frames > 0 {
		col = HIT_FLASH_COLOR
	}
	draw_glyph(e.glyph, px, py, TILE_PX, col)
}

draw_entities :: proc(g: ^Game) {
	// only draw enemies the player can currently see
	for &e in g.enemies {
		if !e.alive { continue }
		if !g.visible[e.y * MAP_W + e.x] { continue }
		draw_entity(g, &e)
	}
	draw_entity(g, &g.player) // hero is always at the centre of FOV
}

// ---- UI chrome -------------------------------------------------------------

draw_top_bar :: proc(g: ^Game) {
	rl.DrawRectangle(0, 0, WINDOW_W, UI_TOP_PX - 4, PALETTE.ui_panel)
	title := fmt.ctprintf(
		"ASGARD  -  %s  -  Depth %d  -  Turn %d",
		realm_name(g.realm), g.depth, g.turn,
	)
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

	// Pack
	pack_y := i32(UI_TOP_PX + 120)
	rl.DrawText(
		fmt.ctprintf("Pack  (%d/%d)", len(g.inventory), INVENTORY_CAP),
		x + 12, pack_y, 16, PALETTE.ui_fg,
	)
	for kind, i in g.inventory {
		line := fmt.ctprintf(" %d  %s", i + 1, item_name(kind))
		rl.DrawText(line, x + 12, pack_y + 22 + i32(i) * 18, 14, item_color(kind))
	}

	hint_y := i32(UI_TOP_PX + 260)
	rl.DrawText("Controls",            x + 12, hint_y,        16, PALETTE.ui_fg)
	rl.DrawText("Arrows / h j k l",    x + 12, hint_y + 24,   14, PALETTE.ui_dim)
	rl.DrawText("y u b n  diagonals",  x + 12, hint_y + 44,   14, PALETTE.ui_dim)
	rl.DrawText(".  wait",             x + 12, hint_y + 64,   14, PALETTE.ui_dim)
	rl.DrawText("1-6  use pack slot",  x + 12, hint_y + 84,   14, PALETTE.ui_dim)
	rl.DrawText("R  reshape realm",    x + 12, hint_y + 104,  14, PALETTE.ui_dim)
	rl.DrawText("F5  save",            x + 12, hint_y + 124,  14, PALETTE.ui_dim)
	rl.DrawText("F9  load",            x + 12, hint_y + 144,  14, PALETTE.ui_dim)
	rl.DrawText("Esc  menu",           x + 12, hint_y + 164,  14, PALETTE.ui_dim)
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
	hint: cstring = "press R to rise in a new realm  -  Esc for menu"
	mw := rl.MeasureText(msg, 56)
	hw := rl.MeasureText(hint, 20)
	rl.DrawText(msg,  (WINDOW_W - mw) / 2, WINDOW_H / 2 - 60, 56, PALETTE.hp_low)
	rl.DrawText(hint, (WINDOW_W - hw) / 2, WINDOW_H / 2 + 10, 20, PALETTE.ui_fg)
}

draw_victory :: proc(g: ^Game) {
	if !g.won { return }
	// Warm pale tint (vs the dead screen's red)
	rl.DrawRectangle(0, 0, WINDOW_W, WINDOW_H, {30, 20, 40, 170})
	msg : cstring = "RAGNAROK ENDS"
	sub : cstring = "Hel has fallen. The Nine Realms exhale."
	hint: cstring = "press R for a new dawn  -  Esc for menu"
	mw := rl.MeasureText(msg, 56)
	sw := rl.MeasureText(sub, 22)
	hw := rl.MeasureText(hint, 20)
	rl.DrawText(msg,  (WINDOW_W - mw) / 2, WINDOW_H / 2 - 80, 56, PALETTE.player)
	rl.DrawText(sub,  (WINDOW_W - sw) / 2, WINDOW_H / 2 - 10, 22, PALETTE.hel)
	rl.DrawText(hint, (WINDOW_W - hw) / 2, WINDOW_H / 2 + 30, 20, PALETTE.ui_fg)
}

// ---- frame -----------------------------------------------------------------

render :: proc(g: ^Game) {
	rl.BeginDrawing()
	rl.ClearBackground(realm_colors(g.realm).bg)
	draw_top_bar(g)
	draw_map(g)
	draw_items(g)
	draw_entities(g)
	draw_sidebar(g)
	draw_log(g)
	draw_game_over(g)
	draw_victory(g)
	draw_menu(g)
	rl.EndDrawing()
	free_all(context.temp_allocator)
}
