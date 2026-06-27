#+build !js

package asgard

import "core:strings"
import "core:testing"

@(test)
save_roundtrip_test :: proc(t: ^testing.T) {
	g := Game{}
	g.realm  = .Muspelheim
	g.depth  = 5
	g.turn   = 42
	g.seed   = 12345
	g.player = make_player()
	g.player.x = 2
	g.player.y = 3
	g.player.hp = 11

	for i in 0 ..< len(g.tiles) {
		g.tiles[i] = .Floor
		g.explored[i] = i % 2 == 0
	}
	g.tiles[0] = .Wall
	g.tiles[7] = .Stairs_Down

	g.enemies   = make([dynamic]Entity,   0, 2)
	g.items     = make([dynamic]Item,     0, 2)
	g.inventory = make([dynamic]ItemKind, 0, INVENTORY_CAP)
	defer {
		delete(g.enemies)
		delete(g.items)
		delete(g.inventory)
	}

	append(&g.enemies, make_troll(8, 9))
	g.enemies[0].hp = 7
	append(&g.items, Item{x = 4, y = 5, kind = .Rune_Fire})
	append(&g.inventory, ItemKind.Mead)
	append(&g.inventory, ItemKind.Scroll_Recall)

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	save_write_game(&b, &g)

	state, ok := load_save_state(transmute([]byte)strings.to_string(b))
	if !testing.expect(t, ok) { return }
	defer save_state_destroy(&state)

	testing.expect_value(t, state.realm, g.realm)
	testing.expect_value(t, state.depth, g.depth)
	testing.expect_value(t, state.turn, g.turn)
	testing.expect_value(t, state.seed, g.seed)
	testing.expect_value(t, state.player.x, g.player.x)
	testing.expect_value(t, state.player.hp, g.player.hp)
	testing.expect_value(t, state.tiles[0], Tile.Wall)
	testing.expect_value(t, state.tiles[7], Tile.Stairs_Down)
	testing.expect_value(t, state.explored[2], true)
	testing.expect_value(t, len(state.enemies), 1)
	testing.expect_value(t, state.enemies[0].name, "troll")
	testing.expect_value(t, state.enemies[0].hp, 7)
	testing.expect_value(t, len(state.items), 1)
	testing.expect_value(t, state.items[0].kind, ItemKind.Rune_Fire)
	testing.expect_value(t, len(state.inventory), 2)
	testing.expect_value(t, state.inventory[1], ItemKind.Scroll_Recall)
}
