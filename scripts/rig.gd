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
var pose_blend := 13.0
var initialized := false
var feet := {}
var foot_plants := {}
var foot_swing := {}
var cloth_points := {}
var cloth_previous := {}
var roll_phase := 0.0
var roll_support := "feet"
var roll_ground_clearance := 0.0
var last_action := ""
var ground_min := .035
var breathing := 0.0
var contact_probes:Array=[]
var roll_feet_world:={}
var previous_roll_phase:=-1.0
var body_materials:Array[StandardMaterial3D]=[]
var beast_pose:Dictionary={}
var beast_blend_from:Dictionary={}
var beast_blend_time:=0.0
var beast_plants:Dictionary={}
var beast_swings:Dictionary={}
var beast_contacts:Dictionary={}
var beast_step_cycles:Dictionary={}
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

func setup(p_kind: String) -> void:
	kind = p_kind
	unit = 1.0 if kind == "knight" else 2.05
	motion = Node3D.new()
	add_child(motion)
	model = load("res://assets/characters/"+kind+".glb").instantiate()
	motion.add_child(model)
	skel = _skeleton(model)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/"+kind+".json"))
	for i in skel.get_bone_count():
		var n := String(skel.get_bone_name(i))
		ids[n] = i
		rest[n] = skel.get_bone_global_rest(i)
		var b: Dictionary = data.bones.get(n, {})
		if b.is_empty(): continue
		heads[n] = Vector3(b.head[0],b.head[1],b.head[2])
		tails[n] = Vector3(b.tail[0],b.tail[1],b.tail[2])
		lengths[n] = heads[n].distance_to(tails[n])
		if kind=="boss" and (n.begins_with("upper_") or n.begins_with("fore_")):lengths[n]*=1.6
	weapon = load("res://assets/weapons/"+("player_sword" if kind=="knight" else "boss_sword")+".glb").instantiate()
	motion.add_child(weapon)
	if kind == "boss":
		weapon.scale = Vector3.ONE*1.38
		blade_length = 2.12
	else:
		blade_length = 1.06
	for mi in model.find_children("*","MeshInstance3D",true,false):
		mi.extra_cull_margin = 5.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var base:Material=mi.get_active_material(0)
		if base is StandardMaterial3D:
			var mat:StandardMaterial3D=base.duplicate()
			mat.metallic=1.0 if int(G.settings.get("quality",1))>0 else .48
			mat.metallic_texture=load("res://assets/characters/"+kind+"_armor_orm.png");mat.metallic_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			mat.albedo_texture=load("res://assets/characters/"+kind+"_surface.jpg")
			mat.roughness=1.0;mat.roughness_texture=mat.metallic_texture;mat.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			mat.normal_scale=.62 if kind=="knight" else .52
			mi.material_override=mat
			body_materials.append(mat)
	if kind=="knight" and FileAccess.file_exists("res://assets/characters/knight_contacts.json"):
		var probes:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/knight_contacts.json"))
		for probe in probes:
			var point:=Vector3(probe.point[0],probe.point[1],probe.point[2])
			contact_probes.append({"bone":probe.bone,"local":rest[probe.bone].affine_inverse()*point})
	if kind=="boss":
		beast_cloth_ids.resize(skel.get_bone_count())
		for bone in ids:beast_cloth_ids[ids[bone]]=int(String(bone).begins_with("cape_"))
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
	for mat in body_materials:
		mat.normal_enabled=quality>0
		mat.metallic=1.0 if quality>0 else .12
		mat.roughness=1.0 if quality>0 else .70
		var packed:Texture2D=load("res://assets/characters/"+kind+"_armor_orm.png")
		mat.metallic_texture=packed if quality>0 else null
		mat.roughness_texture=packed if quality>0 else null

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
	if kind=="boss" and (n.begins_with("upper_") or n.begins_with("fore_")):bs=bs.scaled(Vector3.ONE*1.6)
	globals[n] = Transform3D(bs,a)

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
	recoil_velocity+=(-recoil*210.0-recoil_velocity*24.0)*dt
	recoil+=recoil_velocity*dt
	gait += dt*(TAU*clampf(speed/2.25,.65,2.9) if kind=="knight" else TAU*clampf(speed/1.75,.50,2.7))*float(speed>.05)
	globals.clear()
	if not initialized:
		recoil=Vector3.ZERO;recoil_velocity=Vector3.ZERO
		cloth_points.clear();cloth_previous.clear();foot_plants.clear();foot_swing.clear()
		beast_plants.clear();beast_swings.clear();beast_pose.clear();beast_contacts.clear();beast_blend_from.clear();beast_step_cycles.clear()
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
			p.y=lerpf(.95,.20,f);lean=-1.35*f;lf.z=.50*f;rf.z=.62*f;right.y=.25;left.y=.28
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
		_put(bn,_point(heads[bn],p,body),_point(tails[bn],p,body))
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
		var hand:=_ik("upper_","fore_",side,shoulder,hand_target,elbow_pole)
		var hand_axis:Vector3=sword if side=="r" else Vector3(0,-1,.15)
		_put("hand_"+side,hand,hand+hand_axis.normalized()*lengths["hand_"+side])
		if side=="r":grip=hand
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
	var floor_y:float=(.045-xf.origin.y)/scale_y
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
	# Smooth local transforms while maintaining a deterministic animation clock.
	var alpha:=1.0-exp(-pose_blend*dt)
	if action in ["light","heavy","charged","combo","sweep","overhead"]:alpha=1.0-exp(-25.0*dt)
	if action=="roll" or kind=="boss" or KnightMoves.is_attack(action):alpha=1.0
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
	blade_dir=sword.normalized()
	var x:=Vector3.RIGHT
	if absf(x.dot(blade_dir))>.94:x=Vector3.FORWARD
	var z:=x.cross(blade_dir).normalized()
	x=blade_dir.cross(z).normalized()
	var ws:=1.0 if kind=="knight" else 1.38
	weapon.transform=Transform3D(Basis(x,blade_dir,z).scaled(Vector3.ONE*ws),grip)
	initialized=true

