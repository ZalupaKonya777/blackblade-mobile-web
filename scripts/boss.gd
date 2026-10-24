class_name EclipseBeast
extends CharacterBody3D

const MAX_HP:=FightBalance.BOSS_HP
const STANCE:=FightBalance.BOSS_STANCE
const MOVES=BeastMoves.ATTACKS
var hp:=MAX_HP
var posture:=0.0
var posture_delay:=0.0
var phase:=1
var state:="dormant"
var attack:=""
var t:=0.0
var wait:=.5
var yaw:=0.0
var rig:FighterRig
var hit_flags:={}
var events:={}
var last_blade:Array=[]
var cooldowns:={}
var history:Array=[]
var aim:=Vector3.ZERO
var air_origin:=Vector3.ZERO
var air_delta:=Vector3.ZERO
var air_base_y:=0.0
var committed_dir:=Vector3(0,0,1)
var drive_distance:=0.0
var transition_pending:=false
var stagger_time:=0.0
var blade_light:OmniLight3D
var eye_light:OmniLight3D
var anim_speed:=1.0
var parry_flash:=false
var spawn:=Vector3(0,.05,-6)
var forced_attack:=""
var orbit:=1.0
var ai_enabled:=true
var paw_step:=0
var recover_from:=""
var recovery_duration:=0.0
var heal_seen:=0.0
var shot_aims:={}
var followup:=""
var pressure:=0
var entry_velocity:=Vector3.ZERO
var body_shape:CollisionShape3D
var rear_shape:CollisionShape3D
var last_strike:Array=[]
const FOLLOWUPS={
 "sweep":["backhand","paw_strike","evade_cut"],
 "backhand":["overhead","evade_cut"],
 "drag":["backhand","overhead"],
 "lunge":["sweep","backhand"],
 "combo":["evade_cut"],
 "paw_strike":["backhand","evade_cut"],
 "air_blades":["lunge"],
 "spin":["backhand","evade_cut"]}
var voice_clock:=0.0
var voice_until:=0.0
var voice_priority:=-1
var breath_at:=2.5
var growl_at:=5.5
var pain_at:=0.0
var voice_awakened:=false

func _voice(event:String,priority:int,hold:float,db:float=-2.0,pitch:float=1.0) -> bool:
	if not G.audio or (voice_clock<voice_until and priority<voice_priority):return false
	G.audio.play(event,lock_point(),db,pitch)
	voice_priority=priority;voice_until=voice_clock+hold
	breath_at=maxf(breath_at,voice_until+1.2);growl_at=maxf(growl_at,voice_until+2.0)
	return true

func _voice_tick(dt:float) -> void:
	voice_clock+=dt
	if not G.playing or state in ["dead","dormant","intro","attack","transition","critical","fall","stagger"]:return
	if not voice_awakened:
		voice_awakened=true;_voice("beast_growl",1,1.55,-2.0)
	if voice_clock<voice_until or not G.player or not G.player.alive():return
	if voice_clock>=growl_at and G.flat(G.player.global_position-global_position).length()<10:
		_voice("beast_growl",1,1.55,-5,.94 if phase==2 else 1.0)
		growl_at=voice_clock+randf_range(6.0,9.0)
	elif voice_clock>=breath_at:
		_voice("beast_breath",0,1.15,-8,.94 if phase==2 else 1.0)
		breath_at=voice_clock+randf_range(3.7,5.2)
var blade_drag_t:=0.0

func _ready() -> void:
	G.boss=self
	collision_layer=4;collision_mask=3
	body_shape=CollisionShape3D.new();var cap:=CapsuleShape3D.new();cap.radius=.90;cap.height=2.2;body_shape.shape=cap;body_shape.position=Vector3(0,1.1,.3);add_child(body_shape)
	rear_shape=CollisionShape3D.new();var rear:=CapsuleShape3D.new();rear.radius=.58;rear.height=1.6;rear_shape.shape=rear;rear_shape.position=Vector3(0,.90,-.55);add_child(rear_shape)
	floor_snap_length=.3
	rig=FighterRig.new();add_child(rig);rig.setup("boss");rig.scale=Vector3.ONE*1.20
	last_blade=rig.blade()
	blade_light=OmniLight3D.new();blade_light.light_color=Color(.95,.10,.12);blade_light.omni_range=5;blade_light.light_cull_mask=1;blade_light.light_energy=0;add_child(blade_light)
	eye_light=OmniLight3D.new();eye_light.light_color=Color(1,.55,.18);eye_light.omni_range=1.2;eye_light.light_cull_mask=1;eye_light.light_energy=.18;add_child(eye_light)

