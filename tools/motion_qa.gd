extends Node3D
## Measures actual skeleton motion in a plain headless-compatible stage.
## The torso centroid is a landmark proxy, not a claim about physical mass.
const WATCH=["pelvis","spine1","spine2","head","upper_l","upper_r","hand_r","foot_l","foot_r"]
var report:={"schema":1,"actor_translation_excluded":true,"centroid_is_landmark_proxy":true,"moves":[]}
func _ready() -> void:
	if "--parse-only" in OS.get_cmdline_user_args():get_tree().quit();return
	run.call_deferred()
func v(a:Vector3) -> Array:return [a.x,a.y,a.z]
func yaw(a:Basis) -> float:return atan2(a.z.x,a.z.z)
func axial_twist(a:Basis,axis:Vector3) -> float:
	var q:=a.orthonormalized().get_rotation_quaternion()
	var swing:=Quaternion(axis,(q*axis).normalized())
	var residual:=swing.inverse()*q
	var angle:=2.0*atan2(Vector3(residual.x,residual.y,residual.z).dot(axis),residual.w)
	return wrapf(angle,-PI,PI)
func cloud_range(points:Array) -> Dictionary:
	var low:=Vector3.INF;var high:=-Vector3.INF;var path:=0.0;var last:=Vector3.INF
	for p:Vector3 in points:
		low=low.min(p);high=high.max(p)
		if last!=Vector3.INF:path+=last.distance_to(p)
		last=p
	return {"min":v(low),"max":v(high),"extent":v(high-low),"path_m":path}

func skin_anchors(rig:FighterRig) -> Dictionary:
	var best:={};var scores:={}
	for mi in rig.model.find_children("*","MeshInstance3D",true,false):
		if not mi.skin:continue
		var bind_bones:=PackedInt32Array();var bind_poses:Array[Transform3D]=[];var bind_names:=[]
		for bind in mi.skin.get_bind_count():
			var bone:int=mi.skin.get_bind_bone(bind)
			if bone<0:bone=rig.skel.find_bone(mi.skin.get_bind_name(bind))
			bind_bones.append(bone);bind_poses.append(mi.skin.get_bind_pose(bind));bind_names.append(String(rig.skel.get_bone_name(bone)))
		for surface in mi.mesh.get_surface_count():
			var arr:Array=mi.mesh.surface_get_arrays(surface);var vertices:PackedVector3Array=arr[Mesh.ARRAY_VERTEX]
			var joints:PackedInt32Array=arr[Mesh.ARRAY_BONES];var weights:PackedFloat32Array=arr[Mesh.ARRAY_WEIGHTS]
			var influences:int=joints.size()/vertices.size()
			for vertex in vertices.size():
				var point:Vector3=vertices[vertex];var top:=-1.0;var dominant:="";var left_foot:=0.0;var right_foot:=0.0;var fabric:=0.0
				for k in influences:
					var w:float=weights[vertex*influences+k]
					var bone_name:String=bind_names[joints[vertex*influences+k]]
					if w>top:top=w;dominant=bone_name
					if bone_name=="foot_l":left_foot+=w
					elif bone_name=="foot_r":right_foot+=w
					elif bone_name.begins_with("cape_") or bone_name=="loin":fabric+=w
				var candidates:={}
				for side in ["l","r"]:
					var foot_weight:float=left_foot if side=="l" else right_foot
					if foot_weight<.18 or fabric>.20 or point.y>=float(rig.heads["foot_"+side].y)*.65:continue
					candidates["heel_"+side]=point.z+point.y*.10
					candidates["toe_"+side]=-point.z+point.y*.10
				if dominant=="hand_r":candidates["palm_r"]=point.distance_squared_to(rig.right_socket)
				if dominant=="hand_l" and rig.kind=="boss":candidates["paw_l"]=point.distance_squared_to(rig.support_socket)
				for key:String in candidates:
					if scores.has(key) and float(scores[key])<=float(candidates[key]):continue
					var links:=[]
					for k in influences:
						var at:int=vertex*influences+k;var bind:int=joints[at]
						if weights[at]>.000001:links.append({"bone":bind_bones[bind],"point":bind_poses[bind]*point,"weight":weights[at]})
					best[key]={"vertex":vertex,"rest_point":v(point),"links":links};scores[key]=candidates[key]
	return best

func skin_point(rig:FighterRig,anchor:Dictionary) -> Vector3:
	var point:=Vector3.ZERO
	for link in anchor.links:point+=(rig.skel.get_bone_global_pose(link.bone)*link.point)*float(link.weight)
	return rig.skel.to_global(point)

