@tool
extends EditorScenePostImport
## Materials are assigned by FighterRig using the authored surface and ORM maps.
## Strip unused embedded materials from the imported cache, not the source GLB,
## so phones do not load a second set of 4K textures before replacing them.
func _post_import(scene:Node) -> Object:
	for node in scene.find_children("*","MeshInstance3D",true,false):
		if not node.mesh:continue
		for surface in node.mesh.get_surface_count():node.mesh.surface_set_material(surface,null)
		node.material_override=null
	return scene
