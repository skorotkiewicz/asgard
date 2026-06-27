#+build !js

package asgard

import "core:fmt"
import "core:os"
import "core:strings"

save_game :: proc(g: ^Game) {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	save_write_game(&b, g)

	if err := os.write_entire_file(SAVE_FILE, strings.to_string(b)); err != nil {
		log_msg(g, "Could not save game.")
		return
	}
	log_msg(g, fmt.tprintf("Game saved to %s.", SAVE_FILE))
}

load_game :: proc(g: ^Game) {
	data, err := os.read_entire_file(SAVE_FILE, context.temp_allocator)
	if err != nil {
		log_msg(g, "No save file found.")
		return
	}

	state, ok := load_save_state(data)
	if !ok {
		log_msg(g, "Save file is unreadable.")
		return
	}
	apply_save_state(g, &state)
	log_msg(g, fmt.tprintf("Game loaded from %s.", SAVE_FILE))
}
