class_name FighterRig
extends Node3D
## Original runtime skeleton animation: planted two-bone IK limbs, weighted spine and cloth.
## The source GLBs are static; tools/rig_build.py creates a skin without changing the source files.

var kind := "knight"
var skel: Skeleton3D
var model: Node3D
var motion: Node3D
var weapon: Node3D
var rest := {}
var heads := {}
var tails := {}
var lengths := {}
var ids := {}
var globals := {}
var poses := {}
var unit := 1.0
var clock := 0.0
var gait := 0.0
var blade_dir := Vector3(0,-0.7,0.7)
var grip := Vector3.ZERO
var blade_length := 1.10
var previous_grip := Vector3.ZERO
var previous_tip := Vector3.ZERO
var roll_direction := Vector3.FORWARD
var roll_locked:=false
var pose_blend := 13.0
var initialized := false
var feet := {}
var foot_plants := {}
var foot_swing := {}
var cloth_points := {}
var cloth_previous := {}
var cloth_last_frame:=Transform3D.IDENTITY
var cloth_has_frame:=false
var cloth_root_velocity:=Vector3.ZERO
var roll_phase := 0.0
var roll_support := "feet"
var roll_ground_clearance := 0.0
var last_action := ""
var ground_min := .035
var breathing := 0.0
var contact_probes:Array=[]
var roll_feet_world:={}
var previous_roll_phase:=-1.0
var body_materials:Array[ShaderMaterial]=[]
var beast_pose:Dictionary={}
var beast_blend_from:Dictionary={}
var beast_blend_time:=0.0
var beast_plants:Dictionary={}
var beast_swings:Dictionary={}
var beast_contacts:Dictionary={}
var beast_step_cycles:Dictionary={}
var beast_releases:Dictionary={}
var beast_contact_targets:Dictionary={}
var beast_cloth_probes:Array=[]
var beast_cloth_ids:=PackedByteArray()
var secondary_motion:=true
var recoil:=Vector3.ZERO
var recoil_velocity:=Vector3.ZERO
var weapon_id:=""
var weapon_last_t:=-1.0
var weapon_entry_t:=0.0
var weapon_from:Dictionary={}
var weapon_plants:Dictionary={}
var hand_frames:Dictionary={}
var corpse_probes:Array=[]
var grip_shapes:Array=[]
var left_grip_blend:=0.0
var sockets:Dictionary={}
var right_socket:=Vector3.ZERO
var left_socket:=Vector3.ZERO
var support_socket:=Vector3.ZERO
var support_normal:=Vector3.DOWN
const PALM_FRAME=Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN)
var source_grip:=Vector3.ZERO
var source_shoulder:=Vector3.ZERO
var source_tip:=Vector3.ZERO
var weapon_scale:=1.0
var source_frame:=Basis.IDENTITY
const GroundGaitScript=preload("res://scripts/ground_gait.gd")
var ground_solver=GroundGaitScript.new()
var ground_blend:=0.0
var ground_frequency:=1.0
var walk_contacts:Dictionary={}
var ground_locomotion:=false
var ground_was_moving:=false
var beast_body_support:=Vector3.ZERO
var locomotion_height:=.95