func _physics_process(dt:float) -> void:
	if G.freeze>0:return
	_voice_tick(dt)
	posture_delay-=dt
	if posture_delay<=0 and state not in ["stagger","fall"]:posture=maxf(0,posture-FightBalance.STANCE_REGEN*dt)
	for k in cooldowns:cooldowns[k]-=dt
	t+=dt;blade_drag_t=maxf(0,blade_drag_t-dt)
	if state not in ["idle","move"]:
		velocity.x=move_toward(velocity.x,0,24*dt);velocity.z=move_toward(velocity.z,0,24*dt)
	if G.player and G.player.state=="heal":heal_seen+=dt
	else:heal_seen=0
	if G.playing:
		match state:
			"intro":
				if t>=.45 and not events.has("intro_voice"):
					events.intro_voice=true;_voice("beast_roar",4,2.45,1.0)
				if t>2.4:_idle(.5)
			"idle","move":_think(dt)
			"attack":_run_attack(dt)
			"recover":
				# Complete the weight transfer before the next decision.
				velocity.x=0;velocity.z=0
				if followup!="" and ai_enabled and t>=(.12 if phase==1 else .10) and _can_follow(followup):
					var next:=followup;followup="";start_move(next)
				elif t>=recovery_duration:
					followup="";_idle(.17 if pressure<1 else .36)
			"transition":
				if t>1.1 and not events.has("ignite"):
					events.ignite=true;phase=2;G.new_phase.emit()
					_voice("beast_roar",4,2.5,2.0,.91)
					if G.fx:G.fx.ring(global_position,5.8,Color(1,.15,.12),.9)
					if G.arena:G.arena.rage(true)
				if t>3.0:_idle(1.0)
			"fall":
				if is_on_floor():state="stagger";t=0;velocity=Vector3.ZERO
			"stagger":
				if t>3.2:_idle(.85)
			"critical":
				if t>2.1:_idle(1.1)
	var authored_flight:=false
	if state=="attack" and MOVES[attack].has("flight"):
		var f:Array=MOVES[attack].flight
		if t>=f[0] and t<=f[1]:
			authored_flight=true
			if not events.has("takeoff"):
				events.takeoff=true;air_base_y=global_position.y
				if G.fx:G.fx.ground_contact(global_position,-committed_dir,1.0)
				if G.audio:G.audio.play("boot_land",global_position,-4,.65)
			var previous:float=clampf((t-dt-f[0])/(f[1]-f[0]),0,1)
			var current:float=clampf((t-f[0])/(f[1]-f[0]),0,1)
			# The collision solver integrates both ascent and descent; no root teleport.
			var height:float=4*float(f[2])*current*(1-current)
			var previous_height:float=4*float(f[2])*previous*(1-previous)
			velocity.y=(height-previous_height)/dt
	if not authored_flight:
		if not is_on_floor():velocity.y-=28*dt
		else:velocity.y=-2
	rig.rotation.y=yaw
	body_shape.position=Vector3(sin(yaw)*.3,1.1,cos(yaw)*.3)
	rear_shape.position=Vector3(-sin(yaw)*.55,.90,-cos(yaw)*.55)
	var before:=global_position
	move_and_slide()
	var flat:=Vector2(global_position.x,global_position.z)
	if flat.length()>17.3:
		flat=flat.normalized()*17.3;global_position.x=flat.x;global_position.z=flat.y
	var displacement:=G.flat(global_position-before)/dt
	var stride:=displacement.length() if state in ["idle","move"] else 0.0
	var relative:=displacement.normalized().rotated(Vector3.UP,-yaw)
	var anim:=state
	if state in ["dormant","idle"]:anim="idle"
	elif state=="intro":anim="roar"
	elif state=="attack":anim=attack
	elif state=="recover":anim="recover_"+recover_from
	elif state=="fall":anim="stagger_air"
	rig.pose(anim,t,dt,stride,relative)
	if stride>.25 and is_on_floor() and int(rig.gait/PI)!=paw_step:
		paw_step=int(rig.gait/PI)
		pass # Contact-driven rig events supply the three-limb gait sound.
		if G.fx:G.fx.ground_contact(global_position,displacement.normalized(),.45)
	var blade:=rig.blade()
	var strike:=_strike_segment()
	if G.playing and state=="attack":
		_attack_events(blade)
		if attack=="drag" and t>.34 and t<.90 and blade_drag_t<=0 and blade[1].y<.4:
			blade_drag_t=.30
			if G.audio:G.audio.play("blade_drag",blade[1],-9,1.0)
		_check_blade(strike)
	if G.fx:
		G.fx.trail("boss",blade,state=="attack" and MOVES[attack].get("hit_source","")!="paw" and (_active() or attack=="air_blades" and _shot_release()),Color(1,.15,.12,.56) if phase==2 else Color(.88,.77,.57,.35))
		if phase==2 and state!="dead":G.fx.blade_fire(blade)
	parry_flash=state=="attack" and phase==2 and MOVES[attack].get("parry",false) and _active(true)
	blade_light.global_position=blade[0].lerp(blade[1],.5)
	blade_light.light_color=Color(1,.65,.15) if parry_flash else Color(.95,.05,.07)
	blade_light.light_energy=2.0 if parry_flash else (.9 if phase==2 and state!="dead" else 0.0)
	eye_light.global_position=rig.motion.to_global(rig.globals.head.origin) if rig.globals.has("head") else rig.target_point()
	last_blade=blade
	last_strike=strike

