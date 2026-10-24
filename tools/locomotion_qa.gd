extends Node3D
## Actual translating/turning rigs, not an in-place sine-wave pose sample.
const CASES=[
 {"kind":"knight","id":"walk","speed":1.6,"dir":Vector3(0,0,1)},
 {"kind":"knight","id":"run","speed":4.0,"dir":Vector3(0,0,1)},
 {"kind":"knight","id":"sprint","speed":6.0,"dir":Vector3(0,0,1)},
 {"kind":"knight","id":"strafe","speed":3.52,"dir":Vector3(1,0,0)},
 {"kind":"knight","id":"backward","speed":2.5,"dir":Vector3(0,0,-1)},
 {"kind":"knight","id":"turn","speed":3.52,"dir":Vector3(0,0,1)},
 {"kind":"knight","id":"guard","speed":1.4,"dir":Vector3(1,0,0)},
 {"kind":"boss","id":"approach","speed":2.75,"dir":Vector3(0,0,1)},
 {"kind":"boss","id":"charge","speed":5.2,"dir":Vector3(0,0,1)},
 {"kind":"boss","id":"orbit","speed":.95,"dir":Vector3(1,0,0)},
 {"kind":"boss","id":"retreat","speed":1.5,"dir":Vector3(0,0,-1)},
 {"kind":"boss","id":"turn","speed":3.15,"dir":Vector3(0,0,1)}]
func _ready() -> void:run.call_deferred()
func row(t:Transform3D) -> Array:
	return [t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z]
func vec(v:Vector3) -> Array:return [v.x,v.y,v.z]
func run() -> void:
	G.mobile=true
	var report:={"hz":60,"frames":[],"cases":[]}
	for spec:Dictionary in CASES:
		var rig:=FighterRig.new();add_child(rig);rig.position.y=.05
		if spec.kind=="boss":rig.scale=Vector3.ONE*1.20
		rig.setup(spec.kind)
		for i in 12:rig.pose("idle",0,1.0/60,0,Vector3.ZERO)
		var metrics:={"samples":0,"max_plant_error":0.0,"max_paw_error":0.0,"max_limb_length_error":0.0,"max_socket_error":0.0,"max_pelvis_step":0.0,"max_pelvis_step_time":0.0,"min_boss_supports":3,"finite":true}
		var previous_pelvis:Vector3=rig.skel.get_bone_global_pose(rig.ids.pelvis).origin
		for frame in 181:
			var t:=frame/60.0
			var speed:float=spec.speed*smoothstep(0,.26,t)*(1-smoothstep(2.25,2.7,t))
			var yaw:float=smoothstep(.6,1.65,t)*1.05 if spec.id=="turn" else 0.0
			rig.rotation.y=yaw;rig.position+=Vector3(spec.dir)*speed/60.0
			var local_dir:Vector3=Vector3(spec.dir).rotated(Vector3.UP,-yaw)
			rig.pose("guard" if spec.id=="guard" else ("move" if speed>.01 else "idle"),t,1.0/60,speed,local_dir)
			metrics.samples+=1
			var pelvis:Vector3=rig.skel.get_bone_global_pose(rig.ids.pelvis).origin
			var pelvis_step:=pelvis.distance_to(previous_pelvis)
			if pelvis_step>float(metrics.max_pelvis_step):
				metrics.max_pelvis_step=pelvis_step;metrics.max_pelvis_step_time=t
				metrics.maximum_event={"pelvis":vec(pelvis),"previous":vec(previous_pelvis),"feet":rig.walk_contacts.duplicate(true)}
			previous_pelvis=pelvis
			for side in ["l","r"]:
				var hip:Vector3=rig.skel.get_bone_global_pose(rig.ids["thigh_"+side]).origin
				var knee:Vector3=rig.skel.get_bone_global_pose(rig.ids["shin_"+side]).origin
				var ankle:Vector3=rig.skel.get_bone_global_pose(rig.ids["foot_"+side]).origin
				metrics.max_limb_length_error=maxf(metrics.max_limb_length_error,maxf(absf(hip.distance_to(knee)-rig.lengths["thigh_"+side]),absf(knee.distance_to(ankle)-rig.lengths["shin_"+side])))
				metrics.finite=metrics.finite and hip.is_finite() and knee.is_finite() and ankle.is_finite()
				var plants:Dictionary=rig.foot_plants if spec.kind=="knight" else rig.beast_plants
				if plants.has(side):metrics.max_plant_error=maxf(metrics.max_plant_error,G.flat(rig.skel.to_global(ankle)-Vector3(plants[side])).length())
			if spec.kind=="boss" and rig.beast_plants.has("paw"):
				var paw:Vector3=rig.skel.to_global(rig.skel.get_bone_global_pose(rig.ids.hand_l)*rig.rest.hand_l.affine_inverse()*rig.support_socket)
				metrics.max_paw_error=maxf(metrics.max_paw_error,paw.distance_to(rig.beast_plants.paw))
			if spec.kind=="boss" and speed>.3:metrics.min_boss_supports=mini(metrics.min_boss_supports,rig.beast_plants.size())
			var palm:Vector3=rig.skel.to_global(rig.skel.get_bone_global_pose(rig.ids.hand_r)*rig.rest.hand_r.affine_inverse()*rig.right_socket)
			metrics.max_socket_error=maxf(metrics.max_socket_error,palm.distance_to(rig.weapon.to_global(rig.source_grip)))
			if frame%6!=0:continue
			var transforms:={};var bones:={};var scale_error:=0.0
			for name:String in rig.ids:
				var actual:Transform3D=rig.skel.get_bone_global_pose(rig.ids[name])
				transforms[name]=row(actual*rig.rest[name].affine_inverse())
				bones[name]=vec(rig.skel.to_global(actual.origin))
				scale_error=maxf(scale_error,(actual.basis.get_scale()-Vector3.ONE).length())
			var plants:={}
			for side in ["l","r"]:
				if rig.kind=="knight" and rig.foot_plants.has(side):plants[side]=vec(rig.foot_plants[side])
				elif rig.kind=="boss" and rig.beast_plants.has(side):plants[side]=vec(rig.beast_plants[side])
			if rig.kind=="boss" and rig.beast_plants.has("paw"):plants.paw=vec(rig.beast_plants.paw)
			report.frames.append({"kind":spec.kind,"case":spec.id,"time":t,"speed":speed,"gait":rig.gait,"transforms":transforms,"bones":bones,"plants":plants,"motion_world":row(rig.motion.global_transform),"scale_error":scale_error})
		report.cases.append({"kind":spec.kind,"case":spec.id,"metrics":metrics});print("LOCOMOTION QA ",spec.kind," ",spec.id," ",metrics)
		rig.queue_free()
	var suffix:="baseline" if "--baseline" in OS.get_cmdline_user_args() else "after"
	var file:=FileAccess.open("res://artifacts/locomotion_%s.json"%suffix,FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	get_tree().quit()
