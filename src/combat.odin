package asgard

import "core:fmt"
import "core:math/rand"

// ---- entity factories ------------------------------------------------------

make_player :: proc() -> Entity {
	return Entity{
		glyph        = "@",
		name         = "Wanderer",
		color        = PALETTE.player,
		hp           = 20,
		hp_max       = 20,
		power        = 4,
		armor        = 1,
		alive        = true,
		attack_sound = .Player_Strike,
	}
}

make_draugr :: proc(x, y: int) -> Entity {
	return Entity{
		x = x, y = y,
		glyph        = "d",
		name         = "draugr",
		color        = PALETTE.draugr,
		hp           = 6,
		hp_max       = 6,
		power        = 3,
		armor        = 0,
		alive        = true,
		attack_sound = .Draugr_Strike,
	}
}

// Jotunn — slow, heavy. Skips every other turn (cooldown_max=1) but hits
// hard and has armor. Player can kite them.
make_jotunn :: proc(x, y: int) -> Entity {
	return Entity{
		x = x, y = y,
		glyph         = "J",
		name          = "jotunn",
		color         = PALETTE.jotunn,
		hp            = 10,
		hp_max        = 10,
		power         = 4,
		armor         = 2,
		alive         = true,
		attack_sound  = .Jotunn_Strike,
		cooldown_max  = 1,
	}
}

// Hound of Hel — fast, fragile. Takes two actions per turn (move + attack,
// or attack twice) so they close distance fast despite low HP. Spawn in pairs.
make_hound :: proc(x, y: int) -> Entity {
	return Entity{
		x = x, y = y,
		glyph         = "h",
		name          = "hound",
		color         = PALETTE.hound,
		hp            = 3,
		hp_max        = 3,
		power         = 2,
		armor         = 0,
		alive         = true,
		attack_sound  = .Hound_Strike,
		extra_actions = 1,
	}
}

make_troll :: proc(x, y: int) -> Entity {
	return Entity{
		x = x, y = y,
		glyph         = "T",
		name          = "troll",
		color         = PALETTE.troll,
		hp            = 14,
		hp_max        = 14,
		power         = 5,
		armor         = 1,
		alive         = true,
		attack_sound  = .Jotunn_Strike,
		cooldown_max  = 1,
	}
}

make_wraith :: proc(x, y: int) -> Entity {
	return Entity{
		x = x, y = y,
		glyph         = "w",
		name          = "wraith",
		color         = PALETTE.wraith,
		hp            = 5,
		hp_max        = 5,
		power         = 3,
		armor         = 1,
		alive         = true,
		attack_sound  = .Draugr_Strike,
		extra_actions = 1,
	}
}

make_fenrir :: proc(x, y: int) -> Entity {
	return Entity{
		x = x, y = y,
		glyph         = "F",
		name          = "fenrir",
		color         = PALETTE.fenrir,
		hp            = 12,
		hp_max        = 12,
		power         = 4,
		armor         = 1,
		alive         = true,
		attack_sound  = .Hound_Strike,
		extra_actions = 1,
	}
}

make_surtr :: proc(x, y: int) -> Entity {
	return Entity{
		x = x, y = y,
		glyph        = "S",
		name         = "surtr",
		color        = PALETTE.surtr,
		hp           = 16,
		hp_max       = 16,
		power        = 5,
		armor        = 1,
		alive        = true,
		attack_sound = .Jotunn_Strike,
	}
}

make_jormungandr :: proc(x, y: int) -> Entity {
	return Entity{
		x = x, y = y,
		glyph         = "M",
		name          = "jormungandr",
		color         = PALETTE.jormungandr,
		hp            = 18,
		hp_max        = 18,
		power         = 4,
		armor         = 2,
		alive         = true,
		attack_sound  = .Hel_Strike,
		cooldown_max  = 1,
	}
}

// Hel — queen of the dishonoured dead, sole boss. Acts twice per turn like
// a hound but hits like a small jotunn. Killing her wins the run.
make_hel :: proc(x, y: int) -> Entity {
	return Entity{
		x = x, y = y,
		glyph         = "H",
		name          = "Hel",
		color         = PALETTE.hel,
		hp            = 14,
		hp_max        = 14,
		power         = 4,
		armor         = 1,
		alive         = true,
		attack_sound  = .Hel_Strike,
		extra_actions = 1,
		is_boss       = true,
	}
}

EnemyKind :: enum {
	Draugr,
	Jotunn,
	Hound,
	Troll,
	Wraith,
	Fenrir,
	Surtr,
	Jormungandr,
	Hel,
}