func _think(dt:float) -> void:
	if not ai_enabled or not G.player or not G.player.alive():
		velocity.x=move_toward(velocity.x,0,16*dt);velocity.z=move_toward(velocity.z,0,16*dt);return
	var to:=G.flat(G.player.global_position-global_position)
	var dist:=to.length();var heading:=atan2(to.x,to.z)
	yaw=rotate_toward(yaw,heading,(2.65 if phase==1 else 2.95)*dt)
	wait-=dt
	if transition_pending and is_on_floor():_transition();return
	if wait<=0:
		var choice:=_choose(dist)
		if choice!="":start_move(choice);return
		wait=.22
	var dir:=Vector3.ZERO;var speed:=0.0
	if dist>3.6:dir=to.normalized();speed=5.2 if dist>12 else (3.8 if phase==2 else 3.3)
	elif dist<2.05:dir=-to.normalized();speed=1.9
	elif wait>.11:dir=to.normalized().cross(Vector3.UP)*orbit;speed=1.55 if phase==2 else 1.30
	if speed>0:
		dir=_steer(dir)
	var motor:=Vector3(velocity.x,0,velocity.z).move_toward(dir*speed,(10.0 if speed>0 else 16.0)*dt)
	velocity.x=motor.x;velocity.z=motor.z
	state="move" if motor.length()>.10 else "idle"

func _clear_path(direction:Vector3,distance:float) -> bool:
	if distance<.1:return true
	var side:=direction.cross(Vector3.UP).normalized()*.88
	for offset in [Vector3.ZERO,side,-side]:
		var from:Vector3=global_position+Vector3.UP*.85+offset
		var q:=PhysicsRayQueryParameters3D.create(from,from+direction*distance,1)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():return false
	return true

func _steer(direction:Vector3) -> Vector3:
	if _clear_path(direction,2.1):return direction
	for angle in [.55,1.0,1.45,2.0]:
		for sign_turn in [orbit,-orbit]:
			var candidate:=direction.rotated(Vector3.UP,angle*sign_turn)
			if _clear_path(candidate,2.1):return candidate
	return Vector3.ZERO

