package asgard

// Recursive shadowcasting field of view.
// See https://www.roguebasin.com/index.php?title=FOV_using_recursive_shadowcasting

FOV_RADIUS :: 8

// Eight octants. Each entry is the (xx, xy, yx, yy) transform that maps
// algorithm-local (dx, dy) into world deltas. Together they tile the full circle.
FOV_OCTANTS := [8][4]int{
	{ 1,  0,  0,  1},
	{ 0,  1,  1,  0},
	{ 0, -1,  1,  0},
	{ 1,  0,  0, -1},
	{-1,  0,  0, -1},
	{ 0, -1, -1,  0},
	{ 0,  1, -1,  0},
	{-1,  0,  0,  1},
}

blocks_sight :: proc(g: ^Game, x, y: int) -> bool {
	return tile_at(g, x, y) == .Wall
}

mark_visible :: proc(g: ^Game, x, y: int) {
	if x < 0 || y < 0 || x >= MAP_W || y >= MAP_H { return }
	i := y * MAP_W + x
	g.visible[i]  = true
	g.explored[i] = true
}

// Classic recursive shadowcasting for a single octant. `row` starts at 1
// (we never scan distance 0 — the origin is always lit by compute_fov).
cast_light :: proc(
	g: ^Game,
	cx, cy, row: int,
	start_in, end: f32,
	radius: int,
	xx, xy, yx, yy: int,
) {
	start := start_in
	if start < end { return }
	radius_sq := radius * radius
	new_start: f32 = 0

	for j := row; j <= radius; j += 1 {
		dy := -j
		blocked := false
		for dx := -j; dx <= 0; dx += 1 {
			X := cx + dx * xx + dy * xy
			Y := cy + dx * yx + dy * yy
			l_slope := (f32(dx) - 0.5) / (f32(dy) + 0.5)
			r_slope := (f32(dx) + 0.5) / (f32(dy) - 0.5)

			if start < r_slope { continue }
			if end > l_slope   { break }

			if dx*dx + dy*dy <= radius_sq {
				mark_visible(g, X, Y)
			}

			if blocked {
				if blocks_sight(g, X, Y) {
					new_start = r_slope
					continue
				} else {
					blocked = false
					start = new_start
				}
			} else {
				if blocks_sight(g, X, Y) && j < radius {
					blocked = true
					cast_light(g, cx, cy, j + 1, start, l_slope, radius, xx, xy, yx, yy)
					new_start = r_slope
				}
			}
		}
		if blocked { break }
	}
}

compute_fov :: proc(g: ^Game, px, py, radius: int) {
	for i in 0 ..< len(g.visible) { g.visible[i] = false }
	mark_visible(g, px, py)
	for i in 0 ..< 8 {
		m := FOV_OCTANTS[i]
		cast_light(g, px, py, 1, 1.0, 0.0, radius, m[0], m[1], m[2], m[3])
	}
}
