extends SceneTree
func _initialize() -> void:
	var root3:=Node3D.new();root.add_child(root3)
	var r:=FighterRig.new();root3.add_child(r);r.setup("boss")
	print("SKEL TRANSFORM ",r.skel.global_transform)
	for n in ["root","pelvis","spine2","head","hand_l","hand_r"]:
		var i:int=r.ids[n]
		print(n," rest ",r.rest[n]," head ",r.heads[n]," current ",r.skel.get_bone_global_pose(i)," target ",r.globals[n])
	for m in r.model.find_children("*","MeshInstance3D",true,false):print("MESH ",m.global_transform," ",m.get_aabb())
	quit()