func _choose(dist:float) -> String:
	if forced_attack!="":
		var chosen:=forced_attack;forced_attack="";return chosen
	var choices:Array=[];var total:=0.0
	var to:=G.flat(G.player.global_position-global_position)
	var angle:=absf(wrapf(atan2(to.x,to.z)-yaw,-PI,PI))
	for id in MOVES:
		var m:Dictionary=MOVES[id]
		if m.get("phase",1)>phase or cooldowns.get(id,0)>0:continue
		if angle>(1.65 if m.get("wide",false) else .95):continue
		if dist>m.reach or dist<float(m.get("min_range",0)):continue
		if not _clear_path(to.normalized(),maxf(.1,dist-1.1)):continue
		var w:float=m.weight
		if not history.is_empty() and history.back()==id:w*=.08
		if history.has(id):w*=.58
		if dist>7 and id in ["lunge","leap","air_blades"]:w*=2
		if dist<3.2 and id in ["combo","sweep","spin"]:w*=1.5
		if dist<2.8 and id in ["paw_strike","backhand","evade_cut"]:w*=1.65
		if heal_seen>.35 and id in ["lunge","leap"]:w*=1.55
		if id=="death_storm" and dist>4:w*=.45
		total+=w;choices.append([id,total])
	if choices.is_empty():return ""
	var pick:=randf()*total
	for v in choices:
		if pick<=v[1]:return v[0]
	return choices.back()[0]

func _can_follow(id:String) -> bool:
	if transition_pending or pressure>=1 or not G.player or not G.player.alive():return false
	var to:=G.flat(G.player.global_position-global_position)
	return MOVES[id].get("phase",1)<=phase and cooldowns.get(id,0)<=0 and to.length()>=MOVES[id].get("min_range",0) and to.length()<=MOVES[id].reach and absf(wrapf(atan2(to.x,to.z)-yaw,-PI,PI))<(.95 if MOVES[id].get("wide",false) else .70) and _clear_path(to.normalized(),to.length()-1)

func _plan_followup(finished:String) -> String:
	if not ai_enabled or pressure>=1 or transition_pending:return ""
	# Heavy misses remain punishable; only compact attacks may branch.
	if randf()>(.52 if phase==1 else .68):return ""
	var available:Array=[]
	for id in FOLLOWUPS.get(finished,[]):
		if _can_follow(id):available.append(id)
	return available.pick_random() if not available.is_empty() else ""

func start_move(id:String) -> void:
	if not MOVES.has(id) or not alive() or not G.player:return
	pressure=pressure+1 if state=="recover" else 0
	entry_velocity=G.flat(velocity)
	state="attack";attack=id;t=0;hit_flags.clear();events.clear();shot_aims.clear();followup=""
	cooldowns[id]=MOVES[id].cooldown*(.90 if phase==2 else 1.0)
	history.append(id)
	if history.size()>3:history.pop_front()
	aim=G.flat(G.player.global_position-global_position)
	air_origin=global_position;air_delta=Vector3.ZERO;drive_distance=0
	last_strike=[]
	# Turn during anticipation instead of snapping on attack start.
	if id in ["leap","air_blades","death_storm"]:_voice("beast_growl",1,1.35,-4,.96)

func _commit_attack() -> void:
	if events.has("commit"):return
	events.commit=true
	aim=G.flat(G.player.global_position-global_position)
	committed_dir=Vector3(sin(yaw),0,cos(yaw))
	drive_distance=clampf(aim.length()-2.6,2.0,9.6)
	air_origin=global_position
	air_delta=committed_dir*clampf(aim.length()-1.35,1.0,14.0) if attack=="leap" else -committed_dir*1.65
	if MOVES[attack].has("retreat"):
		var retreat:Array=MOVES[attack].retreat
		air_delta=-committed_dir*float(retreat[2])+committed_dir.cross(Vector3.UP)*orbit*float(retreat[3])
	if not _clear_path(air_delta.normalized(),air_delta.length()):air_delta=Vector3.ZERO

