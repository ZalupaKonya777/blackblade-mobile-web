extends Node3D
## Real controller/IK/hit tests on a plain collision floor. Bots are timing probes,
## not estimates of human win rates. Production skin and cloth stay enabled.
var p
var b
var fx
var checks:Array=[]
var failures:=0
var sim_running:=false
var sim_style:=""
var sim_clock:=0.0
var sim_next:=0.0
var want_charge:=false
var sim_results:Array=[]
var transitions:Array=[]
var last_combo:=-1

class LabCamera extends Node3D:
	var yaw:=0.0
	func shake(_a:float) -> void:pass
	func landing(_a:float) -> void:pass
	func hit_recoil(_a:Vector3,_b:float) -> void:pass

func _ready() -> void:
	process_physics_priority=-10
	G.playing=true;G.training=false;G.settings.load=1
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(100,.1,100);shape.shape=box;shape.position.y=-.05;floor_body.add_child(shape);add_child(floor_body)
	fx=load("res://scripts/fx.gd").new();add_child(fx)
	p=PlayerUnit.new();p.position=Vector3(0,.05,2.5);add_child(p)
	b=EclipseBeast.new();b.position=Vector3(0,.05,0);add_child(b)
	G.camera=LabCamera.new();add_child(G.camera)
	for rig in [p.rig,b.rig]:
		if "secondary_motion" in rig:rig.secondary_motion=true
		rig.model.visible=false;rig.weapon.visible=false
	b.ai_enabled=false;b.state="idle";b.wait=100
	run.call_deferred()

func step(frames:int) -> void:
	for i in frames:await get_tree().physics_frame
func reset(gap:=2.5) -> void:
	sim_running=false;G.freeze=0;G.training=false
	Input.action_release("sprint");p.set_physics_process(true);b.set_physics_process(true)
	p.reset(Vector3(0,.05,gap));p.controls_enabled=true;p.bot_move=Vector2.ZERO;p.target=b
	b.reset(Vector3(0,.05,0));b.ai_enabled=false;b.state="idle";b.wait=100
	fx.reset();G.camera.yaw=0
	await step(6)
func check(label:String,ok:bool,detail:Variant="") -> void:
	checks.append({"check":label,"ok":ok,"detail":detail})
	if not ok:failures+=1
	print("BALANCE ","PASS " if ok else "FAIL ",label," ",detail)