func setup(p_kind: String) -> void:
	kind = p_kind
	unit = 1.0 if kind == "knight" else 2.05
	motion = Node3D.new()
	add_child(motion)
	model = load("res://assets/characters/"+kind+"_mobile.glb").instantiate()
	motion.add_child(model)
	skel = _skeleton(model)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/"+kind+"_mobile.json"))
	for i in skel.get_bone_count():
		var n := String(skel.get_bone_name(i))
		ids[n] = i
		rest[n] = skel.get_bone_global_rest(i)
		var b: Dictionary = data.bones.get(n, {})
		if b.is_empty(): continue
		heads[n] = Vector3(b.head[0],b.head[1],b.head[2])
		tails[n] = Vector3(b.tail[0],b.tail[1],b.tail[2])
		lengths[n] = heads[n].distance_to(tails[n])
	weapon = load("res://assets/weapons/"+("player_sword" if kind=="knight" else "boss_sword")+".glb").instantiate()
	motion.add_child(weapon)
	for mesh in weapon.find_children("*","MeshInstance3D",true,false):mesh.layers=2
	sockets=JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/"+kind+"_sockets.json"))
	right_socket=_vec(sockets.right_grip);left_socket=_vec(sockets.left_grip)
	support_socket=_vec(sockets.left_support);support_normal=_vec(sockets.support_normal).normalized()
	if kind=="boss":
		weapon_scale=1.38;source_grip=Vector3(-.000004,.080000,-.000036)
		source_shoulder=Vector3(0,.31,0);source_tip=Vector3(.000406,1.435179,.000979)
	else:
		source_frame=Basis(Vector3.RIGHT,Vector3.DOWN,Vector3.FORWARD)
		source_grip=Vector3(.000069,.940000,-.000081)
		source_shoulder=Vector3(0,.775,0);source_tip=Vector3(-.057005,-.162515,.000328)
	blade_length=source_grip.distance_to(source_tip)*weapon_scale
	for mi in model.find_children("*","MeshInstance3D",true,false):
		mi.extra_cull_margin = 5.0
		mi.layers=2
		if mi.get_blend_shape_count()>0:grip_shapes.append(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Keep the supplied silhouette stable when a limb approaches the camera.
		mi.lod_bias=128.0
		var mat:=ShaderMaterial.new();mat.shader=load("res://shaders/character.gdshader")
		mat.set_shader_parameter("surface",load("res://assets/characters/"+kind+"_surface.jpg"))
		mat.set_shader_parameter("armor",load("res://assets/characters/"+kind+"_armor_orm.png"))
		var normal_path:="res://assets/characters/"+kind+("_medieval_knight_3d_model_normal.png" if kind=="knight" else "_dark_fantasy_creature_3d_model_normal.png")
		mat.set_shader_parameter("normal_map",load(normal_path))
		mat.set_shader_parameter("normal_strength",.48 if kind=="knight" else .34)
		mat.set_shader_parameter("metal_strength",.94 if kind=="knight" else .72)
		mat.set_shader_parameter("minimum_roughness",.30 if kind=="knight" else .44)
		mi.material_override=mat;body_materials.append(mat)
	if kind=="knight" and FileAccess.file_exists("res://assets/characters/knight_contacts.json"):
		var probes:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/knight_contacts.json"))
		for probe in probes:
			var point:=Vector3(probe.point[0],probe.point[1],probe.point[2])
			var links:=[]
			for link in probe.influences:links.append({"bone":link.bone,"local":rest[link.bone].affine_inverse()*point,"weight":float(link.weight)})
			contact_probes.append(links)
	if kind=="boss":
		beast_cloth_ids.resize(skel.get_bone_count())
		for bone in ids:beast_cloth_ids[ids[bone]]=int(String(bone).begins_with("cape_") or bone=="loin")
		var probes:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/boss_cloth_contacts.json"))
		for probe in probes:
			var point:=Vector3(probe.point[0],probe.point[1],probe.point[2])
			var bones:=PackedInt32Array();var points:=PackedVector3Array();var weights:=PackedFloat32Array();var cloth_weight:=0.0
			for link in probe.influences:
				bones.append(ids[link.bone]);points.append(rest[link.bone].affine_inverse()*point);weights.append(link.weight)
				if beast_cloth_ids[ids[link.bone]]:cloth_weight+=float(link.weight)
			beast_cloth_probes.append({"bones":bones,"points":points,"weights":weights,"cloth_weight":cloth_weight})
	pose("idle",0,0.016,0,Vector3.ZERO)
	G.changed.connect(apply_quality)
	apply_quality()

func apply_quality() -> void:
	var quality:int=G.settings.get("quality",1)
	if "--low" in OS.get_cmdline_user_args():quality=0
	if "--beauty" in OS.get_cmdline_user_args():quality=1
	# Material detail and specular filtering stay enabled even in performance mode.
	for mi in model.find_children("*","MeshInstance3D",true,false):mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _skeleton(c)
		if r: return r
	return null

func _point(v: Vector3, origin: Vector3, body: Basis) -> Vector3:
	return origin+body*(v-heads.pelvis)

func _put(n: String, a: Vector3, b: Vector3, roll := 0.0) -> void:
	if not rest.has(n): return
	var old_dir: Vector3 = (tails[n]-heads[n]).normalized()
	var new_dir := (b-a).normalized()
	if new_dir.length_squared()<0.1: new_dir=Vector3.UP
	var q := Quaternion(old_dir,new_dir)
	var bs: Basis = Basis(q)*rest[n].basis
	if absf(roll)>0.001: bs=Basis(new_dir,roll)*bs
	bs=bs.orthonormalized()
	globals[n] = Transform3D(bs,a)

func _oriented(n:String,origin:Vector3,rotation:Basis) -> void:
	# Endpoints cannot represent axial rotation. Preserve the full authored frame.
	globals[n]=Transform3D(rotation.orthonormalized()*rest[n].basis,origin)

func _ik(prefix_a: String, prefix_b: String, side: String, root: Vector3, target: Vector3, pole: Vector3) -> Vector3:
	var la: float = lengths[prefix_a+side]
	var lb: float = lengths[prefix_b+side]
	var v := target-root
	var dist := clampf(v.length(),absf(la-lb)+0.015,la+lb-0.005)
	var f := v.normalized()
	if f.length_squared()<0.1: f=Vector3.DOWN
	var bend := pole-f*pole.dot(f)
	if bend.length_squared()<0.001: bend=Vector3.RIGHT-f*f.x
	bend=bend.normalized()
	var along := (la*la-lb*lb+dist*dist)/(2*dist)
	var height := sqrt(maxf(0,la*la-along*along))
	var joint := root+f*along+bend*height
	var end := root+f*dist
	_put(prefix_a+side,root,joint)
	_put(prefix_b+side,joint,end)
	return end

func _swing_angle(t: float, wind: float, hit: float, finish: float, start_angle: float, end_angle: float) -> float:
	if t<wind: return lerpf(0,start_angle,smoothstep(0,wind,t))
	if t<hit: return lerpf(start_angle,end_angle,smoothstep(wind,hit,t))
	return lerpf(end_angle,0,smoothstep(hit,finish,t))

func pose(action: String, t: float, dt: float, speed: float, direction: Vector3, variant := 0) -> void:
	if not skel: return
	clock += dt
	if kind=="knight":
		var two_hands:=KnightMoves.is_attack(action) and KnightMoves.two_handed(action,variant)
		var next_grip:=move_toward(left_grip_blend,1.0 if two_hands else 0.0,dt*12)
		if not is_equal_approx(next_grip,left_grip_blend):
			left_grip_blend=next_grip
			for mesh in grip_shapes:mesh.set_blend_shape_value(0,left_grip_blend)
	recoil_velocity+=(-recoil*210.0-recoil_velocity*24.0)*dt
	recoil+=recoil_velocity*dt
	var locomoting:=action in ["idle","move","guard"]
	if not initialized:ground_was_moving=false
	ground_frequency=(.90+speed*.28) if kind=="knight" else (.72+speed*.22)
	if locomoting and speed>.08 and not ground_was_moving:
		gait=(.62 if kind=="knight" else (0.0 if direction.z<-.3 or direction.x<-.5 else .43))*TAU
	ground_was_moving=locomoting and speed>.08
	if locomoting:gait+=dt*TAU*ground_frequency*clampf(speed/.35,0,1)
	ground_blend=move_toward(ground_blend,1.0 if locomoting and speed>.08 else 0.0,dt*5.5)
	globals.clear()
	if not initialized:
		ground_solver.reset();walk_contacts.clear();ground_blend=0.0
		beast_body_support=Vector3.ZERO
		cloth_has_frame=false;cloth_root_velocity=Vector3.ZERO
		recoil=Vector3.ZERO;recoil_velocity=Vector3.ZERO;hand_frames.clear()
		cloth_points.clear();cloth_previous.clear();foot_plants.clear();foot_swing.clear()
		beast_plants.clear();beast_swings.clear();beast_pose.clear();beast_contacts.clear();beast_blend_from.clear();beast_step_cycles.clear();beast_releases.clear();beast_contact_targets.clear()
	if kind=="boss":
		_pose_beast(action,t,dt,speed,direction)
		last_action=action
		return
	if kind=="knight" and action=="roll":
		_pose_roll(t,dt)
		last_action=action
		return
	if kind=="knight" and KnightMoves.is_attack(action):
		_pose_weapon(action,t,dt,variant)
		last_action=action
		return
	if kind=="knight" and locomoting:
		_pose_locomotion(action,dt,speed,direction)
		last_action=action
		return
	var p := Vector3(0,0.95,0)*unit
	var lean := 0.08
	var twist := sin(clock*1.6)*0.025
	var left := Vector3(0.28,1.04,0.18)*unit
	var right := Vector3(-0.29,1.06,0.12)*unit
	var lf := Vector3(0.15,0.10,0.06)*unit
	var rf := Vector3(-0.15,0.10,0.08)*unit
	var sword := Vector3(-0.10,-0.70,0.72)
	var root_xform := Transform3D.IDENTITY
	var moving := speed>0.05
	var atk := action.begins_with("light") or action in ["heavy","charged","roll_attack","jump_attack","counter"]
	if moving and action in ["idle","move"]:
		var stride := minf(speed*0.075,0.48)*unit
		var d := direction.normalized()
		if d.length()<0.1:d=Vector3(0,0,1)
		var s := sin(gait)
		lf += d*s*stride+Vector3.UP*maxf(0,cos(gait))*0.16*unit
		rf -= d*s*stride
		rf.y+=maxf(0,-cos(gait))*0.16*unit
		p.y += absf(s)*0.035*unit
		lean+=minf(speed*0.022,0.16)
		left+=Vector3(0,s*0.035,-s*0.10)*unit
		right+=Vector3(0,-s*0.035,s*0.04)*unit
		if speed>5.0:
			lean+=0.12
			left=Vector3(0.28,1.12,0.10+sin(gait)*0.16)*unit
			right=Vector3(-0.27,1.18,0.11)*unit
			sword=Vector3(-0.15,0.72,-0.68)
	if kind=="knight":
		p.y+=sin(clock*2.1)*.004
		if moving and action in ["idle","move"]:
			lf=_locomotion_foot("l",dt,speed,direction)
			rf=_locomotion_foot("r",dt,speed,direction)
			p.y=.92-absf(sin(gait))*.025+clampf((speed-5.0)*.025,0,.055)
			twist=sin(gait)*.055
			lean=.12+speed*.025
		else:
			foot_plants.clear();foot_swing.clear()
	if kind=="knight":
		if action=="backstep":
			p.y-=sin(clampf(t/.45,0,1)*PI)*.08;lean=-.12
		elif action=="guard" or action=="parry":
			lean=.12;left=Vector3(.12,1.30,.32);right=Vector3(-.17,1.22,.35);sword=Vector3(.25,.85,-.2)
			if action=="parry":
				var sw:=sin(clampf(t/.5,0,1)*PI);right.x-=sw*.25;sword=Vector3(.65*sw,.9,.15)
		elif action=="heal":
			left=Vector3(.12,1.42,.21);right=Vector3(-.30,.99,.09);lean=-.05
		elif action=="jump":
			p.y=.83;lean=.25;lf.y=.40;rf.y=.33;lf.z=.25;rf.z=-.16
		elif action=="hurt":
			lean=-sin(clampf(t/.55,0,1)*PI)*.4;right.z=-.10;left.z=-.10
		elif action=="dead":
			var f:=smoothstep(0,1.3,t)
			p.y=lerpf(.95,.39,f);lean=.92*f;lf.z=lerpf(.06,-.24,f);rf.z=lerpf(.08,-.33,f);right.y=lerpf(1.06,.28,f);right.z=lerpf(.12,.43,f);left.y=lerpf(1.04,.22,f);left.z=lerpf(.18,.48,f)
		if atk:
			var wind:=.25;var hit:=.42;var end:=.78
			if action in ["heavy","charged","jump_attack","counter"]:wind=.55;hit=.78;end=1.2
			if action=="roll_attack":wind=.15;hit=.30;end=.65
			var odd:=1.0 if variant%2==0 else -1.0
			var a:=_swing_angle(t,wind,hit,end,-1.75*odd,1.65*odd)
			twist=a*.30;lean=.10+sin(clampf(t/end,0,1)*PI)*.15
			right=Vector3(-.18+sin(a)*.26,1.21+cos(a)*.12,.28+cos(a)*.16)
			left=Vector3(.14,1.12,.22)
			sword=Vector3(sin(a),.15,cos(a)).normalized()
			if action in ["heavy","charged","jump_attack","counter"]:
				var a2:=_swing_angle(t,wind,hit,end,-.90,2.3)
				right=Vector3(-.13,1.28+cos(a2)*.18,.25+sin(a2)*.20)
				sword=Vector3(.15,cos(a2),sin(a2)).normalized()
				left=right+Vector3(.10,-.06,-.04)
				lean+=sin(clampf((t-wind)/(hit-wind),0,1)*PI)*.20
	# Assemble spine first. Bone rotations use the original rest axes to preserve armour orientation.
	lean+=recoil.x;twist+=recoil.y
	var body:=Basis(Vector3.FORWARD,recoil.z)*Basis(Vector3.UP,twist)*Basis(Vector3.RIGHT,lean)
	_put("root",Vector3.ZERO,Vector3.UP*.10*unit)
	for bn in ["pelvis","spine1","spine2","neck","head"]:
		_oriented(bn,_point(heads[bn],p,body),body)
	for side in ["l","r"]:
		var signx:=1.0 if side=="l" else -1.0
		var hip:Vector3=p+Basis(Vector3.UP,twist*.25)*(heads["thigh_"+side]-heads.pelvis)
		var target:Vector3=lf if side=="l" else rf
		var ankle:=_ik("thigh_","shin_",side,hip,target,Vector3(signx*.1,0,1))
		_put("foot_"+side,ankle,ankle+Vector3(0,-.035,.15)*unit)
		feet[side]=ankle
		var shoulder:=_point(heads["upper_"+side],p,body)
		var hand_target:Vector3=left if side=="l" else right
		var elbow_pole:=Vector3(signx*.45,-.12,-.90) if kind=="knight" else Vector3(signx*.85,-.20,-.5)
		if side=="r":_grasp(side,shoulder,hand_target,sword,elbow_pole)
		else:
			var hand:=_ik("upper_","fore_",side,shoulder,hand_target,elbow_pole)
			_put("hand_l",hand,hand+Vector3(0,-1,.15).normalized()*lengths.hand_l)
	motion.transform=root_xform
	_cloth(dt,p,body)
	_commit(action,dt,sword)
	last_action=action

func _beast_cloth_floor() -> void:
	if not secondary_motion:return
	# Constrain the skinned cloth surface, including the broad spiked hem.
	# Bone centres alone can stay above the floor while their mesh sinks through it.
	var xf:=motion.global_transform
	var scale_y:=maxf(.1,xf.basis.get_scale().y)
	var floor_y:float=(.065-xf.origin.y)/scale_y
	var transforms:Array[Transform3D]=[];transforms.resize(skel.get_bone_count())
	for bone in globals:transforms[ids[bone]]=globals[bone]
	var lifts:=PackedFloat32Array();lifts.resize(skel.get_bone_count())
	for probe in beast_cloth_probes:
		var bones:PackedInt32Array=probe.bones;var points:PackedVector3Array=probe.points;var weights:PackedFloat32Array=probe.weights
		var y:=0.0
		for i in bones.size():y+=(transforms[bones[i]]*points[i]).y*weights[i]
		if y>=floor_y or float(probe.cloth_weight)<.3:continue
		var lift:float=(floor_y-y)/float(probe.cloth_weight)
		for bone in bones:
			if beast_cloth_ids[bone]:lifts[bone]=maxf(lifts[bone],lift)
	for bone in globals:
		var lift:float=lifts[ids[bone]]
		if lift<=0:continue
		globals[bone].origin.y+=lift
		var key:=String(bone).trim_prefix("cape_")
		if cloth_points.has(key):
			cloth_points[key].y+=lift*scale_y
			cloth_previous[key].y+=lift*scale_y
func _commit(action:String,dt:float,sword:Vector3) -> void:
	# Contact is measured from the actual curved blade, including its source
	# grip offset. Rotate the wrist without separating it from the forearm.
	var floor_y:float=(.036-motion.global_position.y)/maxf(.1,motion.global_basis.get_scale().y)
	for contact_pass in 4:
		var hand_delta:Transform3D=globals.hand_r*rest.hand_r.affine_inverse()
		var palm:Vector3=hand_delta*right_socket
		var chord:Vector3=hand_delta.basis*PALM_FRAME*source_frame.inverse()*(source_tip-source_grip)*weapon_scale
		if palm.y+chord.y>=floor_y:break
		var axis:=chord.normalized();var minimum:=clampf((floor_y-palm.y)/blade_length,-.995,.995)
		var flat:=Vector3(axis.x,0,axis.z).normalized()
		if flat.length()<.1:flat=Vector3(0,0,1)
		var corrected:=flat*sqrt(1-minimum*minimum)+Vector3.UP*minimum
		globals.hand_r.basis=Basis(Quaternion(axis,corrected))*globals.hand_r.basis
	# Smooth local transforms while maintaining a deterministic animation clock.
	var alpha:=1.0-exp(-pose_blend*dt)
	if action in ["light","heavy","charged","combo","sweep","overhead"]:alpha=1.0-exp(-25.0*dt)
	if action=="roll" or kind=="boss" or KnightMoves.is_attack(action) or action in ["idle","move","guard"]:alpha=1.0
	if not initialized:alpha=1
	for i in skel.get_bone_count():
		var bn:=String(skel.get_bone_name(i))
		if not globals.has(bn):continue
		var parent:=skel.get_bone_parent(i)
		var local:Transform3D=globals[bn]
		if parent>=0:
			var pn:=String(skel.get_bone_name(parent))
			if globals.has(pn):local=globals[pn].affine_inverse()*local
		var cur:Transform3D=poses.get(bn,local)
		cur=cur.interpolate_with(local,alpha)
		poses[bn]=cur
		skel.set_bone_pose_position(i,cur.origin)
		skel.set_bone_pose_rotation(i,cur.basis.orthonormalized().get_rotation_quaternion())
		skel.set_bone_pose_scale(i,cur.basis.get_scale())
	skel.force_update_all_bone_transforms()
	var hand:Transform3D=motion.global_transform.affine_inverse()*skel.global_transform*skel.get_bone_global_pose(ids.hand_r)
	var delta:Transform3D=hand*rest.hand_r.affine_inverse()
	grip=delta*right_socket
	var frame:Basis=delta.basis.orthonormalized()*PALM_FRAME
	var mounted:Basis=(frame*source_frame.inverse()).scaled(Vector3.ONE*weapon_scale)
	weapon.transform=Transform3D(mounted,grip-mounted*source_grip)
	blade_dir=(mounted*(source_tip-source_grip)).normalized()
	initialized=true

func _locomotion_foot(side:String,dt:float,speed:float,direction:Vector3) -> Vector3:
	var phase:=fposmod(gait/TAU+(.0 if side=="l" else .5),1.0)
	var run:=smoothstep(1.2,3.0,speed)
	var stance:=lerpf(.62,.43,run)-smoothstep(4.5,6,speed)*.045
	var d:=direction.normalized()
	if d.length()<.1:d=Vector3.BACK
	var sx:=.155 if side=="l" else -.155
	var home:=Vector3(sx,.108,.045)
	var seed:=skel.to_global(skel.get_bone_global_pose(ids["foot_"+side]).origin)
	var toe_yaw:=clampf(atan2(d.x,absf(d.z)+.01)*.28,-.40,.40)
	var heading:Vector3=global_basis.orthonormalized()*Vector3(sin(toe_yaw),0,cos(toe_yaw))
	var velocity:Vector3=global_basis.orthonormalized()*d*speed
	var sample:Dictionary=ground_solver.sample(side,home,global_transform,velocity,phase,stance,ground_frequency,dt,lerpf(.075,.15,run),speed>.06,seed,heading)
	walk_contacts[side]=sample
	if sample.grounded:foot_plants[side]=sample.world
	else:foot_plants.erase(side)
	return sample.position

func _pose_locomotion(action:String,dt:float,speed:float,direction:Vector3) -> void:
	motion.transform=Transform3D.IDENTITY
	if last_action not in ["idle","move","guard"]:
		ground_solver.reset();locomotion_height=skel.get_bone_global_pose(ids.pelvis).origin.y
	var run:=smoothstep(1.2,3.0,speed)
	var sprint:=smoothstep(4.8,6.0,speed)
	var amount:=ground_blend
	var d:=direction.normalized()
	if d.length()<.1:d=Vector3.BACK
	var targets:={"l":_locomotion_foot("l",dt,speed,d),"r":_locomotion_foot("r",dt,speed,d)}
	var walk_height:=lerpf(.935,.875,smoothstep(.4,1.6,speed))
	var p:=Vector3(sin(gait)*.014*amount,lerpf(.95,lerpf(walk_height,.825,run),amount),0)
	p.y+=cos(gait*2)*lerpf(-.008,.012,run)*amount+sin(clock*2.1)*.003*(1-amount)
	var pelvis_yaw:=sin(gait)*.060*amount
	var chest_yaw:=-sin(gait)*.055*amount
	var bank:=sin(gait)*.024*amount
	var lean:=.08+(.12*run+.015)*amount
	var pelvis_bs:=Basis(Vector3.FORWARD,bank*.65+recoil.z*.35)*Basis(Vector3.UP,pelvis_yaw+recoil.y*.35)*Basis(Vector3.RIGHT,.025+recoil.x*.35)
	var chest_bs:=Basis(Vector3.FORWARD,bank+recoil.z)*Basis(Vector3.UP,chest_yaw+recoil.y)*Basis(Vector3.RIGHT,lean+recoil.x)
	# Keep a real bend in the support knee instead of clamping an unreachable
	# ankle in mid-air. Speed/cadence now determine the stance travel together.
	var foot_rotations:={}
	for side in ["l","r"]:
		var contact:Dictionary=walk_contacts[side]
		var u:float=contact.stance_u
		var pitch:float=(-.13*(1-smoothstep(0,.18,u))+.27*smoothstep(.68,1,u))*amount
		if not contact.grounded:pitch=lerpf(.24,-.13,smoothstep(.06,.90,float(contact.swing_u)))*amount
		var axis:Vector3=(tails["foot_"+side]-heads["foot_"+side]).normalized()
		var rest_flat:=Basis(Quaternion(axis,Vector3(0,-.035,.15).normalized()))
		var flat:=Basis(Vector3.UP,float(contact.yaw))*rest_flat
		var rot:=Basis(Vector3.UP,float(contact.yaw))*Basis(Vector3.RIGHT,pitch)*rest_flat
		var pivot:=Vector3(0,-.080,.15 if pitch>=0 else -.025)
		targets[side]+=flat*pivot-rot*pivot;foot_rotations[side]=rot
		var hip_offset:Vector3=pelvis_bs*(heads["thigh_"+side]-heads.pelvis)
		var delta:=G.flat(p+hip_offset-Vector3(targets[side]))
		var reach:float=(lengths["thigh_"+side]+lengths["shin_"+side])*.982
		var ceiling:float=Vector3(targets[side]).y+sqrt(maxf(.01,reach*reach-delta.length_squared()))-hip_offset.y
		if contact.grounded:p.y=minf(p.y,maxf(.72,ceiling))
	# Unloading a support knee raises the torso progressively. An airborne
	# ankle must not drag the pelvis after its nominal swing landmark.
	if not initialized:locomotion_height=p.y
	locomotion_height=minf(p.y,locomotion_height+dt*1.10);p.y=locomotion_height
	_oriented("root",Vector3.ZERO,Basis.IDENTITY)
	var spine:=p
	for bone in ["pelvis","spine1","spine2","neck","head"]:
		var bs:=pelvis_bs
		if bone=="spine1":bs=pelvis_bs.slerp(chest_bs,.5)
		elif bone=="spine2":bs=chest_bs
		elif bone in ["neck","head"]:bs=Basis(Vector3.UP,chest_yaw*.18)*Basis(Vector3.RIGHT,.035)
		_oriented(bone,spine,bs);spine+=bs*(tails[bone]-heads[bone])
	for side in ["l","r"]:
		var sx:=1.0 if side=="l" else -1.0
		var hip:Vector3=p+pelvis_bs*(heads["thigh_"+side]-heads.pelvis)
		var knee_pole:=Vector3(sx*.10,0,1)
		knee_pole=Basis(Vector3.UP,clampf(atan2(d.x,absf(d.z)+.01)*.45,-.55,.55))*knee_pole
		var ankle:=_ik("thigh_","shin_",side,hip,targets[side],knee_pole)
		_oriented("foot_"+side,ankle,foot_rotations[side]);feet[side]=ankle
	var chest:Vector3=globals.spine2.origin
	var left_local:=Vector3(.28,-.18,.15-sin(gait)*lerpf(.065,.12,run)*amount)
	var right_local:=Vector3(-.29,-.17+sin(gait)*.012*amount,.13+sin(gait)*.035*amount)
	var sword:Vector3=chest_bs*Vector3(-.10,-.70,.72).normalized()
	if sprint>.01:
		left_local=left_local.lerp(Vector3(.27,-.07,.17+sin(gait)*.12),sprint)
		right_local=right_local.lerp(Vector3(-.27,-.065,.14),sprint)
		sword=sword.lerp(chest_bs*Vector3(-.15,.72,-.68).normalized(),sprint).normalized()
	if action=="guard":
		left_local=Vector3(.12,.07,.32);right_local=Vector3(-.17,-.01,.35)
		sword=chest_bs*Vector3(.25,.85,-.2).normalized()
	for side in ["r","l"]:
		var sx:=1.0 if side=="l" else -1.0
		var shoulder:Vector3=globals.spine2*rest.spine2.affine_inverse()*heads["upper_"+side]
		var hand_target:Vector3=chest+chest_bs*(right_local if side=="r" else left_local)
		var pole:=chest_bs*Vector3(sx*.60,-.15,-.7)
		if side=="r":_grasp(side,shoulder,hand_target,sword,pole)
		else:
			var hand:=_ik("upper_","fore_",side,shoulder,hand_target,pole)
			var forearm:Vector3=(hand-globals.fore_l.origin).normalized()
			_put("hand_l",hand,hand+forearm.lerp(chest_bs*Vector3(0,-1,.15).normalized(),.25).normalized()*lengths.hand_l)
	_cloth(dt,p,chest_bs)
	_commit(action,dt,sword)

func impact(weight:float,world_direction:Vector3) -> void:
	var local:=global_basis.orthonormalized().inverse()*world_direction
	recoil_velocity+=Vector3(local.z,local.x*.25,-local.x)*weight*35.0

func _pose_weapon(action:String,t:float,dt:float,variant:int) -> void:
	var id:=KnightMoves.key(action,variant)
	var m:Dictionary=KnightMoves.MOVES[id]
	var entry:=last_action!=action or weapon_id!=id or t<weapon_last_t-.0001 or not initialized
	if entry:
		weapon_id=id;weapon_entry_t=0;weapon_from.clear();weapon_plants.clear()
		skel.force_update_all_bone_transforms()
		for bone in ids:weapon_from[bone]=motion.transform*skel.get_bone_global_pose(ids[bone])
		for side in ["l","r"]:
			var sx:=1.0 if side=="l" else -1.0
			var start:Vector3=motion.to_global(feet.get(side,Vector3(sx*.155,.108,.05)))
			var pattern:Dictionary=KnightMotion.PROFILES[id]
			var landing:=to_global(Vector3(sx*(.155+float(pattern.step_side)),.108,float(pattern.step)))
			weapon_plants[side]={"start":start,"landing":landing}
	weapon_last_t=t;weapon_entry_t+=dt
	motion.transform=Transform3D.IDENTITY
	var pose:Dictionary=KnightMotion.sample(id,t)
	var p:=Vector3(pose.root_x,pose.height,pose.root_z)
	var hip_yaw:float=pose.pelvis_yaw+recoil.y*.35
	var chest_yaw:float=pose.chest_yaw+recoil.y
	var pelvis_bs:=Basis(Vector3.FORWARD,float(pose.bank)*.45+recoil.z*.35)*Basis(Vector3.UP,hip_yaw)*Basis(Vector3.RIGHT,float(pose.lean)*.35+recoil.x*.35)
	var chest_bs:=Basis(Vector3.FORWARD,float(pose.bank)+recoil.z)*Basis(Vector3.UP,chest_yaw)*Basis(Vector3.RIGHT,float(pose.lean)+recoil.x)
	_oriented("root",Vector3.ZERO,Basis.IDENTITY)
	var spine:=p
	for bone in ["pelvis","spine1","spine2","neck","head"]:
		var bs:=pelvis_bs
		if bone=="spine1":bs=pelvis_bs.slerp(chest_bs,.55)
		elif bone=="spine2":bs=chest_bs
		elif bone in ["neck","head"]:
			var head_pitch:float=float(pose.lean)*(.36 if bone=="neck" else .14)
			bs=Basis(Vector3.FORWARD,float(pose.bank)*.28)*Basis(Vector3.UP,float(pose.head_yaw))*Basis(Vector3.RIGHT,head_pitch)
		var end:Vector3=spine+bs*(tails[bone]-heads[bone])
		_oriented(bone,spine,bs);spine=end
	# Rear heel pivots about the ball of the foot; the leading foot lands before
	# the blade crosses the damage window. Planted contacts remain in world space.
	for side in ["l","r"]:
		var sx:=1.0 if side=="l" else -1.0
		var lead:bool=side==String(pose.lead)
		var hip:Vector3=p+pelvis_bs*(heads["thigh_"+side]-heads.pelvis)
		var foot:=Vector3(sx*.155,.108,.05)
		var foot_yaw:float=pose.lead_yaw if lead else pose.rear_yaw
		var heel:float=pose.lead_heel if lead else pose.rear_heel
		if global_position.y>.18 and id=="jump_attack":
			foot.y+=.30;foot.z=.25 if lead else -.20;heel=0
		else:
			var plant:Dictionary=weapon_plants[side]
			var at:Vector3=plant.start
			if lead:
				var f:float=pose.step_load
				at=plant.start.lerp(plant.landing,BeastMoves.smooth_motion(f));at.y+=sin(f*PI)*.065
			var recover:float=pose.settle
			at=at.lerp(to_global(foot),recover);at.y+=sin(recover*PI)*(.045 if lead else .075)
			foot=to_local(at)
		# Rotate about a fixed toe, raising the ankle/heel without skating it.
		var rest_axis:Vector3=(tails["foot_"+side]-heads["foot_"+side]).normalized()
		var flat:=Basis(Quaternion(rest_axis,Vector3(0,-.035,.15).normalized()))
		var rot:=Basis(Vector3.UP,foot_yaw)*Basis(Vector3.RIGHT,heel)*flat
		var ball:=Vector3(0,-.080,.15)
		var ankle_target:=foot+flat*ball-rot*ball
		var ankle:=_ik("thigh_","shin_",side,hip,ankle_target,pelvis_bs*Vector3(sx*.10,.04,1))
		_oriented("foot_"+side,ankle,rot);feet[side]=ankle
	var chest_pivot:Vector3=globals.spine2.origin
	var palm:Vector3=chest_pivot+chest_bs*Vector3(pose.hand)
	var sword:Vector3=chest_bs*Vector3(pose.sword)
	for side in ["r","l"]:
		var sx:=1.0 if side=="l" else -1.0
		var shoulder:Vector3=globals.spine2*rest.spine2.affine_inverse()*heads["upper_"+side]
		var pole:=chest_bs*Vector3(sx*.65,-.18,-.65)
		if side=="r":_grasp(side,shoulder,palm,sword,pole,float(pose.wrist_roll))
		elif KnightMoves.two_handed(action,variant):
			var actual_palm:Vector3=globals.hand_r*rest.hand_r.affine_inverse()*right_socket
			_grasp(side,shoulder,actual_palm-sword*.075,sword,pole,float(pose.wrist_roll))
		else:
			var free:Vector3=chest_pivot+chest_bs*Vector3(pose.free)
			var hand:=_ik("upper_","fore_",side,shoulder,free,pole)
			var forearm:Vector3=(hand-globals.fore_l.origin).normalized()
			var relaxed:=forearm.lerp(chest_bs*Vector3(0,-1,.15).normalized(),.25).normalized()
			_put("hand_l",hand,hand+relaxed*lengths.hand_l)
	var blend:=smoothstep(0,.105,weapon_entry_t)
	if initialized and blend<1:
		for bone in globals:
			if weapon_from.has(bone):globals[bone]=weapon_from[bone].interpolate_with(globals[bone],blend)
	for side in feet:feet[side]=globals["foot_"+side].origin
	_cloth(dt,p,chest_bs)
	_commit(action,dt,sword)

func _beast_contact(id:String,home:Vector3,phase_offset:float,dt:float,speed:float,direction:Vector3,weight:float) -> Vector3:
	# Stance contacts stay in world space. A separate swing brings them forward.
	var xf:=motion.global_transform
	var desired_world:=xf*home
	if ground_locomotion:
		var offset:float={"l":.37,"r":.10,"paw":.60}[id]
		var phase:=fposmod(gait/TAU+offset,1.0)
		var d:=direction.normalized()
		if d.length()<.1:d=Vector3.BACK
		var heading_yaw:=clampf(atan2(d.x,absf(d.z)+.01)*.22,-.34,.34)
		var heading:=xf.basis.orthonormalized()*Vector3(sin(heading_yaw),0,cos(heading_yaw))
		var velocity:=xf.basis.orthonormalized()*d*speed
		var bone:="hand_l" if id=="paw" else "foot_"+id
		var actual:Transform3D=skel.get_bone_global_pose(ids[bone])
		var seed:=skel.to_global(actual.origin)
		if id=="paw":seed=skel.to_global(actual*rest.hand_l.affine_inverse()*support_socket)
		if not initialized:seed=desired_world
		var lift:float=(.075 if id=="paw" else .09)*unit*xf.basis.get_scale().y*lerpf(.55,1.0,smoothstep(.3,3.0,speed))
		var fast:=smoothstep(3.4,5.2,speed)
		var stance:=lerpf(.60,.58,fast) if id=="paw" else lerpf(.80,.77,fast)
		var sample:Dictionary=ground_solver.sample(id,home,xf,velocity,phase,stance,ground_frequency,dt,lift,speed>.08,seed,heading,true)
		walk_contacts[id]=sample
		if sample.grounded:beast_plants[id]=sample.world
		else:beast_plants.erase(id)
		if sample.landed and G.audio:G.audio.play("boss_step",sample.world,-5 if id=="paw" else -9,1.0 if id=="paw" else .93)
		beast_contact_targets[id]=sample.world
		return sample.position
	if weight<.999:
		if not beast_releases.has(id):
			var anchor:Vector3=beast_plants.get(id,beast_contact_targets.get(id,desired_world))
			beast_releases[id]={"from":anchor,"time":0.0}
		var release:Dictionary=beast_releases[id]
		release.time+=dt
		beast_plants.erase(id);beast_swings.erase(id)
		var point:Vector3=Vector3(release.from).lerp(desired_world,smoothstep(0,.10,float(release.time)))
		beast_contact_targets[id]=point
		return xf.affine_inverse()*point
	if beast_releases.has(id):
		var release:Dictionary=beast_releases[id]
		if not release.has("land_from"):
			release.land_from=beast_contact_targets.get(id,desired_world);release.land_time=0.0
		release.land_time+=dt
		var f:=smoothstep(0,.06,float(release.land_time))
		var point:Vector3=Vector3(release.land_from).lerp(desired_world,f)
		point.y=maxf(point.y,desired_world.y)
		beast_contact_targets[id]=point
		if f<1:return xf.affine_inverse()*point
		beast_plants[id]=desired_world;beast_releases.erase(id)
	var phase:=fposmod(gait/TAU+phase_offset,1.0)
	var moving:=speed>.12
	var stance:=.52 if id=="paw" else .66
	var d:=direction.normalized()
	if d.length()<.1:d=Vector3(0,0,1)
	var frequency:=clampf(speed/1.75,.50,2.7)
	var duration:=clampf((1-stance)/frequency,.12,.28) if moving else .18
	var reach:=speed*duration/maxf(.1,global_basis.get_scale().x)+(.16*unit if id!="paw" else 0.0)
	var desired:=home+d*reach if moving else home
	var cycle:=int(floor(gait/TAU+phase_offset))
	var swing:bool=moving and phase>=stance and beast_step_cycles.get(id,-1)!=cycle
	if beast_plants.has(id):
		var local:Vector3=xf.affine_inverse()*beast_plants[id]
		if G.flat(local-home).length()>(1.15*unit if moving else .42*unit):swing=true
	if swing or beast_swings.has(id):
		if not beast_swings.has(id):
			var start:Vector3=beast_plants.get(id,xf*home)
			beast_swings[id]={"from":start,"to":xf*desired,"t":0.0,"duration":duration}
			beast_step_cycles[id]=cycle
			beast_plants.erase(id)
		var step:Dictionary=beast_swings[id]
		step.t+=dt
		var f:float=clampf(step.t/step.duration,0,1)
		var point:Vector3=step.from.lerp(step.to,BeastMoves.smooth_motion(f))
		point.y+=sin(f*PI)*(.19 if id=="paw" else .13)*unit
		if f>=1:
			beast_plants[id]=step.to;beast_swings.erase(id)
			if G.audio:G.audio.play("boss_step",point,-5 if id=="paw" else -9,1.0 if id=="paw" else .93)
		beast_contact_targets[id]=point
		return xf.affine_inverse()*point
	if not beast_plants.has(id):beast_plants[id]=xf*home
	beast_contact_targets[id]=beast_plants[id]
	return xf.affine_inverse()*beast_plants[id]

func _pose_beast(action:String,t:float,dt:float,speed:float,direction:Vector3) -> void:
	motion.transform=Transform3D.IDENTITY
	ground_locomotion=action in ["idle","move"]
	if ground_locomotion and last_action not in ["idle","move"]:
		ground_solver.reset();beast_body_support=Vector3.ZERO
	var target:Dictionary=BeastMotion.sample(action,t,clock)
	if last_action!=action and not beast_pose.is_empty():
		beast_blend_from=beast_pose.duplicate();beast_blend_time=0
	beast_blend_time+=dt
	var blend:=smoothstep(0,.15,beast_blend_time)
	if not beast_blend_from.is_empty() and initialized and blend<1:
		for k in target:target[k]=lerpf(beast_blend_from[k],target[k],blend)
	beast_pose=target
	var flight:float=target.flight
	var moving:=action in ["idle","move"] and speed>.12
	var root_shift:=Vector3(float(target.get("root_x",0)),0,float(target.get("root_z",0)))*unit
	var p:=Vector3(root_shift.x,float(target.height)*unit,-.15*unit+root_shift.z)
	if ground_locomotion and ground_blend>.001:
		p.y+=.026*unit*ground_blend
		p.y+=sin(gait*3-.45)*.009*unit*ground_blend
		p.z+=sin(gait*3-.4)*.010*unit*ground_blend
		p.x+=sin(gait)*.016*unit*ground_blend
	var lean:float=target.lean+recoil.x
	var twist:float=target.twist+sin(clock*1.3)*.012*(1-flight)+recoil.y
	var bank:float=target.bank+recoil.z
	if ground_locomotion and ground_blend>.001:
		lean+=.07*ground_blend
		bank+=sin(gait+.5)*.028*ground_blend
		twist+=sin(gait-.2)*.034*ground_blend
		lean+=sin(gait*3+.3)*.010*ground_blend
	var pelvis_yaw:=twist*.35+float(target.get("pelvis_yaw",0))
	var chest_yaw:=twist+float(target.get("chest_yaw",0))
	var body:=Basis(Vector3.FORWARD,bank)*Basis(Vector3.UP,chest_yaw)*Basis(Vector3.RIGHT,lean+.06)
	var pelvis_bs:=Basis(Vector3.FORWARD,bank*.7)*Basis(Vector3.UP,pelvis_yaw)*Basis(Vector3.RIGHT,lean*.55)
	_put("root",Vector3.ZERO,Vector3.UP*.1*unit)
	var spine:=p
	for bn in ["pelvis","spine1","spine2","neck","head"]:
		var pitch:float=lean
		var turning:float=lerpf(pelvis_yaw,chest_yaw,.5)
		if bn=="pelvis":pitch=lean*.55;turning=pelvis_yaw
		elif bn=="spine2":pitch=lean+.06;turning=chest_yaw
		elif bn=="neck":pitch=.35+float(target.head_pitch)*.45;turning=chest_yaw*.35
		elif bn=="head":pitch=target.head_pitch;turning=chest_yaw*.13
		if moving and bn in ["neck","head"]:pitch-=sin(gait*2-.45)*.016
		var bs:=Basis(Vector3.FORWARD,bank)*Basis(Vector3.UP,turning)*Basis(Vector3.RIGHT,pitch)
		var end:Vector3=spine+bs*(tails[bn]-heads[bn])
		_oriented(bn,spine,bs);spine=end
	var left:=Vector3(target.paw_x,0,target.paw_z)*unit
	if ground_locomotion:left.z=lerpf(left.z,.32*unit,ground_blend)
	left.y=(.045-motion.global_position.y)/maxf(.1,motion.global_basis.get_scale().y)
	left.y+=((1-float(target.paw_weight))*.44+float(target.get("paw_y",0))+flight*.12)*unit
	left.z-=flight*.17*unit
	if float(target.paw_weight)>=.999 and flight<.001:left.y=(.045-motion.global_position.y)/maxf(.1,motion.global_basis.get_scale().y)
	left=_beast_contact("paw",left,.25,dt,speed if moving else 0.0,direction,float(target.paw_weight)*(1-flight))
	if float(target.paw_weight)>.92 and flight<.08:
		var shoulder:Vector3=globals.spine2*rest.spine2.affine_inverse()*heads.upper_l
		var reach:float=lengths.upper_l+lengths.fore_l-.025
		var support_goal:=left
		if ground_locomotion and not bool(walk_contacts.paw.grounded):
			var landing:Vector3=motion.to_local(walk_contacts.paw.landing)
			support_goal=support_goal.lerp(landing,smoothstep(.15,.70,float(walk_contacts.paw.swing_u)))
		var wrist:Vector3=support_goal-_paw_rotation()*(support_socket-heads.hand_l)
		var to_paw:=G.flat(wrist-shoulder)
		var shift:=to_paw.normalized()*minf((.12 if ground_locomotion else .065)*unit,maxf(0,to_paw.length()-reach*.86))
		var horizontal:=G.flat(shoulder+shift-wrist).length()
		var support_drop:=minf((.14 if ground_locomotion else .08)*unit,maxf(0,shoulder.y-wrist.y-sqrt(maxf(.01,reach*reach-horizontal*horizontal))))
		var support_delta:=shift+Vector3.DOWN*support_drop
		if ground_locomotion:
			var contact:Dictionary=walk_contacts.paw
			var weight:float=contact.load
			support_delta=beast_body_support.lerp(support_delta*weight,1-exp(-14*dt))
			if contact.grounded:
				# Minimal whole-body correction makes the palm reachable without
				# stretching a forearm or translating the wrist off its elbow.
				var vector:=wrist-(shoulder+support_delta)
				if vector.length()>reach:support_delta+=vector.normalized()*(vector.length()-reach)
			beast_body_support=support_delta
		p+=support_delta
		for bone in globals:
			if bone!="root":globals[bone].origin+=support_delta
	var a:float=target.blade_yaw
	var pitch:float=target.blade_pitch
	var sword:=Vector3(sin(a)*cos(pitch),sin(pitch),cos(a)*cos(pitch))
	var right:=Vector3(float(target.hand_x)+sin(a)*.26,target.hand_y,target.hand_reach+cos(a)*.10)*unit
	# Carry the hand with the torso. Absolute IK landmarks previously cancelled
	# nearly all shoulder motion and made each cut look like a detached arm.
	var neutral_p:=Vector3(0,float(target.height),-.15)*unit
	var neutral_chest:Vector3=neutral_p+Basis(Vector3.RIGHT,lean*.55)*(tails.pelvis-heads.pelvis)+Basis(Vector3.RIGHT,lean)*(tails.spine1-heads.spine1)
	var neutral_frame:=Basis(Vector3.RIGHT,lean+.06)
	var carried:Vector3=globals.spine2.origin+body*neutral_frame.inverse()*(right-neutral_chest)
	var carry:=.45+float(target.get("body_drive",0))*.12
	right=right.lerp(carried,carry)+root_shift*(1-carry)
	right+=body*Vector3(0,0,.035)*unit*float(target.get("shoulder_reach",0))
	beast_contacts.clear()
	for side in ["l","r"]:
		var sx:=1.0 if side=="l" else -1.0
		var foot:=Vector3(sx*.24*float(target.spread),.125,target.foot_lz if side=="l" else target.foot_rz)*unit
		if ground_locomotion:foot.z=lerpf(foot.z,-.36*unit,ground_blend)
		foot.y+=flight*(.37 if side=="l" else .31)*unit
		foot.z+=flight*(.24 if side=="l" else -.12)*unit
		var foot_lift:float=target.get("foot_lift_"+side,0)
		if foot_lift<=.002:foot_lift=0
		foot.y+=foot_lift*unit
		# A deliberate step releases its world plant, then establishes a new one.
		foot=_beast_contact(side,foot,0 if side=="l" else .5,dt,speed if moving else 0.0,direction,0.0 if foot_lift>.002 else 1-flight)
		var hip:Vector3=p+pelvis_bs*(heads["thigh_"+side]-heads.pelvis)
		var foot_yaw:float=target.get("foot_yaw_"+side,0)
		if ground_locomotion and walk_contacts.has(side):foot_yaw=walk_contacts[side].yaw
		var heel:=float(target.get("body_drive",0))*.12 if foot_lift<.002 and flight<.05 else 0.0
		var rest_axis:Vector3=(tails["foot_"+side]-heads["foot_"+side]).normalized()
		var flat:=Basis(Quaternion(rest_axis,Vector3(0,-.035,.15).normalized()))
		var rot:=Basis(Vector3.UP,foot_yaw)*Basis(Vector3.RIGHT,heel)*flat
		var ball:=Vector3(0,-.080,.15)*unit
		var baseline_flat:=Basis(Vector3.UP,foot_yaw)*flat if ground_locomotion else flat
		var ankle_target:=foot+baseline_flat*ball-rot*ball
		var knee_pole:=pelvis_bs*Vector3(sx*.40,.75,.65)
		if ground_locomotion:
			var travel_yaw:=clampf(atan2(direction.x,absf(direction.z)+.01)*.35,-.45,.45)
			knee_pole=Basis(Vector3.UP,pelvis_yaw+travel_yaw)*Vector3(sx*.10,.60,1.0)
		var ankle:=_ik("thigh_","shin_",side,hip,ankle_target,knee_pole)
		_oriented("foot_"+side,ankle,rot)
		feet[side]=ankle
		beast_contacts[side]=motion.to_global(ankle)
		var shoulder:Vector3=globals.spine2*rest.spine2.affine_inverse()*heads["upper_"+side]
		shoulder+=body*Vector3(0,.008,.030)*unit*float(target.get("shoulder_reach",0))
		var pole:=Basis(Vector3.UP,chest_yaw)*Vector3(sx*.90,-.20,-.65)
		if side=="r":
			# Raise the grip on a downward slam, preserving a vertical blade at contact.
			var floor_y:float=(.035-motion.global_position.y)/maxf(.1,motion.global_basis.get_scale().y)
			right.y=maxf(right.y,floor_y-sword.y*blade_length)
			_grasp(side,shoulder,right,sword,pole,float(target.get("wrist_roll",0)))
		else:
			_support_paw(shoulder,left,pole)
			beast_contacts.paw=motion.to_global(globals.hand_l*rest.hand_l.affine_inverse()*support_socket)
	if action=="dead":p.y+=_corpse_floor()
	_cloth(dt,p,body)
	_beast_cloth_floor()
	_commit(action,dt,sword)

func _pose_roll(t:float,dt:float) -> void:
	var f:=clampf(t/.70,0,1)
	if last_action!="roll" or f<previous_roll_phase:
		roll_feet_world.clear()
	previous_roll_phase=f
	roll_phase=f
	var authored:=RollMotion.sample(f)
	var tuck:float=authored.tuck
	var spin:float=authored.spin
	var bank:float=authored.bank
	var heading:=atan2(roll_direction.x,roll_direction.z)
	# Lock-on keeps the chest facing its target: the body tumbles about the
	# horizontal axis perpendicular to travel instead of turning a forward roll.
	var turn:=smoothstep(0,.12,f)*(1-smoothstep(.79,1,f))
	motion.transform=Transform3D.IDENTITY if roll_locked else Transform3D(Basis(Vector3.UP,wrapf(heading,-PI,PI)*turn),Vector3.ZERO)
	var axis:=Vector3.UP.cross(roll_direction).normalized() if roll_locked else Vector3.RIGHT
	if axis.length_squared()<.5:axis=Vector3.RIGHT
	var tumble:=Basis(axis,spin)
	var p:=Vector3(.045*sin(f*PI),authored.height,0)
	var pelvis_bs:=Basis(Vector3.FORWARD,bank)*tumble*Basis(Vector3.RIGHT,.08)
	var spinal:=p
	var radii:={"pelvis":.17,"spine1":.17,"spine2":.18,"neck":.14,"head":.32}
	for bn in ["pelvis","spine1","spine2","neck","head"]:
		var flex:float={"pelvis":0.0,"spine1":.25,"spine2":.60,"neck":1.20,"head":1.68}[bn]*tuck
		var bs:=Basis(Vector3.FORWARD,bank)*tumble*Basis(Vector3.RIGHT,.08+flex)
		var endpoint:Vector3=spinal+bs*(tails[bn]-heads[bn])
		_oriented(bn,spinal,bs)
		spinal=endpoint
	_put("root",Vector3.ZERO,Vector3.UP*.1)
	for side in ["l","r"]:
		var sx:=1.0 if side=="l" else -1.0
		var lead:=1.0 if side=="l" else .84
		var hip:Vector3=p+pelvis_bs*(heads["thigh_"+side]-heads.pelvis)
		var hip_flex:float=-2.05*tuck*lead
		var knee_flex:float=2.65*tuck*(.94 if side=="l" else 1.0)
		var leg_bs:=Basis(Vector3.FORWARD,bank)*tumble*Basis(Vector3.RIGHT,hip_flex)
		var shin_bs:=Basis(Vector3.FORWARD,bank)*tumble*Basis(Vector3.RIGHT,hip_flex+knee_flex)
		var knee:Vector3=hip+leg_bs*Vector3.DOWN*lengths["thigh_"+side]
		var ankle:Vector3=knee+shin_bs*Vector3.DOWN*lengths["shin_"+side]
		var plant:=smoothstep(.56 if side=="l" else .70,.78 if side=="l" else .90,f)
		var landing:=Vector3(sx*.16,.108,lerpf(.26 if side=="l" else -.15,.055,smoothstep(.87,1,f)))
		var contact_time:=.68 if side=="l" else .80
		if f>=contact_time:
			if not roll_feet_world.has(side):roll_feet_world[side]=motion.to_global(landing)
			var planted:Vector3=motion.to_local(roll_feet_world[side])
			planted.y=.108
			landing=landing.lerp(planted,smoothstep(contact_time,contact_time+.07,f))
			if side=="r" and f>.91:
				var recover:=smoothstep(.91,1,f)
				landing=landing.lerp(Vector3(sx*.16,.108,.055),recover)
				landing.y+=sin(recover*PI)*.045
		if plant>.0:
			var old_ankle:Vector3=ankle
			ankle=_ik("thigh_","shin_",side,hip,old_ankle.lerp(landing,plant),Vector3(sx*.1,0,1))
		else:
			_put("thigh_"+side,hip,knee)
			_put("shin_"+side,knee,ankle)
		var foot_bs:=Basis(axis,spin*(1-plant))*Basis(Vector3.RIGHT,(hip_flex+knee_flex*.72)*(1-plant))
		_put("foot_"+side,ankle,ankle+foot_bs*Vector3(0,-.035,.15))
		feet[side]=ankle
		var chest:Transform3D=globals.spine2
		var shoulder:Vector3=chest.origin+chest.basis*rest.spine2.basis.inverse()*(heads["upper_"+side]-heads.spine2)
		# The free palm braces the approach; the sword arm stays close to the ribs.
		var local_hand:=Vector3(sx*lerpf(.29,.23,tuck),lerpf(-.24,-.05,tuck),lerpf(.12,.34,tuck))
		var chest_basis:=Basis(Vector3.FORWARD,bank)*tumble*Basis(Vector3.RIGHT,.35*tuck)
		var hand_target:Vector3=globals.spine2.origin+chest_basis*local_hand
		if side=="l":
			var brace:=sin(smoothstep(.06,.28,f)*PI)*(1-smoothstep(.28,.36,f))
			var brace_at:=Vector3(.27,.09,.50)
			if roll_locked:
				brace_at=roll_direction*.46+Vector3(0,.09,0)
				if roll_direction.x<-.25:brace*=.25
			hand_target=hand_target.lerp(brace_at,brace*.72)
		var pole:=chest_basis*Vector3(sx*.85,-.35,-.30)
		var sword_axis:=chest_basis*Vector3(-.24,.12,.96).normalized()
		if side=="r":
			_grasp(side,shoulder,hand_target,sword_axis,pole);grip=globals.hand_r*rest.hand_r.affine_inverse()*right_socket;blade_dir=sword_axis
		else:
			var hand:=_ik("upper_","fore_",side,shoulder,hand_target,pole)
			_put("hand_l",hand,hand+(chest_basis*Vector3(0,-1,.15)).normalized()*lengths.hand_l)
	_cloth(dt,p,pelvis_bs)
	# The shoulder/back and the boots support the roll; the helmet stays clear.
	var min_y:=100.0
	if not contact_probes.is_empty():
		for probe in contact_probes:
			var point:=Vector3.ZERO
			for link in probe:point+=(globals[link.bone]*link.local)*link.weight
			min_y=minf(min_y,point.y)
	else:
		for bn in globals:
			if bn=="root":continue
			var rad:float=radii.get(bn,.065 if bn.begins_with("hand") else .09)
			min_y=minf(min_y,globals[bn].origin.y-rad)
	var side_clearance:=(.014+.018*absf(roll_direction.x))*pow(sin(f*PI),2) if roll_locked else 0.0
	var lift:=ground_min+side_clearance-min_y
	for bn in globals:
		if bn!="root":globals[bn].origin.y+=lift
	grip.y+=lift
	p.y+=lift
	for side in feet:feet[side].y+=lift
	# Carry the blade beside the folded body, keeping its tip above the stone.
	var lowest_axis:=clampf((ground_min-grip.y)/blade_length,-.98,.98)
	if blade_dir.y<lowest_axis:
		var horizontal:=Vector3(blade_dir.x,0,blade_dir.z).normalized()
		blade_dir=horizontal*sqrt(1-lowest_axis*lowest_axis)+Vector3.UP*lowest_axis
		_orient_grip("r",blade_dir)
	roll_ground_clearance=min_y+lift
	roll_support="push" if f<.17 else ("shoulder" if f<.42 else ("back" if f<.65 else "plant"))
	_commit("roll",dt,blade_dir)

func _cloth(dt:float,p:Vector3,body:Basis) -> void:
	if globals.has("pelvis") and rest.has("loin"):
		var anchor:Vector3=globals.pelvis*rest.pelvis.affine_inverse()*heads.loin
		_put("loin",anchor,anchor+Vector3(.015*sin(clock*2),-.99,.12).normalized()*lengths.loin)
	if not secondary_motion:return
	var xf:=motion.global_transform
	var inv:=xf.affine_inverse()
	var h:=minf(dt,1.0/30.0)
	var inertia:=Vector3.ZERO
	if cloth_has_frame:
		var transport:=xf*cloth_last_frame.affine_inverse()
		for key in cloth_points:
			cloth_points[key]=transport*Vector3(cloth_points[key])
			cloth_previous[key]=transport*Vector3(cloth_previous[key])
		var velocity:Vector3=(xf.origin-cloth_last_frame.origin)/maxf(dt,.001)
		inertia=-(velocity-cloth_root_velocity)/maxf(dt,.001)
		inertia=inertia.limit_length(25)*.16;cloth_root_velocity=velocity
	cloth_last_frame=xf;cloth_has_frame=true
	for ci in 5:
		var anchor:=_point(heads["cape_%d_0"%ci],p,body)
		var parent_id:int=skel.get_bone_parent(ids["cape_%d_0"%ci])
		var parent_name:String=skel.get_bone_name(parent_id)
		if globals.has(parent_name):
			anchor=globals[parent_name]*rest[parent_name].affine_inverse()*heads["cape_%d_0"%ci]
		var ends:Array[Vector3]=[xf*anchor]
		for seg in 3:
			var key:="%d_%d"%[ci,seg]
			var bn:="cape_"+key
			var seed:Vector3=ends.back()+xf.basis*body*(tails[bn]-heads[bn])
			var current:Vector3=cloth_points.get(key,seed)
			var previous:Vector3=cloth_previous.get(key,current)
			if current.distance_to(ends[0])>2.3*unit:current=seed;previous=seed
			var wind:=Vector3(sin(clock*1.7+ci*.4)*.35,0,-.35)*unit
			var next:=current+(current-previous)*exp(-9*h)+(Vector3.DOWN*12+wind+inertia)*h*h
			cloth_previous[key]=current
			ends.append(next)
		for iteration in (3 if G.mobile else 5):
			for seg in 3:
				var bn:="cape_%d_%d"%[ci,seg]
				var v:Vector3=ends[seg+1]-ends[seg]
				if v.length()<.001:v=Vector3.DOWN
				ends[seg+1]=ends[seg]+v.normalized()*lengths[bn]*(xf.basis.get_scale().y if kind=="boss" else 1.0)
				var local:Vector3=inv*ends[seg+1]
				# A capsule along the spine keeps the cloth outside the armour.
				var chest:Vector3=globals.spine2.origin if globals.has("spine2") else p+Vector3.UP*.3*unit
				var nearest:=CombatMath.point_segment(local,p,chest)
				var off:=local-nearest
				var r:=.19*unit
				if off.length()<r and off.length()>.001:local=nearest+off.normalized()*r
				ends[seg+1]=xf*local
				ends[seg+1].y=maxf(.15 if kind=="knight" else .12*unit,ends[seg+1].y)
		for seg in 3:
			var key:="%d_%d"%[ci,seg]
			cloth_points[key]=ends[seg+1]
			_put("cape_"+key,inv*ends[seg],inv*ends[seg+1])

func blade() -> Array:
	return [weapon.to_global(source_shoulder),weapon.to_global(source_tip)]

func target_point() -> Vector3:
	if globals.has("spine2"):return motion.global_transform*globals.spine2.origin
	return global_position+Vector3.UP*unit

func _vec(a:Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

func _grip_frame(axis:Vector3,forward:Vector3,side:="r") -> Basis:
	var y:=axis.normalized();var z:=forward-y*forward.dot(y)
	if initialized and hand_frames.has(side):
		var previous:Basis=hand_frames[side]
		var transported:=previous.z-y*previous.z.dot(y)
		if transported.length_squared()>.001:
			transported=transported.normalized()
			if z.dot(transported)<0:z=-z
			z=transported.lerp(z.normalized(),smoothstep(.03,.25,z.length_squared())*.55)
	if z.length_squared()<.025:z=Vector3(0,0,1)-y*y.z
	if z.length_squared()<.025:z=Vector3.DOWN-y*y.dot(Vector3.DOWN)
	z=z.normalized();var x:=y.cross(z).normalized()
	var frame:=Basis(x,y,x.cross(y).normalized())
	hand_frames[side]=frame
	return frame

func _grasp(side:String,shoulder:Vector3,palm:Vector3,axis:Vector3,pole:Vector3,wrist_roll:=0.0) -> void:
	var socket:Vector3=right_socket if side=="r" else left_socket
	var frame:=Basis(axis.normalized(),wrist_roll)*_grip_frame(axis,palm-shoulder,side)
	var rotation:=frame*PALM_FRAME.inverse()
	var wrist:Vector3=palm-rotation*(socket-heads["hand_"+side])
	var hand:=_ik("upper_","fore_",side,shoulder,wrist,pole)
	globals["hand_"+side]=Transform3D(rotation*rest["hand_"+side].basis,hand)

func _orient_grip(side:String,axis:Vector3) -> void:
	var hand:Transform3D=globals["hand_"+side]
	var frame:=_grip_frame(axis,hand.origin-globals["fore_"+side].origin)
	globals["hand_"+side].basis=frame*PALM_FRAME.inverse()*rest["hand_"+side].basis

func _paw_rotation() -> Basis:
	var normal:=support_normal
	var across:=Vector3.BACK-normal*Vector3.BACK.dot(normal);across=across.normalized()
	var source:=Basis(across,normal,across.cross(normal))
	return Basis(Vector3.LEFT,Vector3.DOWN,Vector3.BACK)*source.inverse()

func _support_paw(shoulder:Vector3,contact:Vector3,pole:Vector3) -> void:
	var rotation:=_paw_rotation()
	var wrist:Vector3=contact-rotation*(support_socket-heads.hand_l)
	var hand:=_ik("upper_","fore_","l",shoulder,wrist,pole)
	globals.hand_l=Transform3D(rotation*rest.hand_l.basis,hand)

func _corpse_floor() -> float:
	if corpse_probes.is_empty():
		var probes:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/boss_body_contacts.json"))
		for probe in probes:
			var point:=_vec(probe.point);var links:=[]
			for link in probe.influences:links.append({"bone":link.bone,"local":rest[link.bone].affine_inverse()*point,"weight":float(link.weight)})
			corpse_probes.append(links)
	var floor_y:float=(.055-motion.global_position.y)/maxf(.1,motion.global_basis.get_scale().y)
	var min_y:=INF
	for probe in corpse_probes:
		var point:=Vector3.ZERO
		for link in probe:point+=(globals[link.bone]*link.local)*link.weight
		min_y=minf(min_y,point.y)
	var lift:=maxf(0,floor_y-min_y)
	if lift>0:
		for bone in globals:
			if bone!="root":globals[bone].origin.y+=lift
	return lift
