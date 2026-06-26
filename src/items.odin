package asgard

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

INVENTORY_CAP   :: 6
ITEM_SPAWN_PCT  :: 40

MEAD_HEAL       :: 8
RUNE_FIRE_DMG   :: 4
THROW_AXE_DMG   :: 7

ItemKind :: enum {
	Mead,
	Rune_Fire,
	Rune_Sight,
	Weapon,
	Armor,
	Throwing_Axe,
	Scroll_Recall,
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
	case .Weapon:     return "weapon"
	case .Armor:      return "armor"
	case .Throwing_Axe:  return "throwing axe"
	case .Scroll_Recall: return "scroll of recall"
	}
	return "?"
}

item_glyph :: proc(k: ItemKind) -> cstring {
	switch k {
	case .Mead:       return "!"
	case .Rune_Fire:  return "?"
	case .Rune_Sight: return "?"
	case .Weapon:     return "/"
	case .Armor:      return "["
	case .Throwing_Axe:  return "}"
	case .Scroll_Recall: return "~"
	}
	return "?"
}

item_color :: proc(k: ItemKind) -> rl.Color {
	switch k {
	case .Mead:       return {210, 160,  70, 255} // amber
	case .Rune_Fire:  return {220, 110,  60, 255} // red-orange
	case .Rune_Sight: return {160, 200, 230, 255} // pale blue
	case .Weapon:     return {210, 210, 210, 255}
	case .Armor:      return {150, 170, 190, 255}
	case .Throwing_Axe:  return {190, 160, 120, 255}
	case .Scroll_Recall: return {190, 150, 230, 255}
	}
	return {255, 255, 255, 255}
}

// ---- spawn weighting -------------------------------------------------------

pick_item_kind :: proc() -> ItemKind {
	r := rand.int_max(100)
	if r < 35 { return .Mead }
	if r < 52 { return .Rune_Fire }
	if r < 68 { return .Rune_Sight }
	if r < 80 { return .Weapon }
	if r < 90 { return .Armor }
	if r < 97 { return .Throwing_Axe }
	return .Scroll_Recall
}

// ---- queries ---------------------------------------------------------------

// Returns the index of a ground item at (x,y), or -1 if none.
item_at :: proc(g: ^Game, x, y: int) -> int {
	for it, i in g.items {
		if it.x == x && it.y == y { return i }
	}
	return -1
}

nearest_visible_enemy :: proc(g: ^Game) -> ^Entity {
	best: ^Entity
	best_dist := max(int)
	for &e in g.enemies {
		if !e.alive { continue }
		if !g.visible[e.y * MAP_W + e.x] { continue }
		d := cheb_dist(g.player.x, g.player.y, e.x, e.y)
		if d < best_dist {
			best = &e
			best_dist = d
		}
	}
	return best
}

stairs_down_at :: proc(g: ^Game) -> (x, y: int, ok: bool) {
	for t, i in g.tiles {
		if t == .Stairs_Down {
			return i % MAP_W, i / MAP_W, true
		}
	}
	return 0, 0, false
}

hurt_enemy_from_item :: proc(g: ^Game, e: ^Entity, dmg: int) {
	e.hp -= dmg
	e.flash_frames = HIT_FLASH_FRAMES
	log_msg(g, fmt.tprintf("The %s reels (%d dmg).", e.name, dmg))
	if e.hp <= 0 {
		defeat_entity(g, e)
	}
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
	play_sound(.Pickup)
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
			hurt_enemy_from_item(g, &e, RUNE_FIRE_DMG)
			hit += 1
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

	case .Weapon:
		g.player.power += 1
		log_msg(g, fmt.tprintf("You heft a better weapon. (Power %d)", g.player.power))

	case .Armor:
		g.player.armor += 1
		log_msg(g, fmt.tprintf("You buckle on stronger armor. (Armor %d)", g.player.armor))

	case .Throwing_Axe:
		if target := nearest_visible_enemy(g); target != nil {
			log_msg(g, fmt.tprintf("You hurl a throwing axe at the %s.", target.name))
			hurt_enemy_from_item(g, target, THROW_AXE_DMG)
		} else {
			log_msg(g, "You throw the axe into empty dark.")
		}

	case .Scroll_Recall:
		if sx, sy, ok := stairs_down_at(g); ok {
			g.player.x = sx
			g.player.y = sy
			g.descend_pending = true
			log_msg(g, "The scroll drags you to Yggdrasil's stairs.")
		} else {
			log_msg(g, "The scroll fades; no deeper root answers.")
		}
	}

	ordered_remove(&g.inventory, slot)
	play_sound(.Use_Item)
	return true
}