func run() -> void:
	if not "--bots-only" in OS.get_cmdline_user_args():await verify()
	if "--bots" in OS.get_cmdline_user_args() or "--bots-only" in OS.get_cmdline_user_args():
		for style in ["greedy","measured"]:await simulate(style,77123,150.0)
	var report:={"failures":failures,"checks":checks,"simulations":sim_results,"note":"Automated timing probes use the real player/boss controllers; they do not predict human win rates."}
	var output:="balance_baseline.json" if "--baseline" in OS.get_cmdline_user_args() else ("balance_simulation.json" if "--bots-only" in OS.get_cmdline_user_args() else "balance_verification.json")
	var file:=FileAccess.open("res://artifacts/"+output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("BALANCE COMPLETE ",checks.size()," checks, ",failures," failures; ",sim_results)
	get_tree().quit(1 if failures else 0)

func verify() -> void:
	await reset();p.stamina=17.9;p.move_dir=Vector3.RIGHT
	check("roll requires its full stamina reserve",not p._command("dodge") and p.state=="idle" and is_equal_approx(p.stamina,17.9))
	p.stamina=19.9
	check("light attack cannot start on one remaining point",not p._command("light") and p.state=="idle")
	p.stamina=33.9
	check("heavy attack requires its full cost",not p._command("heavy"))
	await reset(10);p.target=null;p.bot_move=Vector2(1,0)
	await step(1)
	check("armoured locomotion accelerates into its speed",G.flat(p.velocity).length()<1.0,p.velocity)
	await step(25);var speed:float=G.flat(p.velocity).length();p.bot_move=Vector2.ZERO;var at:Vector3=p.global_position
	await step(16)
	check("locomotion reaches tuned run speed",absf(speed-4)<.1,speed)
	check("release brakes with a short grounded stop",G.flat(p.velocity).length()<.05 and G.flat(p.global_position-at).length()>.15 and G.flat(p.global_position-at).length()<.55,p.global_position-at)
	await reset(8);p.target=null;p._attack("light")
	var starts:Array=[0.0];var previous:=0;var clock:=0.0
	for frame in 240:
		p._queue("light");await step(1);clock+=1.0/60
		if p.state=="attack" and p.combo!=previous:starts.append(clock);previous=p.combo
		if starts.size()>=5:break
	check("four-hit chain includes a committed finisher",starts.size()>=5 and float(starts[1])>=.64 and float(starts[2])-float(starts[1])>=.69 and float(starts[4])-float(starts[3])>=1.18,starts)
	await reset(8);p.target=null;p._attack("heavy");p.heavy_held=true
	await step(38);at=p.global_position;var held:float=p.t
	await step(20)
	check("holding charge does not repeat forward root motion",p.global_position.distance_to(at)<.015 and absf(p.t-held)<.02,p.global_position.distance_to(at))
	await step(14);p.heavy_held=false
	check("full charge spends its extra stamina once",p.charged and is_equal_approx(p.stamina,74),[p.charged,p.stamina])
	await reset(2.25);p._attack("heavy");p.heavy_held=true;await step(70);p.heavy_held=false;await step(25)
	check("charged blade applies one 610-damage contact",is_equal_approx(b.hp,EclipseBeast.MAX_HP-610),EclipseBeast.MAX_HP-b.hp)
	await reset(8);p.target=null;p._attack("light");await step(17)
	var heading:float=p.yaw;p.bot_move=Vector2(0,-1);await step(12)
	check("released player swing cannot turn behind itself",absf(wrapf(p.yaw-heading,-PI,PI))<.001,[heading,p.yaw])
	await reset(8);p.receive_hit(100,b.global_position,72);var after:float=p.hp;p.receive_hit(100,b.global_position,72)
	check("overlapping contacts do not double damage in one frame",is_equal_approx(p.hp,after),p.hp)
	await step(18);p.receive_hit(100,b.global_position,72)
	check("damage protection expires for a later distinct hit",is_equal_approx(p.hp,1100),p.hp)
	await reset(8);at=p.global_position;p.receive_hit(340,b.global_position,72)
	await step(12)
	check("a received strike transfers a small grounded impulse",p.global_position.distance_to(at)>.12 and p.global_position.distance_to(at)<.6,p.global_position.distance_to(at))
	p.move_dir=Vector3.RIGHT;p.bot_move=Vector2(1,0);p._queue("dodge");await step(11)
	check("hurt recovery allows a timed escape before the next hit",p.state=="roll",[p.state,p.t])
	await reset(8);p.set_physics_process(false);p.guarding=true;p.yaw=PI;p.receive_hit(340,b.global_position,72)
	check("braced block reduces damage and consumes stance stamina",is_equal_approx(p.hp,1232) and is_equal_approx(p.stamina,48),[p.hp,p.stamina])
	p._command("heavy")
	check("successful block offers counter plus one roll reserve",p.action=="counter" and is_equal_approx(p.stamina,20),[p.action,p.stamina])
	await reset(8);p.set_physics_process(false);p.guarding=true;p.stamina=40;p.receive_hit(340,b.global_position,72)
	check("broken guard has a longer committed recovery",p.state=="hurt" and p.hurt_cancel>.8,[p.state,p.hurt_cancel])
	await reset(8);p.set_physics_process(false);p._attack("heavy");p.charged=true;p.t=.70;p.receive_hit(100,b.global_position,72)
	check("charged release absorbs light stagger while taking damage",p.state=="attack" and p.hp==1200,p.state)
	p.damage_grace=0;p.receive_hit(100,b.global_position,108)
	check("a heavy boss impact breaks that limited armour",p.state=="hurt",p.state)
	await reset(8);p.hp=500;p._command("heal");await step(47)
	check("flask commits before healing and consumes one of five",p.hp==500 and p.flasks==4,[p.hp,p.flasks])
	await step(7)
	check("flask restores the tuned 560 HP",p.hp==1060,p.hp)
	await reset(8);b.take_damage(1,56,b.global_position,"test");await step(180)
	check("stance damage persists through a short attack opportunity",b.posture>55,b.posture)
	b.take_damage(1,56,b.global_position,"test")
	check("two close charged stance hits can earn a critical",b.state=="stagger",b.state)
	await reset(8);b.take_damage(1,56,b.global_position,"test");await step(270)
	check("long disengagement lets boss stance recover",b.posture<46,b.posture)
	await reset(8);b.phase=2;b.pressure=1;b.followup="lunge"
	check("phase-two follow-ups cannot become an endless chain",not b._can_follow("lunge"))
	await reset(8);p.receive_hit(100,b.global_position,72,true)
	check("curse clamps current health to its reduced cap",p.hp<=p.hp_cap and p.dd_timer<=6.0,[p.hp,p.hp_cap,p.dd_timer])
	await reset(8);fx.projectile(Vector3(0,2,4),p.global_position,100,10,0);fx.shockwave(p.global_position,4,100)
	b.hp=1;b.take_damage(2,0,b.global_position,"test");await step(3)
	check("boss death clears damaging remnants",fx.projectiles.is_empty() and fx.waves.is_empty())
	await reset(8);p.set_physics_process(false);b.set_physics_process(false)
	for id in KnightMoves.MOVES:
		p.rig.initialized=false;var max_step:=0.0;var low:=100.0;var last:=Vector3.INF;var wrist_error:=0.0
		for frame in int(ceil(float(KnightMoves.MOVES[id].length)*60))+1:
			p.rig.pose(id,frame/60.0,1.0/60,0,Vector3.ZERO)
			p.rig.skel.force_update_all_bone_transforms();var blade:Array=p.rig.blade()
			if last!=Vector3.INF:max_step=maxf(max_step,blade[1].distance_to(last))
			last=blade[1];low=minf(low,blade[1].y)
			var wrist:Vector3=p.rig.skel.global_transform*p.rig.skel.get_bone_global_pose(p.rig.ids.hand_r)*p.rig.rest.hand_r.affine_inverse()*p.rig.right_socket
			wrist_error=maxf(wrist_error,wrist.distance_to(p.rig.weapon.to_global(p.rig.source_grip)))
		check(id+" continuous blade motion and floor clearance",max_step<.9 and low>.025,[max_step,low])
		check(id+" visible sword stays in the animated hand",wrist_error<.005,wrist_error)
	# Compare real resource commitments to the available window after a medium roll.
	var quick_window:=BeastMoves.finish("sweep")+float(BeastMoves.ATTACKS.sweep.recover)+.17+.43-(.61-.07+.70)
	var slam_window:=BeastMoves.finish("overhead")+float(BeastMoves.ATTACKS.overhead.recover)+.17+.43-(1.0-.07+.70)
	var light_escape:=float(KnightMoves.MOVES.light1.dodge)+2.0/60
	var heavy_escape:=1.07+2.0/60
	var charged_escape:=heavy_escape+.65
	check("short recovery permits a light punish and rewards restraint",light_escape<quick_window and heavy_escape>quick_window,[quick_window,light_escape,heavy_escape])
	check("dodging a committed overhead earns a normal heavy punish",heavy_escape<slam_window and charged_escape>slam_window,[slam_window,heavy_escape,charged_escape])

func move_bot(dir:Vector3) -> void:
	p.bot_move=Vector2(dir.x,-dir.z)
func _physics_process(dt:float) -> void:
	if not sim_running or not p.alive() or not b.alive():return
	sim_clock+=dt
	var to:Vector3=G.flat(b.global_position-p.global_position);var dist:=to.length();var dir:=to.normalized()
	Input.action_release("sprint")
	if p.state=="attack" and p.action=="heavy":p.heavy_held=want_charge and p.charge_time<.69
	else:p.heavy_held=false
	if p.state not in ["idle","move","hurt"]:move_bot(Vector3.ZERO);return
	if sim_style=="greedy":
		move_bot(dir if dist>1.9 else Vector3.ZERO)
		if sim_clock>=sim_next:
			if p.hp<520 and p.flasks>0:p._queue("heal")
			elif dist<2.65:p._queue("light")
			sim_next=sim_clock+.12
		return
	var danger:=false
	if b.state=="attack":
		for hit in EclipseBeast.MOVES[b.attack].hits:
			if b.t>=float(hit[0])-.10 and b.t<float(hit[1]) and dist<(13 if b.attack in ["lunge","leap"] else 5.2):danger=true
	for wave in fx.waves:
		var distance:float=G.flat(p.global_position-wave.at).length()
		var eta:float=(distance-float(wave.r)*float(wave.age)/float(wave.life))/(float(wave.r)/float(wave.life))
		if not wave.consumed and eta>-.035 and eta<.13:danger=true
	for projectile in fx.projectiles:
		var offset:Vector3=p.global_position+Vector3.UP*.9-projectile.node.global_position
		var eta:float=offset.dot(projectile.dir)/float(projectile.speed)
		if eta>0 and eta<.14 and (offset-projectile.dir*offset.dot(projectile.dir)).length()<1.0:danger=true
	if danger and p.stamina>=18:
		move_bot((dir*.45+dir.cross(Vector3.UP)*.89).normalized());p._queue("dodge");return
	if p.state=="hurt":return
	if b.critical_ready():
		var spot:Vector3=b.global_position+Vector3(sin(b.yaw),0,cos(b.yaw))*2.0
		if G.flat(spot-p.global_position).length()>.4:move_bot(G.flat(spot-p.global_position).normalized())
		else:move_bot(Vector3.ZERO);p._queue("light")
		return
	var safe:=float(b.recovery_duration)-float(b.t)+.60 if b.state=="recover" else (3.0 if b.state=="stagger" else 0.0)
	if p.hp<650 and p.flasks>0 and (safe>1.5 or dist>11 and b.state in ["idle","move"]):move_bot(Vector3.ZERO);p._queue("heal");return
	move_bot(dir if dist>2.1 else Vector3.ZERO)
	if dist>8 and p.stamina>75:Input.action_press("sprint")
	if dist<2.55 and p.state in ["idle","move"] and sim_clock>=sim_next:
		var facing:float=Vector3(sin(p.yaw),0,cos(p.yaw)).dot(dir)
		if facing<.75:return
		if safe>2.0 and p.stamina>=64:want_charge=true;p._queue("heavy");sim_next=sim_clock+.3
		elif safe>1.2 and p.stamina>=52:want_charge=false;p._queue("heavy");sim_next=sim_clock+.3
		elif safe>.65 and p.stamina>=38:p._queue("light");sim_next=sim_clock+.3

func simulate(style:String,rng_seed:int,limit:float) -> void:
	await reset(8);seed(rng_seed);sim_style=style;sim_clock=0;sim_next=0;want_charge=false
	b.ai_enabled=true;b.wait=.45;sim_running=true
	var stats_before:Dictionary=G.stats.duplicate();var phase_seen:=false
	for frame in int(limit*60):
		await step(1);phase_seen=phase_seen or b.phase==2
		if not p.alive() or not b.alive():break
	sim_running=false;Input.action_release("sprint")
	var result:={"style":style,"seed":rng_seed,"seconds":snappedf(sim_clock,.01),"outcome":"win" if not b.alive() else ("loss" if not p.alive() else "time_limit"),"player_hp":p.hp,"boss_hp":b.hp,"boss_damage":EclipseBeast.MAX_HP-b.hp,"flasks_left":p.flasks,"phase_two_reached":phase_seen,"rolls":int(G.stats.rolls)-int(stats_before.rolls),"evades":int(G.stats.evades)-int(stats_before.evades)}
	sim_results.append(result);print("BALANCE SIM ",result)
