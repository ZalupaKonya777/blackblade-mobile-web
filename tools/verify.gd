extends Node
var main:Node
var reports:Array=[]
var failures:=0
var p:PlayerUnit
var b:EclipseBeast

func _check(label:String,ok:bool,detail:Variant="") -> void:
	reports.append({"check":label,"ok":ok,"detail":detail})
	if not ok:failures+=1
	print("VERIFY ","PASS " if ok else "FAIL ",label," ",detail)

func _step(frames:int) -> void:
	for i in frames:await get_tree().physics_frame

func _reset(pos:=Vector3(0,.05,2)) -> void:
	G.freeze=0;G.training=false
	p.reset(pos);p.bot_move=Vector2.ZERO;b.reset(Vector3(0,.05,-5));b.ai_enabled=false;b.state="idle";b.wait=100
	G.fx.reset();G.camera.yaw=0;G.camera.cinematic=false
	await _step(8)

func run(scene:Node) -> void:
	main=scene;main.start(false,true);p=main.player;b=main.boss
	b.ai_enabled=false
	await _step(10)
	_check("source knight has skin",p.rig.skel.get_bone_count()==33,p.rig.skel.get_bone_count())
	_check("mobile boss has body, limb and front-fur skin",b.rig.skel.get_bone_count()==34 and b.rig.ids.has("loin"),b.rig.skel.get_bone_count())
	_check("ground collision",p.is_on_floor(),p.global_position.y)
	for load_id in 3:
		await _reset()
		G.settings.load=load_id
		p.move_dir=Vector3(0,0,-1);p.bot_move=Vector2.ZERO
		var start:=p.global_position;var before:=p.stamina
		p._command("dodge")
		var spent:=before-p.stamina;var inv_frames:=0;var protected:=true
		var frames:=45 if load_id!=2 else 58
		for i in frames:
			await _step(1)
			if p.invulnerable:
				inv_frames+=1
				var old_hp:=p.hp
				p.receive_hit(100,Vector3(0,0,-3))
				protected=protected and p.hp==old_hp
		var distance:=G.flat(p.global_position-start).length()
		var expected:float=[4.10,3.25,2.65][load_id]
		_check("roll cost load %d"%load_id,is_equal_approx(spent,18),spent)
		_check("roll distance load %d"%load_id,absf(distance-expected)<.23,distance)
		_check("roll immunity load %d"%load_id,protected and inv_frames in range(23,29),inv_frames)
	G.settings.load=1
	# Skin-space checks exercise the supplied mesh, not only controller variables.
	await _reset(Vector3(0,.05,0))
	p.set_physics_process(false)
	var auditor=load("res://tools/roll_studio.gd").new();auditor.rig=p.rig
	var helmet_low:=100.0;var blade_low:=100.0;var all_finite:=true
	for frame in 43:
		p.rig.roll_direction=Vector3(0,0,1)
		p.rig.pose("roll",frame/60.0,1.0/60.0,0,Vector3.ZERO)
		var sample:Dictionary=auditor.audit_mesh()
		helmet_low=minf(helmet_low,sample.helmet_min_y)
		blade_low=minf(blade_low,p.rig.blade()[1].y)
		all_finite=all_finite and is_finite(sample.min_y) and sample.max_y<2.7
	_check("roll helmet clears ground across all 43 poses",helmet_low>-.025,helmet_low)
	_check("carried sword clears ground throughout roll",blade_low>=.025,blade_low)
	_check("full roll skin stays finite",all_finite)
	auditor.free();p.set_physics_process(true)
	await _reset();p.move_dir=Vector3(0,0,-1);p._command("dodge")
	var planted_at:=Vector3.INF;var foot_slide:=0.0;var low_capsule:=false
	for i in 43:
		await _step(1)
		if p.state=="roll":
			var phase:float=p.t/p.roll_duration
			if phase>.25 and phase<.65:low_capsule=low_capsule or p.body_capsule.height<.85
			if phase>.78 and phase<.89:
				var foot:Vector3=p.rig.motion.to_global(p.rig.feet.l)
				if planted_at==Vector3.INF:planted_at=foot
				foot_slide=maxf(foot_slide,G.flat(foot-planted_at).length())
	_check("roll collision capsule follows low body",low_capsule)
	_check("recovery boot stays planted in world space",foot_slide<.03,foot_slide)
	_check("shoulder and boot contact fire once",p.roll_events.size()==2,p.roll_events.keys())
	for v in [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(1,-1),Vector2(0,-1),Vector2(-1,-1),Vector2(-1,0),Vector2(-1,1)]:
		await _reset();p.target=b
		var want:=Vector3(v.x,0,-v.y).normalized();p.move_dir=want
		var from:=p.global_position;p._command("dodge");await _step(44)
		var actual:=G.flat(p.global_position-from).normalized()
		_check("lock-on roll direction "+str(v),actual.dot(want)>.98,actual.dot(want))
	await _reset()
	await _step(5)
	b.rig.skel.force_update_all_bone_transforms()
	var hand_id:int=b.rig.ids.hand_l
	var pose:Transform3D=b.rig.skel.get_bone_global_pose(hand_id)
	var claw:Vector3=b.rig.skel.global_transform*(pose*b.rig.rest.hand_l.affine_inverse()*b.rig.support_socket)
	_check("free claw contacts the floor",absf(claw.y)<.14,claw.y)
	await _reset();p.bot_move=Vector2(0,1)
	var press:=InputEventAction.new();press.action="dodge";press.pressed=true
	Input.parse_input_event(press);await _step(4)
	_check("dodge waits for button release",p.state in ["idle","move"],p.state)
	var release:=InputEventAction.new();release.action="dodge";release.pressed=false
	Input.parse_input_event(release);await _step(3)
	_check("tap release starts a roll",p.state=="roll",p.state)
	await _reset();p.bot_move=Vector2(0,1)
	Input.parse_input_event(press);await _step(21)
	_check("held dodge becomes sprint",p.sprinting and p.state in ["idle","move"],p.state)
	Input.parse_input_event(release);await _step(2)
	_check("sprint release does not roll",p.state in ["idle","move"],p.state)
	await _reset();p.move_dir=Vector3.ZERO;p._command("dodge")
	var inv:=false
	for i in 34:await _step(1);inv=inv or p.invulnerable
	_check("backstep has no invulnerability",not inv)
	await _reset();p.stamina=0
	_check("exhausted dodge is rejected",not p._command("dodge"))
	await _reset();p._attack("light");await _step(17);p.bot_move=Vector2(1,0);p.move_dir=Vector3(1,0,0);p._queue("dodge");await _step(8)
	_check("attack cannot cancel during active swing",p.state=="attack",p.state)
	await _step(16)
	_check("buffered roll starts at recovery",p.state=="roll",p.state)
	await _reset();p.bot_move=Vector2.ZERO;p.move_dir=Vector3(0,0,-1);p._command("dodge");await _step(36);p._queue("light");await _step(6)
	_check("roll followup attack",p.state=="attack" and p.action=="roll_attack",p.action)
	await _reset(Vector3(0,.05,0));b.global_position=Vector3(0,.05,-2.35);b.yaw=0;p.target=b
	await _step(12)
	var hp0:=b.hp;p._attack("light");await _step(55)
	_check("swept player blade damages boss",b.hp<hp0,hp0-b.hp)
	await _reset(Vector3(0,.05,0));b.global_position=Vector3(0,.05,-3.0);b.yaw=0
	await _step(10);hp0=p.hp;b.start_move("overhead");await _step(135)
	_check("boss blade damages player",p.hp<hp0,hp0-p.hp)
	await _reset();p.hp=500;p._command("heal");await _step(78)
	_check("flask heals at authored time",p.hp>1050 and p.flasks==4,[p.hp,p.flasks])
	await _reset();p.hp=500;p._command("heal");await _step(19);p.receive_hit(100,p.global_position+Vector3(0,0,-2));await _step(80)
	_check("interrupted flask does not heal",p.hp<500 and p.flasks==4,[p.hp,p.flasks])
	await _reset();b.take_damage(4100,0,b.global_position,"test");await _step(200)
	_check("phase two at half health",b.phase==2 and b.state!="transition",[b.phase,b.state])
	await _reset();p.yaw=PI;p._command("parry");await _step(10)
	p.receive_hit(400,p.global_position+Vector3(0,0,-2),80,true,true)
	_check("timed golden blade parry staggers",b.state=="stagger" and p.hp==PlayerUnit.MAX_HP,b.state)
	await _reset();b.take_damage(1,EclipseBeast.STANCE+1,b.global_position,"test");await _step(30)
	_check("stance break opens critical",b.critical_ready(),b.state)
	await _reset(Vector3(0,.05,0));b.global_position=Vector3(0,.05,-2.5);b.take_damage(1,EclipseBeast.STANCE+1,b.global_position,"test");await _step(28)
	var before_critical:=b.hp;p._command("light");await _step(65)
	_check("front critical deals its timed damage",b.hp<before_critical-1200,before_critical-b.hp)
	await _reset();p.receive_hit(200,p.global_position+Vector3(0,0,-2),60,true);await _step(3)
	_check("destined death reduces max HP",p.hp_cap<PlayerUnit.MAX_HP and p.dd_timer>0,p.hp_cap)
	await _reset();p.bot_move=Vector2(0,1);await _step(10)
	var pause_key:=InputEventKey.new();pause_key.physical_keycode=KEY_ESCAPE;pause_key.pressed=true
	Input.parse_input_event(pause_key)
	for i in 2:await get_tree().process_frame
	_check("Escape opens pause menu",main.ui.pause_root.visible and get_tree().paused)
	var at:=p.global_position
	for i in 10:await get_tree().process_frame
	_check("pause freezes combat",p.global_position.is_equal_approx(at))
	main.ui.close_pause();p.bot_move=Vector2.ZERO
	G.fx.projectile(Vector3(0,2,-5),Vector3(0,1,0),100,10,0);p.dd_timer=6;main.start(false,true);b.ai_enabled=false
	_check("retry clears transient fight state",G.fx.projectiles.is_empty() and p.dd_timer==0 and p.hp==PlayerUnit.MAX_HP and b.phase==1)
	b.state="idle";b.hp=1;b.take_damage(500,0,b.global_position,"test");await _step(80)
	_check("victory result is reachable",main.phase=="won" and main.ui.mode=="result",main.phase)
	for move_name in EclipseBeast.MOVES:
		await _reset(Vector3(0,.05,0))
		G.training=true
		b.phase=2
		var gap:=9.0 if move_name in ["lunge","leap","air_blades"] else 3.0
		b.global_position=Vector3(0,.05,-gap);b.start_move(move_name)
		await _step(int(EclipseBeast.MOVES[move_name].length*60)+12)
		_check("complete boss move "+move_name,b.global_position.is_finite() and b.global_position.y<.25 and p.global_position.is_finite(),[b.state,b.global_position.y])
	var f:=FileAccess.open("res://artifacts/verification.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures":failures,"checks":reports},"  "));f.close()
	print("VERIFICATION COMPLETE: ",reports.size()," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)