func _run_attack(dt:float) -> void:
	var m:Dictionary=MOVES[attack]
	if t<float(m.track):
		var to:=G.flat(G.player.global_position-global_position)
		if to.length()>.1:yaw=rotate_toward(yaw,atan2(to.x,to.z),float(m.turn)*dt)
	else:_commit_attack()
	if m.has("retreat"):
		var d:Array=m.retreat
		var delta:float=BeastMoves.smooth_motion((t-d[0])/(d[1]-d[0]))-BeastMoves.smooth_motion((t-dt-d[0])/(d[1]-d[0]))
		velocity.x=air_delta.x*delta/dt;velocity.z=air_delta.z*delta/dt
	elif m.has("drive"):
		var d:Array=m.drive
		var delta:float=BeastMoves.drive_progress((t-d[0])/(d[1]-d[0]))-BeastMoves.drive_progress((t-dt-d[0])/(d[1]-d[0]))
		velocity.x=committed_dir.x*drive_distance*delta/dt;velocity.z=committed_dir.z*drive_distance*delta/dt
	elif m.has("flight"):
		var f:Array=m.flight
		var delta:float=BeastMoves.smooth_motion((t-f[0])/(f[1]-f[0]))-BeastMoves.smooth_motion((t-dt-f[0])/(f[1]-f[0]))
		velocity.x=air_delta.x*delta/dt;velocity.z=air_delta.z*delta/dt
	elif m.has("step"):
		var delta:float=BeastMoves.smooth_motion((t-.25)/.65)-BeastMoves.smooth_motion((t-dt-.25)/.65)
		velocity.x=sin(yaw)*float(m.step)*delta/dt;velocity.z=cos(yaw)*float(m.step)*delta/dt
	if t<.18:
		var coast:=entry_velocity*(1-smoothstep(0,.18,t))
		velocity.x+=coast.x;velocity.z+=coast.z
	if attack=="air_blades":
		for i in m.shots.size():
			if t>=float(m.shots[i])-.18 and not shot_aims.has(i):
				var predicted:Vector3=G.player.global_position+Vector3.UP*.88
				var to:=G.flat(predicted-global_position)
				var heading:=yaw+clampf(wrapf(atan2(to.x,to.z)-yaw,-PI,PI),-1.12,1.12)
				shot_aims[i]=Vector3(global_position.x+sin(heading)*to.length(),predicted.y,global_position.z+cos(heading)*to.length())
	if t>=BeastMoves.finish(attack):
		var finished:=attack
		followup=_plan_followup(finished)
		recover_from=finished;recovery_duration=m.recover;state="recover";attack="";t=0
		velocity.x=0;velocity.z=0

