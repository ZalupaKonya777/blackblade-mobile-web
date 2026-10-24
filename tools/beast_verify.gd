extends Node
## Rehearses mesh motion and real combat states at the shipped 60 Hz tick rate.
var main:Node
var p:PlayerUnit
var b:EclipseBeast
var checks:Array=[]
var failures:=0

func check(label:String,ok:bool,detail:Variant="") -> void:
	checks.append({"check":label,"ok":ok,"detail":detail})
	if not ok:failures+=1
	print("BEAST VERIFY ","PASS " if ok else "FAIL ",label," ",detail)

func step(frames:int) -> void:
	for i in frames:await get_tree().physics_frame

func reset(gap:=3.0) -> void:
	G.freeze=0;G.training=false;G.fx.reset()
	p.set_physics_process(true);b.set_physics_process(true)
	p.reset(Vector3(0,.05,gap));p.controls_enabled=false;p.bot_move=Vector2.ZERO;p.target=null
	b.reset(Vector3(0,.05,0));b.ai_enabled=false;b.state="idle";b.wait=100
	await step(6)

func run(scene:Node) -> void:
	main=scene;main.start(false,true);p=main.player;b=main.boss
	await reset()
	# Inspect the actual skeleton/weapon transforms throughout every authored move.
	b.set_physics_process(false);p.set_physics_process(false)
	for id in EclipseBeast.MOVES:
		b.rig.initialized=false
		var last:=Vector3.INF;var max_jump:=0.0;var low:=100.0;var finite:=true;var wrist_error:=0.0
		var travels:Array=[];var last_contact:=Vector3.INF
		for h in EclipseBeast.MOVES[id].hits:travels.append(0.0)
		for frame in int(ceil(float(EclipseBeast.MOVES[id].length)*60))+1:
			var time:=frame/60.0
			b.rig.pose(id,time,1.0/60.0,0,Vector3.ZERO)
			b.rig.skel.force_update_all_bone_transforms()
			var blade:=b.rig.blade()
			var contact:Vector3=b.rig.motion.to_global(b.rig.globals.hand_l.origin) if EclipseBeast.MOVES[id].get("hit_source","")=="paw" else blade[1]
			finite=finite and blade[0].is_finite() and blade[1].is_finite()
			low=minf(low,blade[1].y)
			if last!=Vector3.INF:
				var distance:float=blade[1].distance_to(last);max_jump=maxf(max_jump,distance)
				for i in travels.size():
					var h:Array=EclipseBeast.MOVES[id].hits[i]
					if time>=h[0] and time<h[1] and last_contact!=Vector3.INF:travels[i]+=contact.distance_to(last_contact)
			last=blade[1]
			last_contact=contact
			var wrist:Vector3=b.rig.skel.global_transform*b.rig.skel.get_bone_global_pose(b.rig.ids.hand_r)*b.rig.rest.hand_r.affine_inverse()*b.rig.right_socket
			wrist_error=maxf(wrist_error,wrist.distance_to(b.rig.weapon.to_global(b.rig.source_grip)))
		check(id+" continuous full-body motion",finite and max_jump<1.35,{"max_tip_step":max_jump,"tip_min_y":low})
		check(id+" sword stays attached inside animated palm",wrist_error<.005,wrist_error)
		if id!="lunge":
			for i in travels.size():check(id+" active strike %d follows its actual limb or blade"%i,float(travels[i])>.55,travels[i])
	var auditor=load("res://tools/roll_studio.gd").new();auditor.rig=b.rig
	for sample in [["idle",0.0],["sweep",.52],["combo",1.46],["overhead",1.18],["leap",1.60],["spin",1.31],["death_storm",1.28],["dead",2.0]]:
		b.rig.initialized=false
		for i in 8:b.rig.pose(sample[0],sample[1],1.0/60.0,0,Vector3.ZERO)
		var mesh:Dictionary=auditor.audit_mesh()
		check("skinned cloth stays above floor in "+sample[0],float(mesh.cloth_min_y)>-.035,mesh.cloth_min_y)
		check("deformed body stays finite in "+sample[0],is_finite(mesh.min_y) and float(mesh.min_y)>-.085 and float(mesh.max_y)<4.2,mesh.min_y)
	auditor.free()
	await reset()
	# Turning remains continuous on entry and stops when the attack commits.
	b.yaw=PI;p.global_position=Vector3(0,.05,3);b.start_move("sweep")
	check("attack entry does not snap facing",is_equal_approx(b.yaw,PI),b.yaw)
	await reset();b.start_move("combo");await step(30)
	var committed:=b.yaw;p.global_position=Vector3(-3,.05,-3)
	await step(105)
	check("committed combination does not home behind a roll",absf(wrapf(b.yaw-committed,-PI,PI))<.001,b.yaw)
	await reset();b.start_move("overhead");await step(105)
	var at:=b.global_position;b.ai_enabled=true
	await step(24)
	check("heavy attack has a stationary punish window",b.state=="recover" and b.global_position.distance_to(at)<.02,[b.state,b.global_position.distance_to(at)])
	await reset();var hp0:=p.hp;b.start_move("overhead");await step(87)
	check("central overhead blade actually hits its visible path",p.hp<hp0,hp0-p.hp)
	await reset(9);b.start_move("lunge");await step(39)
	at=b.rig.blade()[1];await step(17)
	check("pouncing thrust carries the blade through its hit window",G.flat(b.rig.blade()[1]-at).length()>2,G.flat(b.rig.blade()[1]-at).length())
	await step(20)
	check("lunge brakes before its recovery",b.state=="recover" and G.flat(b.velocity).length()<.02,[b.state,b.velocity])
	await reset(10);b.start_move("leap")
	var peak:=0.0;var max_rise:=0.0;var previous:=b.global_position.y
	for i in 170:
		await step(1)
		peak=maxf(peak,b.global_position.y);max_rise=maxf(max_rise,b.global_position.y-previous);previous=b.global_position.y
	check("leap takes off and lands through physics",peak>3 and b.global_position.y<.15 and max_rise<.2,[peak,b.global_position.y,max_rise])
	check("leap creates one landing wave",G.fx.combat_stats.waves==1,G.fx.combat_stats)
	await reset(10);b.start_move("leap");await step(57);b._stagger()
	check("airborne posture break cannot open a floating critical",b.state=="fall" and not b.critical_ready(),[b.state,b.global_position.y])
	await step(61)
	check("interrupted beast lands before opening critical",b.global_position.y<.15 and b.critical_ready(),[b.state,b.global_position.y,b.t])
	await reset(10);b.start_move("leap");await step(48);b.take_damage(4100,0,b.global_position,"test")
	check("phase change waits for airborne attack to finish",b.phase==1 and b.state=="attack" and b.transition_pending)
	await step(285)
	check("phase change begins safely after landing",b.phase==2 and b.global_position.y<.15,[b.phase,b.state,b.global_position.y])
	await reset(10);b.phase=2;b.start_move("air_blades");await step(163)
	check("air combo releases exactly three blades",G.fx.combat_stats.projectiles==3,G.fx.combat_stats)
	check("each projectile has an anticipation aim snapshot",b.shot_aims.size()==3,b.shot_aims.size())
	await reset();b.phase=2;b.start_move("death_storm");await step(175)
	check("death storm creates four separate expanding waves",G.fx.combat_stats.waves==4,G.fx.combat_stats)
	await reset();hp0=p.hp
	G.fx.shockwave(Vector3.ZERO,4.5,100,false,.70)
	check("wave does not damage the entire disk on creation",p.hp==hp0)
	await step(12)
	check("wave only damages after reaching the player",p.hp==hp0,p.hp)
	await step(35)
	check("expanding wave hits once on crossing",p.hp==hp0-100 and G.fx.combat_stats.wave_contacts==1,[p.hp,G.fx.combat_stats])
	await reset();hp0=p.hp;p.set_physics_process(false);p.invulnerable=true
	G.fx.shockwave(Vector3.ZERO,4.5,100,false,.70);await step(34);p.invulnerable=false;await step(12)
	check("rolled wave cannot hit later as immunity ends",p.hp==hp0 and G.fx.combat_stats.wave_contacts==1,[p.hp,G.fx.combat_stats])
	await reset();hp0=p.hp;p.set_physics_process(false);p.global_position.y=1.0
	G.fx.shockwave(Vector3.ZERO,4.5,100,false,.70);await step(34);p.global_position.y=.05;await step(12)
	check("jump clears a ground wave without a late hit",p.hp==hp0 and G.fx.combat_stats.wave_contacts==1,[p.hp,G.fx.combat_stats])
	await reset();b.phase=1
	for id in EclipseBeast.MOVES:b.cooldowns[id]=10
	check("AI respects move cooldowns",b._choose(3)=="")
	b.cooldowns.clear();var phase_ok:=true
	for i in 80:phase_ok=phase_ok and not b._choose(3) in ["spin","death_storm","air_blades"]
	check("phase one keeps phase two moves locked",phase_ok)
	var wall:=StaticBody3D.new();wall.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.8,3,.5);shape.shape=box;wall.add_child(shape);main.add_child(wall);wall.position=Vector3(0,1.5,1.5)
	await step(2)
	check("AI rejects attacks through a pillar",b._choose(3)=="")
	var avoidance:=b._steer(Vector3(0,0,1))
	check("approach steers around a blocked route",absf(avoidance.x)>.2,avoidance)
	wall.queue_free();await step(2)
	await reset();b.rig.initialized=false;b.rig.pose("idle",0,1.0/60.0,0,Vector3.ZERO)
	var paw:Vector3=b.rig.beast_contacts.paw;var slide:=0.0
	for i in 40:
		b.rig.pose("idle",i/60.0,1.0/60.0,0,Vector3.ZERO)
		slide=maxf(slide,b.rig.beast_contacts.paw.distance_to(paw))
	check("free support paw stays planted while breathing",slide<.025,[slide,paw.y])
	G.fx.shockwave(Vector3.ZERO,4,100);G.fx.projectile(Vector3.UP*3,Vector3.ZERO,100,10,0);b.shot_aims[0]=Vector3.ONE;b.followup="lunge"
	main.start(false,true);b.ai_enabled=false
	check("retry clears boss waves, aim and follow-up state",G.fx.waves.is_empty() and G.fx.projectiles.is_empty() and b.shot_aims.is_empty() and b.followup=="")
	var file:=FileAccess.open("res://artifacts/beast_verification.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"checks":checks},"  "));file.close()
	print("BEAST VERIFICATION COMPLETE: ",checks.size()," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)