func run() -> void:
	var baseline:="--baseline" in OS.get_cmdline_user_args()
	for kind in ["knight","boss"]:
		var rig:=FighterRig.new();add_child(rig);rig.setup(kind)
		if kind=="boss":rig.scale=Vector3.ONE*1.20
		var anchors:=skin_anchors(rig)
		var moves:Array=KnightMoves.MOVES.keys() if kind=="knight" else BeastMoves.ATTACKS.keys()
		for id:String in moves:
			var data:Dictionary=KnightMoves.MOVES[id] if kind=="knight" else BeastMoves.ATTACKS[id]
			var action:=id;var variant:=0
			if id.begins_with("light"):action="light";variant=int(id.trim_prefix("light"))-1
			rig.initialized=false
			# Begin in the authored ready stance so entry blending is real.
			for i in 3:rig.pose("idle",0,1.0/60,0,Vector3.ZERO)
			var clouds:={};var angle_min:={};var angle_max:={};var quats:={};var rotation_path:={}
			for bone in WATCH:
				clouds[bone]=[];angle_min[bone]=INF;angle_max[bone]=-INF;rotation_path[bone]=0.0
			clouds["torso_centroid"]=[];clouds["shoulder_mid"]=[];clouds["support_paw"]=[]
			for key:String in anchors:clouds["skin_"+key]=[]
			var socket_error:=0.0;var blade_floor:=INF;var skin_floor:=INF;var radial_low:=INF;var radial_high:=-INF;var finite:=true;var samples:=[]
			var desired_min:=INF;var desired_max:=-INF
			for frame in int(ceil(float(data.length)*60))+1:
				var time:=frame/60.0
				rig.pose(action,time,1.0/60,0,Vector3.ZERO,variant)
				rig.skel.force_update_all_bone_transforms()
				var actual:={};var torso:=Vector3.ZERO
				for bone:String in WATCH:
					var pose:Transform3D=rig.skel.get_bone_global_pose(rig.ids[bone])
					var delta:Basis=pose.basis*rig.rest[bone].basis.inverse()
					var point:Vector3=rig.skel.to_global(pose.origin)
					clouds[bone].append(point);actual[bone]={"position":v(point),"yaw":yaw(delta),"axial_twist":axial_twist(delta,(rig.tails[bone]-rig.heads[bone]).normalized())}
					angle_min[bone]=minf(angle_min[bone],actual[bone].axial_twist);angle_max[bone]=maxf(angle_max[bone],actual[bone].axial_twist)
					var q:=delta.orthonormalized().get_rotation_quaternion()
					if quats.has(bone):rotation_path[bone]+=quats[bone].angle_to(q)
					quats[bone]=q
				var pp:Transform3D=rig.skel.get_bone_global_pose(rig.ids.pelvis)
				var sp:Transform3D=rig.skel.get_bone_global_pose(rig.ids.spine1)
				var ch:Transform3D=rig.skel.get_bone_global_pose(rig.ids.spine2)
				var hd:Transform3D=rig.skel.get_bone_global_pose(rig.ids.head)
				torso=rig.skel.to_global(pp.origin*.40+sp.origin*.24+ch.origin*.26+hd.origin*.10)
				clouds.torso_centroid.append(torso)
				var shoulder_l:Vector3=rig.skel.to_global(rig.skel.get_bone_global_pose(rig.ids.upper_l).origin)
				var shoulder_r:Vector3=rig.skel.to_global(rig.skel.get_bone_global_pose(rig.ids.upper_r).origin)
				clouds.shoulder_mid.append((shoulder_l+shoulder_r)*.5)
				if kind=="boss" and rig.beast_contacts.has("paw"):clouds.support_paw.append(rig.beast_contacts.paw)
				var hand:Transform3D=rig.skel.get_bone_global_pose(rig.ids.hand_r)
				var palm:Vector3=rig.skel.to_global(hand*rig.rest.hand_r.affine_inverse()*rig.right_socket)
				var actual_grip:Vector3=rig.weapon.to_global(rig.source_grip)
				socket_error=maxf(socket_error,palm.distance_to(actual_grip))
				var blade:Array=rig.blade();blade_floor=minf(blade_floor,minf(blade[0].y,blade[1].y))
				var skinned:={}
				for key:String in anchors:
					var point:=skin_point(rig,anchors[key]);clouds["skin_"+key].append(point);skinned[key]=v(point)
					if key!="palm_r":skin_floor=minf(skin_floor,point.y)
					else:
						var axis:Vector3=rig.weapon.global_basis.y.normalized()
						var radius:float=(point-actual_grip-axis*(point-actual_grip).dot(axis)).length()
						radial_low=minf(radial_low,radius);radial_high=maxf(radial_high,radius)
				finite=finite and palm.is_finite() and actual_grip.is_finite() and torso.is_finite()
				var authored:Dictionary=KnightMotion.sample(id,time) if kind=="knight" else BeastMotion.sample(id,time,rig.clock)
				var target:float=authored.twist;desired_min=minf(desired_min,target);desired_max=maxf(desired_max,target)
				if frame%6==0 or frame==int(ceil(float(data.length)*60)):
					samples.append({"time":time,"bones":actual,"torso_centroid":v(torso),"palm":v(palm),"blade_tip":v(blade[1]),"authored_twist":target,"skinned_supports":skinned})
			var summary:={}
			for bone in WATCH:summary[bone]={"motion":cloud_range(clouds[bone]),"axial_twist_range":angle_max[bone]-angle_min[bone],"rotation_path_rad":rotation_path[bone]}
			for key in ["torso_centroid","shoulder_mid","support_paw"]:
				if not clouds[key].is_empty():summary[key]={"motion":cloud_range(clouds[key])}
			for key:String in anchors:summary["skin_"+key]={"motion":cloud_range(clouds["skin_"+key]),"rest_point":anchors[key].rest_point,"vertex":anchors[key].vertex}
			var entry:={"skin_support_min_y":skin_floor,"palm_skin_radial_drift_m":radial_high-radial_low,"kind":kind,"id":id,"finite":finite,"socket_error_m":socket_error,"blade_min_y":blade_floor,"authored_twist_range":desired_max-desired_min,"summary":summary,"samples":samples}
			report.moves.append(entry)
			print("MOTION QA ",kind," ",id," desired_twist=",desired_max-desired_min," actual_chest_axial=",angle_max.spine2-angle_min.spine2," torso_extent=",summary.torso_centroid.motion.extent," socket=",socket_error)
		rig.queue_free()
	var suffix:="baseline" if baseline else "after"
	var path:="res://artifacts/motion_qa_%s.json"%suffix
	var out:=FileAccess.open(path,FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	print("MOTION QA SAVED ",path)
	get_tree().quit()