make_enemy :: proc(kind: EnemyKind, x, y: int) -> Entity {
	switch kind {
	case .Draugr:      return make_draugr(x, y)
	case .Jotunn:      return make_jotunn(x, y)
	case .Hound:       return make_hound(x, y)
	case .Troll:       return make_troll(x, y)
	case .Wraith:      return make_wraith(x, y)
	case .Fenrir:      return make_fenrir(x, y)
	case .Surtr:       return make_surtr(x, y)
	case .Jormungandr: return make_jormungandr(x, y)
	case .Hel:         return make_hel(x, y)
	}
	return make_draugr(x, y)
}

// ---- queries ---------------------------------------------------------------

// Returns pointer to a live enemy at (x,y), or nil. Pointer is stable so long
// as g.enemies isn't appended to between the lookup and use.
enemy_at :: proc(g: ^Game, x, y: int) -> ^Entity {
	for &e in g.enemies {
		if e.alive && e.x == x && e.y == y { return &e }
	}
	return nil
}

is_walkable :: proc(g: ^Game, x, y: int) -> bool {
	if tile_at(g, x, y) == .Wall { return false }
	if enemy_at(g, x, y) != nil  { return false }
	return true
}

// ---- math helpers ----------------------------------------------------------

sign :: proc(n: int) -> int {
	if n > 0 { return 1 }
	if n < 0 { return -1 }
	return 0
}

abs_int :: proc(n: int) -> int {
	if n < 0 { return -n }
	return n
}

cheb_dist :: proc(ax, ay, bx, by: int) -> int {
	return max(abs_int(ax - bx), abs_int(ay - by))
}

// ---- combat ----------------------------------------------------------------

attack :: proc(g: ^Game, attacker, defender: ^Entity) {
	roll := rand.int_max(3) - 1 // -1, 0, +1
	dmg  := max(1, attacker.power - defender.armor + roll)
	defender.hp -= dmg

	// visual feedback: defender flashes red; if WE landed the hit, screen shakes
	defender.flash_frames = HIT_FLASH_FRAMES
	if attacker == &g.player {
		g.shake_frames = SHAKE_MAX_FRAMES
	}
	play_sound(attacker.attack_sound)

	if attacker == &g.player {
		log_msg(g, fmt.tprintf("You strike the %s (%d dmg).", defender.name, dmg))
	} else if defender == &g.player {
		log_msg(g, fmt.tprintf("The %s lunges at you (%d dmg).", attacker.name, dmg))
	} else {
		log_msg(g, fmt.tprintf("%s hits %s (%d).", attacker.name, defender.name, dmg))
	}

	if defender.hp <= 0 {
		defender.alive = false
		if defender == &g.player {
			log_msg(g, "You have fallen. The realm grows still.")
			g.dead = true
		} else if defender.is_boss {
			log_msg(g, fmt.tprintf("%s falls. The cold lifts from your bones.", defender.name))
			log_msg(g, "Ragnarok ends. The Nine Realms exhale.")
			g.won = true
		} else {
			log_msg(g, fmt.tprintf("The %s crumbles to dust.", defender.name))
		}
	}
}

// ---- AI --------------------------------------------------------------------

// One "tick" of enemy behaviour: attack player if adjacent, else greedy chase.
take_one_action :: proc(g: ^Game, e: ^Entity) {
	dist := cheb_dist(e.x, e.y, g.player.x, g.player.y)

	if dist == 1 {
		attack(g, e, &g.player)
		return
	}

	dx := sign(g.player.x - e.x)
	dy := sign(g.player.y - e.y)

	if dx != 0 && dy != 0 && is_walkable(g, e.x + dx, e.y + dy) {
		e.x += dx; e.y += dy
		return
	}
	if dx != 0 && is_walkable(g, e.x + dx, e.y) {
		e.x += dx
		return
	}
	if dy != 0 && is_walkable(g, e.x, e.y + dy) {
		e.y += dy
		return
	}
	// blocked: shuffle awkwardly (skip)
}

enemy_turn :: proc(g: ^Game) {
	for &e in g.enemies {
		if !e.alive { continue }
		// only act if currently in the player's line of sight
		if !g.visible[e.y * MAP_W + e.x] { continue }

		// Slow enemies skip turns via cooldown
		if e.cooldown > 0 {
			e.cooldown -= 1
			continue
		}

		take_one_action(g, &e)
		if g.dead { return }

		// Fast enemies take additional actions per turn
		for _ in 0 ..< e.extra_actions {
			take_one_action(g, &e)
			if g.dead { return }
		}

		if e.cooldown_max > 0 {
			e.cooldown = e.cooldown_max
		}
	}
}