func _locomotion_foot(side:String,dt:float,speed:float,direction:Vector3) -> Vector3:
	var phase:=fposmod(gait/TAU+(.0 if side=="l" else .5),1.0)
	var stance:=.59
	var sx:=.155 if side=="l" else -.155
	var d:=direction.normalized()
	if d.length()<.1:d=Vector3(0,0,1)
	var reach:=clampf(speed*.13,.20,.66)
	var home:=Vector3(sx,.108,.045)
	if phase<stance:
		if not foot_plants.has(side):
			foot_plants[side]=to_global(home+d*reach)
		foot_swing[side]=foot_plants[side]
		var planted:Vector3=to_local(foot_plants[side]);planted.y=.108
		if G.flat(planted-home).length()>reach*1.9:
			planted=home-d*reach
			foot_plants[side]=to_global(planted)
		return planted
	foot_plants.erase(side)
	var u:float=(phase-stance)/(1-stance)
	var from:Vector3=to_local(foot_swing.get(side,to_global(home-d*reach)))
	var end:=home+d*reach
	var foot:=from.lerp(end,smoothstep(0,1,u))
	foot.y=.108+sin(u*PI)*(.15+speed*.012)
	return foot

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
			weapon_plants[side]={"start":start,"landing":to_global(Vector3(sx*.155,.108,.32))}
	weapon_last_t=t;weapon_entry_t+=dt
	motion.transform=Transform3D.IDENTITY
	var pose:Dictionary=KnightMotion.sample(id,t)
	var p:=Vector3(0,pose.height,0)
	var body:=Basis(Vector3.FORWARD,float(pose.bank)+recoil.z)*Basis(Vector3.UP,float(pose.twist)+recoil.y)*Basis(Vector3.RIGHT,float(pose.lean)+recoil.x)
	_put("root",Vector3.ZERO,Vector3.UP*.1)
	var spine:=p
	for bone in ["pelvis","spine1","spine2","neck","head"]:
		var flex:=.35 if bone=="pelvis" else (1.0 if bone in ["spine1","spine2"] else .25)
		var bs:=Basis(Vector3.FORWARD,(float(pose.bank)+recoil.z)*flex)*Basis(Vector3.UP,(float(pose.twist)+recoil.y)*flex)*Basis(Vector3.RIGHT,(float(pose.lean)+recoil.x)*flex)
		var end:Vector3=spine+bs*(tails[bone]-heads[bone]);_put(bone,spine,end);spine=end
	for side in ["l","r"]:
		var sx:=1.0 if side=="l" else -1.0
		var hip:Vector3=p+Basis(Vector3.UP,float(pose.twist)*.35)*(heads["thigh_"+side]-heads.pelvis)
		var foot:=Vector3(sx*.155,.108,.05)
		if global_position.y>.18 and id=="jump_attack":
			foot.y+=.30;foot.z=.25 if side=="l" else -.20
		else:
			var plant:Dictionary=weapon_plants[side]
			var at:Vector3=plant.start
			if side==String(pose.lead):
				var f:=clampf(t/(float(m.wind)*.74),0,1)
				at=plant.start.lerp(plant.landing,BeastMoves.smooth_motion(f));at.y+=sin(f*PI)*.075
			var recover:=smoothstep(float(m.hits[1])+.11,float(m.length),t)
			at=at.lerp(to_global(foot),recover);at.y+=sin(recover*PI)*.045
			foot=to_local(at)
		var ankle:=_ik("thigh_","shin_",side,hip,foot,Vector3(sx*.12,.06,1))
		_put("foot_"+side,ankle,ankle+Vector3(0,-.035,.15));feet[side]=ankle
		var shoulder:Vector3=globals.spine2*rest.spine2.affine_inverse()*heads["upper_"+side]
		var hand:=_ik("upper_","fore_",side,shoulder,pose.free if side=="l" else pose.hand,Vector3(sx*.65,-.18,-.65))
		var axis:Vector3=pose.sword if side=="r" else Vector3(0,-1,.15).normalized()
		_put("hand_"+side,hand,hand+axis*lengths["hand_"+side])
	var blend:=smoothstep(0,.12,weapon_entry_t)
	if initialized and blend<1:
		for bone in globals:
			if weapon_from.has(bone):globals[bone]=weapon_from[bone].interpolate_with(globals[bone],blend)
	grip=globals.hand_r.origin
	var sword:Vector3=(globals.hand_r.basis*rest.hand_r.basis.inverse()*(tails.hand_r-heads.hand_r)).normalized()
	var minimum:=clampf((.035-motion.to_global(grip).y)/blade_length,-.99,.99)
	if sword.y<minimum:
		var flat:=Vector3(sword.x,0,sword.z).normalized()
		sword=flat*sqrt(1-minimum*minimum)+Vector3.UP*minimum
		_put("hand_r",grip,grip+sword*lengths.hand_r)
	for side in feet:feet[side]=globals["foot_"+side].origin
	_cloth(dt,p,body)
	_commit(action,dt,sword)