func _attack_events(blade:Array) -> void:
	var m:Dictionary=MOVES[attack]
	for i in m.hits.size():
		var h:Array=m.hits[i];var key:="sound%d"%i
		if t>=h[0]-.10 and not events.has(key):
			events[key]=true
			if G.audio:
				if m.get("hit_source","")=="paw":G.audio.play("armor_takeoff",_bone_head("hand_l"),-8,.78)
				else:G.audio.play("boss_swing",blade[0],-2,1.0)
			_voice("beast_attack",2,.68,-2,.94 if phase==2 else 1.0)
	if attack=="drag" and t>.47 and t<.96 and blade[1].y<.38 and int(t*16)!=events.get("scrape",-1):
		events.scrape=int(t*16)
		var tip:Vector3=blade[1];tip.y=.055
		if G.fx:G.fx.burst(tip,Color(1,.65,.25),4,2.2);G.fx.ground_contact(tip,committed_dir,.32)
	if attack=="overhead" and t>=1.16 and not events.has("impact"):
		events.impact=true
		var point:Vector3=blade[1];point.y=.055
		if G.fx:G.fx.slam(point,2.7,phase==2)
		if G.audio:G.audio.play("slam",point,-3)
		if G.camera:G.camera.shake(.3)
	if attack=="leap":
		if t>.28 and not events.has("tell"):
			events.tell=true
			if G.fx:G.fx.telegraph(air_origin+air_delta,3.8,1.30,phase==2)
		if t>=1.58 and not events.has("land") and global_position.y<.3:
			events.land=true
			if G.fx:G.fx.slam(global_position,4.2,phase==2)
			if G.audio:G.audio.play("slam",global_position,-1,.8)
			_voice("beast_attack",2,.72,0.0,.92)
			if G.camera:G.camera.shake(.42)
		if t>=1.90 and not events.has("wave") and events.has("land"):
			events.wave=true
			if G.fx:G.fx.shockwave(global_position,4.4,260,phase==2,.60)
	if attack=="air_blades":
		for i in m.shots.size():
			var fire_time:float=m.shots[i]
			if t>=fire_time and not events.has("shot%d"%i):
				events["shot%d"%i]=true
				var start:Vector3=blade[0].lerp(blade[1],.60)
				if G.fx:G.fx.projectile(start,shot_aims.get(i,G.player.global_position+Vector3.UP*.9),300,18.5,i%2)
				if G.audio:G.audio.play("projectile",start,-1,.75)
				_voice("beast_attack",2,.68,-2,1.05)
			elif t>=fire_time-.18 and t<fire_time and G.fx:G.fx.charge(blade[1])
	if attack=="death_storm":
		if t>=.12 and not events.has("tell"):
			events.tell=true
			if G.fx:G.fx.telegraph(global_position,4.8,1.14,true)
		if t>=1.26 and not events.has("slam"):
			events.slam=true
			if G.fx:G.fx.slam(blade[1],5,true)
			if G.audio:G.audio.play("slam",global_position,-1,.7)
			_voice("beast_roar",4,2.3,0.0,.94)
		for i in m.pulses.size():
			if t>=float(m.pulses[i]) and not events.has("pulse%d"%i):
				events["pulse%d"%i]=true
				if G.fx:G.fx.shockwave(global_position,4.8,135,true,.65);G.fx.death_cut(global_position,4.8,i)

func _shot_release() -> bool:
	for fire_time in MOVES.air_blades.shots:
		if absf(t-float(fire_time))<.12:return true
	return false

func _active(early:=false) -> bool:
	return BeastMoves.active(attack,t,.20 if early else 0.0)

func _strike_segment() -> Array:
	if attack!="" and MOVES[attack].get("hit_source","")=="paw":
		return [rig.motion.to_global(rig.globals.fore_l.origin),rig.motion.to_global(rig.globals.hand_l.origin)]
	return rig.blade()

func _check_blade(blade:Array) -> void:
	if state!="attack" or not G.player or not G.player.alive():return
	var m:Dictionary=MOVES[attack]
	for i in m.hits.size():
		if hit_flags.has(i):continue
		var h:Array=m.hits[i]
		if t<h[0] or t>=h[1]:continue
		var previous:Array=last_strike if last_strike.size()==2 else blade
		var radius:=.24 if m.get("hit_source","")=="paw" else .16
		if CombatMath.blade_hits(previous,blade,G.player,radius):
			hit_flags[i]=true
			G.player.receive_hit(h[2]*(1.08 if phase==2 else 1),global_position,108 if attack in ["overhead","leap"] else 72,phase==2,phase==2 and m.get("parry",false),m.get("low",false))
			if state!="attack":return

func _idle(delay:float) -> void:
	state="idle";attack="";t=0;wait=delay;orbit=-orbit if randf()<.35 else orbit
	velocity.x=0;velocity.z=0
	if transition_pending and is_on_floor():_transition()

func _transition() -> void:
	transition_pending=false;state="transition";attack="";t=0;events.clear();followup=""
	velocity.x=0;velocity.z=0

