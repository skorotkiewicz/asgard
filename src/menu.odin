package asgard

// In-game menu overlay. Toggled with Esc. While open it absorbs every
// keystroke (movement, items, descent — all paused) so the game can't
// advance behind it. The menu renders on top of everything else.

import rl "vendor:raylib"

MenuAction :: enum {
	Resume,
	New_Game,
	Exit,
}

MENU_ITEMS := [?]MenuAction{.Resume, .New_Game, .Exit}

menu_label :: proc(a: MenuAction) -> cstring {
	switch a {
	case .Resume:   return "Resume"
	case .New_Game: return "New Game"
	case .Exit:     return "Exit"
	}
	return "?"
}

menu_open :: proc(g: ^Game) {
	g.menu_open      = true
	g.menu_selection = 0
	cancel_hold() // drop any held movement key so we don't auto-walk on resume
}

menu_close :: proc(g: ^Game) {
	g.menu_open = false
}

// Called first thing in handle_input. Returns true if the menu absorbed input
// for this frame (so the caller should NOT process normal gameplay input).
menu_input :: proc(g: ^Game) -> bool {
	if !g.menu_open { return false }

	n := len(MENU_ITEMS)

	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.K) {
		g.menu_selection -= 1
		if g.menu_selection < 0 { g.menu_selection = n - 1 }
		return true
	}
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.J) {
		g.menu_selection += 1
		if g.menu_selection >= n { g.menu_selection = 0 }
		return true
	}
	if rl.IsKeyPressed(.ESCAPE) {
		menu_close(g)
		return true
	}
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE) {
		switch MENU_ITEMS[g.menu_selection] {
		case .Resume:
			menu_close(g)
		case .New_Game:
			menu_close(g)
			regenerate(g)
		case .Exit:
			g.quit = true
		}
		return true
	}

	return true // everything else is swallowed while menu is open
}

draw_menu :: proc(g: ^Game) {
	if !g.menu_open { return }

	// Dim the world behind the panel
	rl.DrawRectangle(0, 0, WINDOW_W, WINDOW_H, {0, 0, 0, 170})

	// Title
	title : cstring = "ASGARD"
	tw := rl.MeasureText(title, 56)
	rl.DrawText(title, (WINDOW_W - tw) / 2, WINDOW_H / 2 - 200, 56, PALETTE.player)

	// Menu items, vertically centred around mid-screen
	ITEM_SIZE    :: i32(32)
	ITEM_SPACING :: i32(60)
	start_y := WINDOW_H / 2 - i32(len(MENU_ITEMS)) * ITEM_SPACING / 2

	for action, i in MENU_ITEMS {
		label := menu_label(action)
		w := rl.MeasureText(label, ITEM_SIZE)
		x := (WINDOW_W - w) / 2
		y := start_y + i32(i) * ITEM_SPACING

		col := PALETTE.ui_dim
		if i == g.menu_selection {
			col = PALETTE.player
			rl.DrawText(">", x - 36, y, ITEM_SIZE, col)
			rl.DrawText("<", x + w + 12, y, ITEM_SIZE, col)
		}
		rl.DrawText(label, x, y, ITEM_SIZE, col)
	}

	// Hint
	hint : cstring = "Up / Down  navigate    Enter  select    Esc  resume"
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, (WINDOW_W - hw) / 2, WINDOW_H - 80, 16, PALETTE.ui_dim)
}
