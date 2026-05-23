package asgard

// In-game menu overlay. Toggled with Esc. While open it absorbs every
// keystroke (movement, items, descent — all paused) so the game can't
// advance behind it. The menu has two screens: Main and Settings.
// Esc backs out one level (Settings → Main → Closed).

import rl "vendor:raylib"

MenuScreen :: enum {
	Main,
	Settings,
}

MenuAction :: enum {
	Resume,
	Settings,
	New_Game,
	Exit,
	Toggle_Music,
	Toggle_SFX,
	Back,
}

MAIN_MENU_ITEMS     := [?]MenuAction{.Resume, .Settings, .New_Game, .Exit}
SETTINGS_MENU_ITEMS := [?]MenuAction{.Toggle_Music, .Toggle_SFX, .Back}

menu_label :: proc(a: MenuAction) -> cstring {
	switch a {
	case .Resume:        return "Resume"
	case .Settings:      return "Settings"
	case .New_Game:      return "New Game"
	case .Exit:          return "Exit"
	case .Toggle_Music:
		if is_music_enabled() { return "Music:     ON" }
		return "Music:     OFF"
	case .Toggle_SFX:
		if is_sfx_enabled() { return "Sound FX:  ON" }
		return "Sound FX:  OFF"
	case .Back:          return "Back"
	}
	return "?"
}

current_items :: proc(g: ^Game) -> []MenuAction {
	switch g.menu_screen {
	case .Main:     return MAIN_MENU_ITEMS[:]
	case .Settings: return SETTINGS_MENU_ITEMS[:]
	}
	return MAIN_MENU_ITEMS[:]
}

menu_open :: proc(g: ^Game) {
	g.menu_open      = true
	g.menu_screen    = .Main
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

	items := current_items(g)
	n := len(items)

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
		// Back out one level: Settings → Main, Main → closed.
		switch g.menu_screen {
		case .Settings:
			g.menu_screen    = .Main
			g.menu_selection = 0
		case .Main:
			menu_close(g)
		}
		return true
	}
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE) {
		activate_menu_item(g, items[g.menu_selection])
		return true
	}

	return true // everything else is swallowed while menu is open
}

@(private="file")
activate_menu_item :: proc(g: ^Game, action: MenuAction) {
	switch action {
	case .Resume:
		menu_close(g)
	case .Settings:
		g.menu_screen    = .Settings
		g.menu_selection = 0
	case .New_Game:
		menu_close(g)
		regenerate(g)
	case .Exit:
		g.quit = true
	case .Toggle_Music:
		set_music_enabled(!is_music_enabled())
	case .Toggle_SFX:
		set_sfx_enabled(!is_sfx_enabled())
		// Both: stay on Settings; the label flip provides feedback.
	case .Back:
		g.menu_screen    = .Main
		g.menu_selection = 0
	}
}

draw_menu :: proc(g: ^Game) {
	if !g.menu_open { return }

	// Dim the world behind the panel
	rl.DrawRectangle(0, 0, WINDOW_W, WINDOW_H, {0, 0, 0, 170})

	// Title varies by screen
	title: cstring
	switch g.menu_screen {
	case .Main:     title = "ASGARD"
	case .Settings: title = "SETTINGS"
	}
	tw := rl.MeasureText(title, 56)
	rl.DrawText(title, (WINDOW_W - tw) / 2, WINDOW_H / 2 - 200, 56, PALETTE.player)

	// Menu items, vertically centred around mid-screen
	ITEM_SIZE    :: i32(32)
	ITEM_SPACING :: i32(60)
	items := current_items(g)
	start_y := WINDOW_H / 2 - i32(len(items)) * ITEM_SPACING / 2

	for action, i in items {
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

	// Hint, varies by screen
	hint: cstring
	switch g.menu_screen {
	case .Main:     hint = "Up / Down  navigate    Enter  select    Esc  resume"
	case .Settings: hint = "Up / Down  navigate    Enter  toggle    Esc  back"
	}
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, (WINDOW_W - hw) / 2, WINDOW_H - 80, 16, PALETTE.ui_dim)
}