func take_damage(amount:float,stance:float,point:Vector3,_kind:String) -> void:
	if state in ["dead","dormant"]:return
	if state=="transition":amount*=.25
	if not G.training:hp=maxf(0,hp-amount)
	posture_delay=FightBalance.STANCE_DELAY
	if state not in ["stagger","critical","transition","fall"]:posture+=stance
	if G.fx:G.fx.burst(point,Color(.9,.55,.24),18 if amount<400 else 28,3.4)
	if G.audio:G.audio.play("impact_beast",point,-3,1.0)
	rig.impact((.018 if amount<350 else .055)*(.35 if state=="attack" else 1.0),G.flat(point-global_position).normalized())
	if G.ui:G.ui.damage_number(amount,point)
	if hp<=0:
		state="dead";t=0;attack="";followup="";_voice("beast_death",5,3.2,1.0,.96);G.beast_dead.emit();return
	if voice_clock>=pain_at:
		_voice("beast_pain",3,.72,-1.0,.94 if phase==2 else 1.0);pain_at=voice_clock+.55
	if phase==1 and hp<=MAX_HP*.5:transition_pending=true
	if posture>=STANCE and state not in ["stagger","critical","transition","fall"]:_stagger()
	elif transition_pending and state in ["idle","move"] and is_on_floor():_transition()

func _stagger() -> void:
	posture=0;attack="";t=0;followup=""
	if global_position.y>.35:
		state="fall";velocity.y=minf(velocity.y,1.0);velocity.x*=.3;velocity.z*=.3
	else:state="stagger";velocity=Vector3.ZERO
	if G.audio:G.audio.play("parry",global_position,-3,.65)
	if voice_clock>=pain_at:
		_voice("beast_pain",3,.9,-1,.90);pain_at=voice_clock+.55
	if G.ui:G.ui.notify("СТОЙКА СЛОМЛЕНА", "Подойди спереди и нажми ЛКМ")

func parried() -> void:_stagger()
func critical_ready() -> bool:return state=="stagger" and t>.30 and t<2.8 and global_position.y<.35
func accept_critical() -> void:state="critical";t=0

func hurt_segments() -> Array:
	var result:Array=[]
	for link in [["pelvis","spine2",.53],["spine2","head",.60]]:
		result.append([_bone_head(link[0]),_bone_head(link[1]) if link[1]!="" else _bone_tail(link[0]),link[2]])
	var head_forward:Vector3=(rig.motion.global_basis*rig.globals.head.basis*rig.rest.head.basis.inverse()*Vector3.BACK).normalized()*.16
	result.append([_bone_head("head")+head_forward,_bone_tail("head")+head_forward,.48])
	for side in ["l","r"]:
		for link in [["upper_","fore_",.36],["fore_","hand_",.36],["thigh_","shin_",.43],["shin_","foot_",.42],["foot_","",.38]]:
			result.append([_bone_head(link[0]+side),_bone_head(link[1]+side) if link[1]!="" else _bone_tail(link[0]+side),link[2]])
	return result

func _bone_head(bone:String) -> Vector3:
	return rig.motion.to_global(rig.globals[bone].origin)

func _bone_tail(bone:String) -> Vector3:
	return rig.motion.to_global(rig.globals[bone]*rig.rest[bone].affine_inverse()*rig.tails[bone])

func lock_point() -> Vector3:return rig.target_point()+Vector3.UP*.25
func alive() -> bool:return state!="dead"

func set_training_phase() -> void:
	phase=2 if phase==1 else 1
	state="idle";attack="";t=0;wait=1;velocity=Vector3.ZERO
	global_position.y=.045
	cooldowns.clear();events.clear();shot_aims.clear();transition_pending=false;followup="";forced_attack=""
	rig.initialized=false

func reset(at:Vector3) -> void:
	voice_clock=0.0;voice_until=0.0;voice_priority=-1;breath_at=2.5;growl_at=5.5;pain_at=0.0;voice_awakened=false
	last_strike=[]
	global_position=at;velocity=Vector3.ZERO;yaw=0;hp=MAX_HP;posture=0;posture_delay=0;phase=1;state="dormant";attack="";t=0;wait=.5
	cooldowns.clear();events.clear();history.clear();hit_flags.clear();shot_aims.clear();transition_pending=false;forced_attack="";followup=""
	recover_from="";recovery_duration=0;pressure=0;heal_seen=0;air_delta=Vector3.ZERO;drive_distance=0;parry_flash=false;entry_velocity=Vector3.ZERO
	rig.initialized=false
