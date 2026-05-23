package asgard

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

INVENTORY_CAP   :: 6
ITEM_SPAWN_PCT  :: 40

MEAD_HEAL       :: 8
RUNE_FIRE_DMG   :: 4

ItemKind :: enum {
	Mead,
	Rune_Fire,
	Rune_Sight,
}

Item :: struct {
	x, y: int,
	kind: ItemKind,
}

// ---- presentation ----------------------------------------------------------

item_name :: proc(k: ItemKind) -> string {
	switch k {
	case .Mead:       return "mead"
	case .Rune_Fire:  return "rune of fire"
	case .Rune_Sight: return "rune of sight"
	}
	return "?"
}

item_glyph :: proc(k: ItemKind) -> cstring {
	switch k {
	case .Mead:       return "!"
	case .Rune_Fire:  return "?"
	case .Rune_Sight: return "?"
	}
	return "?"
}

item_color :: proc(k: ItemKind) -> rl.Color {
	switch k {
	case .Mead:       return {210, 160,  70, 255} // amber
	case .Rune_Fire:  return {220, 110,  60, 255} // red-orange
	case .Rune_Sight: return {160, 200, 230, 255} // pale blue
	}
	return {255, 255, 255, 255}
}

// ---- spawn weighting -------------------------------------------------------

pick_item_kind :: proc() -> ItemKind {
	r := rand.int_max(100)
	if r < 50 { return .Mead }       // 50%
	if r < 75 { return .Rune_Fire }  // 25%
	return .Rune_Sight               // 25%
}

// ---- queries ---------------------------------------------------------------

// Returns the index of a ground item at (x,y), or -1 if none.
item_at :: proc(g: ^Game, x, y: int) -> int {
	for it, i in g.items {
		if it.x == x && it.y == y { return i }
	}
	return -1
}

// ---- pickup / use ----------------------------------------------------------

// Pick up the item at index `idx` in g.items if there's room in the pack.
// Logs the result either way. Never costs a turn — stepping already did.
pickup_item :: proc(g: ^Game, idx: int) {
	kind := g.items[idx].kind
	if len(g.inventory) >= INVENTORY_CAP {
		log_msg(g, fmt.tprintf("Your pack is full. The %s stays.", item_name(kind)))
		return
	}
	append(&g.inventory, kind)
	unordered_remove(&g.items, idx)
	log_msg(g, fmt.tprintf("You pick up the %s.", item_name(kind)))
}

// Consume the inventory slot. Returns true if the action actually fired
// (a turn was taken). Returns false if the slot was empty.
use_item :: proc(g: ^Game, slot: int) -> bool {
	if slot < 0 || slot >= len(g.inventory) { return false }
	kind := g.inventory[slot]

	switch kind {
	case .Mead:
		before := g.player.hp
		g.player.hp = min(g.player.hp + MEAD_HEAL, g.player.hp_max)
		gained := g.player.hp - before
		log_msg(g, fmt.tprintf("You quaff mead. (+%d HP)", gained))

	case .Rune_Fire:
		hit := 0
		for &e in g.enemies {
			if !e.alive { continue }
			if !g.visible[e.y * MAP_W + e.x] { continue }
			e.hp -= RUNE_FIRE_DMG
			hit += 1
			if e.hp <= 0 {
				e.alive = false
				log_msg(g, fmt.tprintf("Fire devours the %s.", e.name))
			}
		}
		if hit == 0 {
			log_msg(g, "The rune of fire flares uselessly; nothing in sight to burn.")
		} else {
			log_msg(g, fmt.tprintf("A rune of fire blazes; %d foes seared.", hit))
		}

	case .Rune_Sight:
		for i in 0 ..< len(g.explored) {
			g.explored[i] = true
		}
		log_msg(g, "A rune of sight unrolls the realm before you.")
	}

	ordered_remove(&g.inventory, slot)
	return true
}
