class_name FacadeDetail
extends RefCounted
## Swaps textured map materials for the procedural facade-detail shader.
## Enabled per map with "facade_detail": true in the manifest
## (MAP_OVERRIDES in tools/process_models.py).

const SHADER_PATH := "res://shaders/facade_detail.gdshader"


## Returns the number of surfaces converted.
static func apply(map: Node) -> int:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		push_error("Missing " + SHADER_PATH)
		return 0
	var cache := {}  # source material -> ShaderMaterial (keeps materials shared)
	var count := 0
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as BaseMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			if not cache.has(src):
				var mat := ShaderMaterial.new()
				mat.shader = shader
				mat.set_shader_parameter(&"albedo_tex", src.albedo_texture)
				cache[src] = mat
			mi.set_surface_override_material(i, cache[src])
			count += 1
	return count
