package asgard

import "core:fmt"
import rl "vendor:raylib"

WINDOW_W :: 1280
WINDOW_H :: 720

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
		tick_anim(&g)
		render(&g)
	}

	fmt.printfln("Farewell. You walked %d turns through %s.", g.turn, realm_name(g.realm))
}
