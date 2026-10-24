extends "res://tools/balance_lab.gd"
## Real controller, collider and skeleton regressions for the revised encounter.
var pose_samples:Array=[]
func vec(v:Vector3) -> Array:return [v.x,v.y,v.z]
func xf(t:Transform3D) -> Array:return [vec(t.basis.x),vec(t.basis.y),vec(t.basis.z),vec(t.origin)]
func save_pose(id:String) -> void:
	var bones:={}
	for bone in b.rig.globals:bones[bone]=xf(b.rig.globals[bone])
	var hurt:=[]
	for s in b.hurt_segments():hurt.append([vec(s[0]),vec(s[1]),s[2]])
	pose_samples.append({"id":id,"bones":bones,"motion_transform":xf(b.rig.motion.global_transform),"hurt_segments":hurt})

func run() -> void:
	seed(48193)
	p.rig.secondary_motion=true;b.rig.secondary_motion=true
	await reset(4)
	check("actors physically collide on their actual collision layers",bool(p.collision_mask&b.collision_layer) and bool(b.collision_mask&p.collision_layer))
	var gaps:=[];var blocked:=true
	for i in 8:
		await reset(4)
		var toward:=Vector3(sin(i*TAU/8),0,cos(i*TAU/8))
		p.global_position=toward*4+Vector3.UP*.05;p.target=null
		p.bot_move=Vector2(-toward.x,toward.z)
		await step(85)
		var gap:float=G.flat(p.global_position-b.global_position).length()
		gaps.append(gap);blocked=blocked and gap>1.0 and gap<1.8
	check("walking into the beast stops outside its core from eight directions",blocked,gaps)
	await reset(8);p.bot_move=Vector2.ZERO;b.start_move("lunge")
	var smallest:=100.0
	for i in 90:
		await step(1);smallest=minf(smallest,G.flat(p.global_position-b.global_position).length())
	check("boss rush cannot pass through the player",smallest>1.05,smallest)
	await reset(3);b.set_physics_process(false);p.set_physics_process(false)
	for pose in [["idle",0.0],["sweep",.75],["combo",1.46],["overhead",1.10],["backhand",.55],["paw_strike",.54],["evade_cut",.66],["lunge",.78],["leap",1.51],["air_blades",1.44],["spin",1.31],["death_storm",1.27]]:
		b.rig.initialized=false
		for i in 12:b.rig.pose(pose[0],pose[1],1.0/60,0,Vector3.ZERO)
		save_pose(pose[0])
	check("damage shapes follow torso head and all four limbs",b.hurt_segments().size()==13)
	var contacts:=[]
	for id in KnightMoves.MOVES:
		await reset(2.6)
		var which:String=id;var variant:=0
		if id.begins_with("light"):which="light";variant=int(id.trim_prefix("light"))-1
		if id=="heavy2":which="heavy";variant=1
		p._attack(which,variant)
		var max_damage:=0.0;var min_gap:=100.0
		for frame in int(ceil(float(KnightMoves.MOVES[id].length)*60))+5:
			await step(1)
			max_damage=maxf(max_damage,EclipseBeast.MAX_HP-b.hp)
			min_gap=minf(min_gap,G.flat(p.global_position-b.global_position).length())
		contacts.append({"id":id,"damage":max_damage,"min_gap":min_gap})
		check("visible sword reaches body without entering mesh: "+id,max_damage>0 and min_gap>1.1,contacts.back())
	await reset(8);p.target=null;p.stamina=1000;p._attack("light")
	var ids:=["light1"];var starts:=[0.0];var clock:=0.0;var previous:="light1"
	for frame in 240:
		p._queue("light");await step(1);clock+=1.0/60
		if p.state=="attack":
			var id:String=KnightMoves.key(p.action,p.combo)
			if id!=previous:ids.append(id);starts.append(clock);previous=id
		if ids.size()>=5:break
	check("light input gives four distinct attacks and a committed finisher",ids.slice(0,4)==["light1","light2","light3","light4"] and starts.size()>=5 and starts[4]-starts[3]>1.15,{"ids":ids,"starts":starts})
	await reset(8);p.target=null;p.stamina=1000;p._attack("heavy")
	ids=["heavy"];starts=[0.0];clock=0;previous="heavy"
	for frame in 210:
		p._queue("heavy");await step(1);clock+=1.0/60
		if p.state=="attack":
			var id:String=KnightMoves.key(p.action,p.combo)
			if id!=previous:ids.append(id);starts.append(clock);previous=id
		if ids.size()>=3:break
	check("heavy input links an overhead and a separate two-handed return cut",ids.slice(0,2)==["heavy","heavy2"] and starts.size()>=3 and starts[2]-starts[1]>1.30,{"ids":ids,"starts":starts})
	await reset(8);p.sprinting=true;p.velocity=Vector3(0,0,-6);p._command("light")
	check("light from a real sprint selects the running thrust",p.action=="running_attack",p.action)
	await reset(8);p._begin("backstep");p.t=.35;p._queue("light");await step(1)
	check("light out of backstep selects its rising return",p.action=="backstep_attack",p.action)
	await reset(3);b.ai_enabled=true;b.state="recover";b.recover_from="sweep";b.recovery_duration=.24;b.followup="backhand";b.pressure=0;b.t=0
	await step(9)
	check("a follow-up starts from the outgoing pose without a neutral-state pause",b.state=="attack" and b.attack=="backhand" and b.pressure==1,[b.state,b.attack,b.pressure])
	check("follow-up budget prevents an endless attack chain",not b._can_follow("sweep"))
	var windows:={}
	for id in ["sweep","overhead"]:
		await reset(8);b.start_move(id)
		var end:float=BeastMoves.ATTACKS[id].hits.back()[1];clock=0
		for frame in 210:
			await step(1);clock+=1.0/60
			if b.state=="idle":break
		windows[id]=clock-end
	check("quick attack no longer has two stacked recoveries",windows.sweep<.65,windows)
	check("a missed heavy slam still earns a larger punish window",windows.overhead>windows.sweep+.35 and windows.overhead>.90,windows)
	var selections:={}
	for phase in [1,2]:
		await reset(6);G.training=true;b.ai_enabled=true;b.phase=phase;b.wait=0
		var seen:={};var count:=0;var last:="";var max_chain:=0
		for frame in 3000:
			if frame%420==0:
				var radius:float=[3.0,7.5,10.0,2.6,5.8,3.2,8.2][(frame/420)%7]
				p.global_position=b.global_position+Vector3(sin(b.yaw),0,cos(b.yaw))*radius;p.global_position.y=.05
			await step(1);max_chain=maxi(max_chain,b.pressure)
			if b.state=="attack" and b.attack!=last:seen[b.attack]=int(seen.get(b.attack,0))+1;count+=1;last=b.attack
			elif b.state!="attack":last=""
		selections[phase]={"moves":seen,"attacks":count,"max_followups":max_chain}
		check("phase %d varies its real AI choices without infinite pressure"%phase,seen.size()>=(6 if phase==1 else 7) and count>=16 and max_chain<=1,selections[phase])
	await reset(10);p.set_physics_process(false);b.set_physics_process(false)
	var auditor=load("res://tools/roll_studio.gd").new();auditor.rig=p.rig
	for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.BACK,Vector3.FORWARD,Vector3(1,0,1).normalized(),Vector3(-1,0,1).normalized(),Vector3(1,0,-1).normalized(),Vector3(-1,0,-1).normalized()]:
		p.rig.initialized=false;p.rig.roll_locked=true;p.rig.roll_direction=direction
		var bad:=false;var low:=100.0;var helmet:=100.0;var max_jump:=0.0;var previous_head:=Vector3.INF
		for frame in 43:
			p.rig.pose("roll",frame/60.0,1.0/60,0,Vector3.ZERO)
			var head:Vector3=p.rig.motion.to_global(p.rig.globals.head.origin)
			if previous_head!=Vector3.INF:max_jump=maxf(max_jump,head.distance_to(previous_head))
			previous_head=head;bad=bad or not head.is_finite()
			if frame in [8,17,25,34]:
				var mesh:Dictionary=auditor.audit_mesh();low=minf(low,mesh.min_y);helmet=minf(helmet,mesh.helmet_min_y)
			if frame==12:
				var facing:float=absf(p.rig.motion.rotation.y)
				var delta:Basis=p.rig.globals.pelvis.basis*p.rig.rest.pelvis.basis.inverse()
				var lean:float=(delta*Vector3.UP).dot(direction)
				check("locked roll tumbles along travel while keeping target-facing yaw "+str(direction),facing<.01 and lean>.70,{"yaw":facing,"travel_tilt":lean})
		check("locked roll keeps actual skin and helmet above stone "+str(direction),not bad and low>.0 and helmet>.02 and max_jump<.65,{"skin_min_y":low,"helmet_min_y":helmet,"max_head_step":max_jump})
	auditor.free()
	await reset(10);p.yaw=PI;p.target=b;p.move_dir=Vector3.RIGHT;p.bot_move=Vector2.RIGHT
	var origin:Vector3=p.global_position;p._command("dodge")
	await step(42)
	check("locked lateral roll keeps established distance duration and facing",absf(p.global_position.distance_to(origin)-3.25)<.06 and absf(wrapf(p.yaw-PI,-PI,PI))<.01,[p.global_position-origin,p.yaw,p.state])
	var out:=FileAccess.open("res://artifacts/encounter_pose_samples.json",FileAccess.WRITE);out.store_string(JSON.stringify(pose_samples));out.close()
	var report:={"checks":checks,"failures":failures,"weapon_contacts":contacts,"AI":selections,"punish_windows":windows}
	out=FileAccess.open("res://artifacts/encounter_verification.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	print("ENCOUNTER COMPLETE ",checks.size()," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)
