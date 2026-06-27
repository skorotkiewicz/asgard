#+build js

package asgard

import "core:fmt"
import rl "vendor:raylib"

@(private = "file")
web_game: Game

@(private = "file")
web_running := false

main :: proc() {
	rl.SetConfigFlags({.WINDOW_HIGHDPI, .VSYNC_HINT})
	rl.InitWindow(WINDOW_W, WINDOW_H, "Asgard")
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL)

	audio_init()
	web_game = new_game(fresh_seed())
	web_running = true
}

@export
step :: proc(delta_time: f64) -> bool {
	if !web_running {
		return false
	}

	if rl.WindowShouldClose() || web_game.quit {
		fmt.printfln("Farewell. You walked %d turns through %s.", web_game.turn, realm_name(web_game.realm))
		destroy_game(&web_game)
		audio_shutdown()
		rl.CloseWindow()
		web_running = false
		return false
	}

	handle_input(&web_game)
	tick_anim(&web_game)
	tick_music()
	render(&web_game)
	return true
}
