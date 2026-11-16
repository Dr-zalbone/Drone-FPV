class_name MapLod
extends RefCounted
## Distance-based discrete LOD for processed map chunks.
## Chunk nodes are named "<map>_chunk_<x>_<y>_lod<N>" with their origin at the
## chunk centre (tools/process_models.py), so visibility ranges are measured
## per chunk.

const BASE_SWITCH := 3.0  # LOD0 -> LOD1 at 3 chunk widths ...
const MIN_SWITCH := 250.0  # ... but never closer than this (metres)
const LOD2_FACTOR := 2.5  # LOD1 -> LOD2 at 2.5x the first switch
const HYSTERESIS := 0.05


## Switch distances [LOD0->1, LOD1->2] for a chunk size and quality multiplier.
static func switch_distances(chunk_size: float, multiplier: float) -> Array[float]:
	var d1 := maxf(chunk_size * BASE_SWITCH, MIN_SWITCH) * multiplier
	return [d1, d1 * LOD2_FACTOR]


## Returns [base_name, level] or ["", -1] when the node is not an LOD chunk.
static func parse_name(node_name: String) -> Array:
	var re := RegEx.create_from_string("^(.*)_lod(\\d+)$")
	var m := re.search(node_name)
	if m == null:
		return ["", -1]
	return [m.get_string(1), m.get_string(2).to_int()]


## Visibility range [begin, end] for one LOD level (end = 0 means unlimited).
static func range_for(level: int, max_level: int, switches: Array[float], view_distance: float, radius: float) -> Vector2:
	var begin := 0.0 if level == 0 else switches[mini(level - 1, switches.size() - 1)]
	var end := view_distance + radius
	if level < max_level:
		end = minf(switches[mini(level, switches.size() - 1)], end)
	return Vector2(begin, end)


static func apply(map: Node, chunk_size: float, multiplier: float, view_distance: float) -> void:
	var switches := switch_distances(chunk_size, multiplier)
	var nodes := map.find_children("*", "GeometryInstance3D", true, false)
	var max_level := {}
	for node in nodes:
		var parsed := parse_name(String(node.name))
		if parsed[1] >= 0:
			max_level[parsed[0]] = maxi(max_level.get(parsed[0], 0), parsed[1])
	for node in nodes:
		var gi := node as GeometryInstance3D
		var radius := 0.0
		if gi is VisualInstance3D:
			radius = (gi as VisualInstance3D).get_aabb().size.length() * 0.5
		var parsed := parse_name(String(gi.name))
		var r := Vector2(0.0, view_distance + radius)
		if parsed[1] >= 0:
			r = range_for(parsed[1], max_level[parsed[0]], switches, view_distance, radius)
		gi.visibility_range_begin = r.x
		gi.visibility_range_end = r.y
		gi.visibility_range_begin_margin = r.x * HYSTERESIS
		gi.visibility_range_end_margin = r.y * HYSTERESIS
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
