package asgard

import "core:fmt"
import "core:strconv"
import "core:strings"

SAVE_FILE    :: "asgard.save"
SAVE_VERSION :: 1

SAVE_MAX_ENEMIES :: 256
SAVE_MAX_ITEMS   :: 256

SaveState :: struct {
	tiles:     [MAP_W * MAP_H]Tile,
	explored:  [MAP_W * MAP_H]bool,
	player:    Entity,
	enemies:   [dynamic]Entity,
	items:     [dynamic]Item,
	inventory: [dynamic]ItemKind,
	realm:     Realm,
	depth:     int,
	turn:      int,
	seed:      u64,
	dead:      bool,
	won:       bool,
}

SaveReader :: struct {
	text: string,
}

bool_int :: proc(b: bool) -> int {
	if b { return 1 }
	return 0
}

int_bool :: proc(n: int) -> (bool, bool) {
	switch n {
	case 0: return false, true
	case 1: return true, true
	}
	return false, false
}

save_next :: proc(r: ^SaveReader) -> (string, bool) {
	return strings.fields_iterator(&r.text)
}

save_expect :: proc(r: ^SaveReader, tag: string) -> bool {
	tok, ok := save_next(r)
	return ok && tok == tag
}

save_read_int :: proc(r: ^SaveReader) -> (int, bool) {
	tok, ok := save_next(r)
	if !ok { return 0, false }
	return strconv.parse_int(tok)
}

save_read_u64 :: proc(r: ^SaveReader) -> (u64, bool) {
	tok, ok := save_next(r)
	if !ok { return 0, false }
	return strconv.parse_u64(tok)
}

save_read_bool :: proc(r: ^SaveReader) -> (bool, bool) {
	n, ok := save_read_int(r)
	if !ok { return false, false }
	return int_bool(n)
}

save_read_tile_map :: proc(r: ^SaveReader, tiles: ^[MAP_W * MAP_H]Tile) -> bool {
	tok, ok := save_next(r)
	if !ok || len(tok) != len(tiles^) { return false }
	for i in 0 ..< len(tiles^) {
		switch tok[i] {
		case '0': tiles^[i] = .Floor
		case '1': tiles^[i] = .Wall
		case '2': tiles^[i] = .Stairs_Down
		case:    return false
		}
	}
	return true
}

save_read_explored :: proc(r: ^SaveReader, explored: ^[MAP_W * MAP_H]bool) -> bool {
	tok, ok := save_next(r)
	if !ok || len(tok) != len(explored^) { return false }
	for i in 0 ..< len(explored^) {
		switch tok[i] {
		case '0': explored^[i] = false
		case '1': explored^[i] = true
		case:    return false
		}
	}
	return true
}

entity_kind_for_save :: proc(e: ^Entity) -> EnemyKind {
	switch e.name {
	case "draugr":      return .Draugr
	case "jotunn":      return .Jotunn
	case "hound":       return .Hound
	case "troll":       return .Troll
	case "wraith":      return .Wraith
	case "fenrir":      return .Fenrir
	case "surtr":       return .Surtr
	case "jormungandr": return .Jormungandr
	case "Hel":         return .Hel
	}
	return .Draugr
}

save_write_map :: proc(b: ^strings.Builder, g: ^Game) {
	strings.write_string(b, "tiles ")
	for t in g.tiles {
		strings.write_byte(b, byte(48 + int(t)))
	}
	strings.write_byte(b, 10)

	strings.write_string(b, "explored ")
	for seen in g.explored {
		if seen {
			strings.write_byte(b, '1')
		} else {
			strings.write_byte(b, '0')
		}
	}
	strings.write_byte(b, 10)
}

save_write_game :: proc(b: ^strings.Builder, g: ^Game) {
	fmt.sbprintfln(b, "ASGARD_SAVE %d", SAVE_VERSION)
	fmt.sbprintfln(b, "state %d %d %d %d %d %d", int(g.realm), g.depth, g.turn, g.seed, bool_int(g.dead), bool_int(g.won))
	fmt.sbprintfln(b, "player %d %d %d %d %d %d %d",
		g.player.x, g.player.y, g.player.hp, g.player.hp_max, g.player.power, g.player.armor, bool_int(g.player.alive),
	)
	save_write_map(b, g)

	fmt.sbprintfln(b, "enemies %d", len(g.enemies))
	for &e in g.enemies {
		fmt.sbprintfln(b, "enemy %d %d %d %d %d %d %d %d %d",
			int(entity_kind_for_save(&e)), e.x, e.y, e.hp, e.hp_max, e.power, e.armor, bool_int(e.alive), e.cooldown,
		)
	}

	fmt.sbprintfln(b, "items %d", len(g.items))
	for it in g.items {
		fmt.sbprintfln(b, "item %d %d %d", int(it.kind), it.x, it.y)
	}

	fmt.sbprintf(b, "inventory %d", len(g.inventory))
	for kind in g.inventory {
		fmt.sbprintf(b, " %d", int(kind))
	}
	strings.write_byte(b, 10)
}

save_state_destroy :: proc(s: ^SaveState) {
	delete(s.enemies)
	delete(s.items)
	delete(s.inventory)
}

save_valid_xy :: proc(x, y: int) -> bool {
	return x >= 0 && y >= 0 && x < MAP_W && y < MAP_H
}

