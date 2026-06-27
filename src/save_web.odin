#+build js

package asgard

save_game :: proc(g: ^Game) {
	log_msg(g, "Saving is unavailable in the browser build.")
}

load_game :: proc(g: ^Game) {
	log_msg(g, "Loading is unavailable in the browser build.")
}
