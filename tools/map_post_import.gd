@tool
extends EditorScenePostImport
## Post-import step for processed maps (assets/maps/*.glb), set by
## tools/configure_imports.py: anisotropic filtering for oblique facades,
## no shadow casting (shadows are off on Quest anyway).


func _post_import(scene: Node) -> Object:
	var seen := {}
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if mat and not seen.has(mat):
				seen[mat] = true
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return scene