load_save_state :: proc(data: []byte) -> (s: SaveState, ok: bool) {
	s.enemies   = make([dynamic]Entity,   0, 16)
	s.items     = make([dynamic]Item,     0, 16)
	s.inventory = make([dynamic]ItemKind, 0, INVENTORY_CAP)
	defer {
		if !ok {
			save_state_destroy(&s)
		}
	}

	r := SaveReader{text = string(data)}
	if !save_expect(&r, "ASGARD_SAVE") { return }
	version, version_ok := save_read_int(&r)
	if !version_ok || version != SAVE_VERSION { return }

	if !save_expect(&r, "state") { return }
	realm_i, realm_ok := save_read_int(&r)
	if !realm_ok || realm_i < 0 || realm_i > int(Realm.Helheim) { return }
	s.realm = Realm(realm_i)
	if s.depth, ok = save_read_int(&r); !ok { return }
	if s.turn,  ok = save_read_int(&r); !ok { return }
	if s.seed,  ok = save_read_u64(&r); !ok { return }
	if s.dead,  ok = save_read_bool(&r); !ok { return }
	if s.won,   ok = save_read_bool(&r); !ok { return }

	if !save_expect(&r, "player") { return }
	px, px_ok := save_read_int(&r)
	py, py_ok := save_read_int(&r)
	if !px_ok || !py_ok || !save_valid_xy(px, py) { return }
	s.player = make_player()
	s.player.x = px
	s.player.y = py
	if s.player.hp,     ok = save_read_int(&r); !ok { return }
	if s.player.hp_max, ok = save_read_int(&r); !ok || s.player.hp_max <= 0 { return }
	if s.player.power,  ok = save_read_int(&r); !ok { return }
	if s.player.armor,  ok = save_read_int(&r); !ok { return }
	if s.player.alive,  ok = save_read_bool(&r); !ok { return }

	if !save_expect(&r, "tiles") || !save_read_tile_map(&r, &s.tiles) { return }
	if s.tiles[s.player.y * MAP_W + s.player.x] == .Wall { return }
	if !save_expect(&r, "explored") || !save_read_explored(&r, &s.explored) { return }

	if !save_expect(&r, "enemies") { return }
	enemy_count, enemy_count_ok := save_read_int(&r)
	if !enemy_count_ok || enemy_count < 0 || enemy_count > SAVE_MAX_ENEMIES { return }
	for _ in 0 ..< enemy_count {
		if !save_expect(&r, "enemy") { return }
		kind_i, kind_ok := save_read_int(&r)
		x, x_ok := save_read_int(&r)
		y, y_ok := save_read_int(&r)
		if !kind_ok || kind_i < 0 || kind_i > int(EnemyKind.Hel) || !x_ok || !y_ok || !save_valid_xy(x, y) { return }
		e := make_enemy(EnemyKind(kind_i), x, y)
		if e.hp,     ok = save_read_int(&r); !ok { return }
		if e.hp_max, ok = save_read_int(&r); !ok || e.hp_max <= 0 { return }
		if e.power,  ok = save_read_int(&r); !ok { return }
		if e.armor,  ok = save_read_int(&r); !ok { return }
		if e.alive,  ok = save_read_bool(&r); !ok { return }
		if e.cooldown, ok = save_read_int(&r); !ok { return }
		append(&s.enemies, e)
	}

	if !save_expect(&r, "items") { return }
	item_count, item_count_ok := save_read_int(&r)
	if !item_count_ok || item_count < 0 || item_count > SAVE_MAX_ITEMS { return }
	for _ in 0 ..< item_count {
		if !save_expect(&r, "item") { return }
		kind_i, kind_ok := save_read_int(&r)
		x, x_ok := save_read_int(&r)
		y, y_ok := save_read_int(&r)
		if !kind_ok || kind_i < 0 || kind_i > int(ItemKind.Scroll_Recall) || !x_ok || !y_ok || !save_valid_xy(x, y) { return }
		append(&s.items, Item{x = x, y = y, kind = ItemKind(kind_i)})
	}

	if !save_expect(&r, "inventory") { return }
	inv_count, inv_count_ok := save_read_int(&r)
	if !inv_count_ok || inv_count < 0 || inv_count > INVENTORY_CAP { return }
	for _ in 0 ..< inv_count {
		kind_i, kind_ok := save_read_int(&r)
		if !kind_ok || kind_i < 0 || kind_i > int(ItemKind.Scroll_Recall) { return }
		append(&s.inventory, ItemKind(kind_i))
	}

	_, extra := save_next(&r)
	if extra { return }
	ok = true
	return
}

apply_save_state :: proc(g: ^Game, s: ^SaveState) {
	g.tiles    = s.tiles
	g.explored = s.explored
	for i in 0 ..< len(g.visible) {
		g.visible[i] = false
	}

	g.player = s.player
	g.realm  = s.realm
	g.depth  = s.depth
	g.turn   = s.turn
	g.seed   = s.seed
	g.dead   = s.dead
	g.won    = s.won

	delete(g.enemies)
	delete(g.items)
	delete(g.inventory)
	g.enemies   = s.enemies
	g.items     = s.items
	g.inventory = s.inventory
	s.enemies   = nil
	s.items     = nil
	s.inventory = nil

	g.descend_pending = false
	g.menu_open       = false
	g.shake_frames    = 0
	g.shake_dx        = 0
	g.shake_dy        = 0

	clear_log(g)
	compute_fov(g, g.player.x, g.player.y, FOV_RADIUS)
	play_realm_music(g.realm)
}
