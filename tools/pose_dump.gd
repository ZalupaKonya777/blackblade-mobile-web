extends Node
func _ready() -> void:run.call_deferred()
func row(t:Transform3D) -> Array:
	return [t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z]
func run() -> void:
	var main=get_parent();main.set_process(false);G.playing=false
	main.player.set_physics_process(false);main.boss.set_physics_process(false)
	var report:=[]
	for rig:FighterRig in [main.player.rig,main.boss.rig]:
		for sample in [["idle",0.0,0.0],["move",.35,3.6],["light",.42,0.0],["sweep",.72,0.0],["overhead",1.18,0.0],["leap",.82,0.0],["roll",.32,0.0],["dead",2.0,0.0]]:
			if rig.kind=="boss" and sample[0] in ["light","roll"]:continue
			if rig.kind=="knight" and sample[0] in ["sweep","overhead","leap"]:continue
			rig.initialized=false
			for i in 24:rig.pose(sample[0],sample[1],1.0/60,sample[2],Vector3(0,0,1))
			rig.skel.force_update_all_bone_transforms()
			var transforms:={}
			for name in rig.ids:transforms[name]=row(rig.skel.get_bone_global_pose(rig.ids[name])*rig.rest[name].affine_inverse())
			report.append({"kind":rig.kind,"action":sample[0],"t":sample[1],"transforms":transforms,"motion_world":row(rig.motion.global_transform),"paw":rig.beast_contacts.get("paw",Vector3.ZERO),"grip":rig.grip})
	var f:=FileAccess.open("res://artifacts/pose_dump.json",FileAccess.WRITE);f.store_string(JSON.stringify(report));f.close();get_tree().quit()