func _beast_contact(id:String,home:Vector3,phase_offset:float,dt:float,speed:float,direction:Vector3,weight:float) -> Vector3:
	# Stance contacts stay in world space. A separate swing brings them forward.
	if weight<.92:
		beast_plants.erase(id);beast_swings.erase(id)
		return home
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
	var xf:=motion.global_transform
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
		point.y+=sin(f*PI)*(.15 if id=="paw" else .12)*unit
		if f>=1:
			beast_plants[id]=step.to;beast_swings.erase(id)
		return xf.affine_inverse()*point
	if not beast_plants.has(id):beast_plants[id]=xf*home
	return xf.affine_inverse()*beast_plants[id]

func _pose_beast(action:String,t:float,dt:float,speed:float,direction:Vector3) -> void:
	motion.transform=Transform3D.IDENTITY
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
	var p:=Vector3(0,target.height,-.15)*unit
	if moving:
		p.y+=absf(sin(gait))*minf(.023,speed*.007)*unit
		p.x+=sin(gait)*.018*unit
	var lean:float=target.lean+recoil.x
	var twist:float=target.twist+sin(clock*1.3)*.012*(1-flight)+recoil.y
	var bank:float=target.bank+recoil.z
	var body:=Basis(Vector3.FORWARD,bank)*Basis(Vector3.UP,twist)*Basis(Vector3.RIGHT,lean)
	var pelvis_bs:=Basis(Vector3.FORWARD,bank*.7)*Basis(Vector3.UP,twist*.35)*Basis(Vector3.RIGHT,lean*.55)
	_put("root",Vector3.ZERO,Vector3.UP*.1*unit)
	var spine:=p
	for bn in ["pelvis","spine1","spine2","neck","head"]:
		var pitch:float=lean
		var turning:float=twist
		if bn=="pelvis":pitch=lean*.55;turning=twist*.35
		elif bn=="spine2":pitch=lean+.06
		elif bn=="neck":pitch=.35+float(target.head_pitch)*.45;turning=twist*.40
		elif bn=="head":pitch=target.head_pitch;turning=twist*.15
		var bs:=Basis(Vector3.FORWARD,bank)*Basis(Vector3.UP,turning)*Basis(Vector3.RIGHT,pitch)
		var end:Vector3=spine+bs*(tails[bn]-heads[bn])
		_put(bn,spine,end);spine=end
	var left:=Vector3(target.paw_x,.122,target.paw_z)*unit
	left.y+=((1-float(target.paw_weight))*.44+flight*.12)*unit
	left.z-=flight*.17*unit
	left=_beast_contact("paw",left,.25,dt,speed if moving else 0.0,direction,float(target.paw_weight)*(1-flight))
	if float(target.paw_weight)>.92 and flight<.08:
		var shoulder:Vector3=globals.spine2*rest.spine2.affine_inverse()*heads.upper_l
		var reach:float=lengths.upper_l+lengths.fore_l-.025
		var horizontal:=G.flat(shoulder-left).length()
		var support_drop:=maxf(0,shoulder.y-left.y-sqrt(maxf(.01,reach*reach-horizontal*horizontal)))
		if support_drop>0:
			p.y-=support_drop
			for bone in globals:
				if bone!="root":globals[bone].origin.y-=support_drop
	var a:float=target.blade_yaw
	var pitch:float=target.blade_pitch
	var sword:=Vector3(sin(a)*cos(pitch),sin(pitch),cos(a)*cos(pitch))
	var right:=Vector3(float(target.hand_x)+sin(a)*.26,target.hand_y,target.hand_reach+cos(a)*.10)*unit
	beast_contacts.clear()
	for side in ["l","r"]:
		var sx:=1.0 if side=="l" else -1.0
		var foot:=Vector3(sx*.24*float(target.spread),.125,target.foot_lz if side=="l" else target.foot_rz)*unit
		if moving:foot.z+=.18*unit
		foot.y+=flight*(.37 if side=="l" else .31)*unit
		foot.z+=flight*(.24 if side=="l" else -.12)*unit
		foot=_beast_contact(side,foot,0 if side=="l" else .5,dt,speed if moving else 0.0,direction,1-flight)
		var hip:Vector3=p+pelvis_bs*(heads["thigh_"+side]-heads.pelvis)
		var ankle:=_ik("thigh_","shin_",side,hip,foot,Vector3(sx*.40,.75,.65))
		_put("foot_"+side,ankle,ankle+Vector3(0,-.035,.15)*unit)
		feet[side]=ankle
		beast_contacts[side]=motion.to_global(ankle)
		var shoulder:Vector3=globals.spine2*rest.spine2.affine_inverse()*heads["upper_"+side]
		var hand_target:Vector3=left if side=="l" else right
		var pole:=Basis(Vector3.UP,twist)*Vector3(sx*.90,-.20,-.65)
		var hand:=_ik("upper_","fore_",side,shoulder,hand_target,pole)
		var hand_axis:=sword if side=="r" else Vector3(.08,-1,.20).normalized()
		if side=="r":
			grip=hand
			# The blade hits the stone at the end of a downward cut, then drags out.
			var minimum:=clampf((.035-motion.to_global(grip).y)/(blade_length*global_basis.get_scale().y),-.995,.995)
			if sword.y<minimum:
				var flat:=Vector3(sword.x,0,sword.z).normalized()
				if flat.length()<.1:flat=Vector3(0,0,1)
				sword=flat*sqrt(1-minimum*minimum)+Vector3.UP*minimum
			hand_axis=sword
		else:beast_contacts.paw=motion.to_global(hand+hand_axis*lengths.hand_l)
		_put("hand_"+side,hand,hand+hand_axis*lengths["hand_"+side])
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
	# Turn into the shoulder roll, then return to the target-facing stance.
	var turn:=smoothstep(0,.12,f)*(1-smoothstep(.79,1,f))
	motion.transform=Transform3D(Basis(Vector3.UP,wrapf(heading,-PI,PI)*turn),Vector3.ZERO)
	var p:=Vector3(.045*sin(f*PI),authored.height,0)
	var pelvis_bs:=Basis(Vector3.FORWARD,bank)*Basis(Vector3.RIGHT,spin+.08)
	var spinal:=p
	var radii:={"pelvis":.17,"spine1":.17,"spine2":.18,"neck":.14,"head":.32}
	for bn in ["pelvis","spine1","spine2","neck","head"]:
		var flex:float={"pelvis":0.0,"spine1":.25,"spine2":.60,"neck":1.20,"head":1.68}[bn]*tuck
		var bs:=Basis(Vector3.FORWARD,bank)*Basis(Vector3.RIGHT,spin+.08+flex)
		var endpoint:Vector3=spinal+bs*(tails[bn]-heads[bn])
		_put(bn,spinal,endpoint)
		spinal=endpoint
	_put("root",Vector3.ZERO,Vector3.UP*.1)
	for side in ["l","r"]:
		var sx:=1.0 if side=="l" else -1.0
		var lead:=1.0 if side=="l" else .84
		var hip:Vector3=p+pelvis_bs*(heads["thigh_"+side]-heads.pelvis)
		var hip_flex:float=-2.05*tuck*lead
		var knee_flex:float=2.65*tuck*(.94 if side=="l" else 1.0)
		var leg_bs:=Basis(Vector3.FORWARD,bank)*Basis(Vector3.RIGHT,spin+hip_flex)
		var shin_bs:=Basis(Vector3.FORWARD,bank)*Basis(Vector3.RIGHT,spin+hip_flex+knee_flex)
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
		var foot_bs:=Basis(Vector3.RIGHT,(spin+hip_flex+knee_flex*.72)*(1-plant))
		_put("foot_"+side,ankle,ankle+foot_bs*Vector3(0,-.035,.15))
		feet[side]=ankle
		var chest:Transform3D=globals.spine2
		var shoulder:Vector3=chest.origin+chest.basis*rest.spine2.basis.inverse()*(heads["upper_"+side]-heads.spine2)
		# The free palm braces the approach; the sword arm stays close to the ribs.
		var local_hand:=Vector3(sx*lerpf(.29,.23,tuck),lerpf(-.24,-.05,tuck),lerpf(.12,.34,tuck))
		var chest_basis:=Basis(Vector3.FORWARD,bank)*Basis(Vector3.RIGHT,spin+.35*tuck)
		var hand_target:Vector3=globals.spine2.origin+chest_basis*local_hand
		if side=="l":
			var brace:=sin(smoothstep(.06,.28,f)*PI)*(1-smoothstep(.28,.36,f))
			hand_target=hand_target.lerp(Vector3(.27,.09,.50),brace*.72)
		var pole:=chest_basis*Vector3(sx*.85,-.35,-.30)
		var hand:=_ik("upper_","fore_",side,shoulder,hand_target,pole)
		var sword_axis:=chest_basis*Vector3(-.24,.12,.96).normalized()
		_put("hand_"+side,hand,hand+(sword_axis if side=="r" else chest_basis*Vector3(0,-1,.15)).normalized()*lengths["hand_"+side])
		if side=="r":grip=hand;blade_dir=sword_axis
	# The shoulder/back and the boots support the roll; the helmet stays clear.
	var min_y:=100.0
	if not contact_probes.is_empty():
		for probe in contact_probes:
			if globals.has(probe.bone):min_y=minf(min_y,(globals[probe.bone]*probe.local).y)
	else:
		for bn in globals:
			if bn=="root":continue
			var rad:float=radii.get(bn,.065 if bn.begins_with("hand") else .09)
			min_y=minf(min_y,globals[bn].origin.y-rad)
	var lift:=ground_min-min_y
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
		_put("hand_r",grip,grip+blade_dir*lengths.hand_r)
	roll_ground_clearance=min_y+lift
	roll_support="push" if f<.17 else ("shoulder" if f<.42 else ("back" if f<.65 else "plant"))
	_cloth(dt,p,pelvis_bs)
	_commit("roll",dt,blade_dir)

func _cloth(dt:float,p:Vector3,body:Basis) -> void:
	if not secondary_motion:return
	var xf:=motion.global_transform
	var inv:=xf.affine_inverse()
	var h:=minf(dt,1.0/30.0)
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
			var next:=current+(current-previous)*exp(-7*h)+(Vector3.DOWN*12+wind)*h*h
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

func blade() -> Array[Vector3]:
	var base:=motion.global_transform*grip
	var tip:=motion.global_transform*(grip+blade_dir*blade_length)
	return [base,tip]

func target_point() -> Vector3:
	if globals.has("spine2"):return motion.global_transform*globals.spine2.origin
	return global_position+Vector3.UP*unit
