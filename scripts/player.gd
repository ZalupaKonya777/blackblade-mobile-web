class_name PlayerUnit
extends CharacterBody3D

const MAX_HP:=FightBalance.PLAYER_HP
const MAX_STAMINA:=FightBalance.STAMINA
const RUN:=FightBalance.RUN
const SPRINT:=FightBalance.SPRINT
const ROLL_COST:=FightBalance.ROLL_COST
const REGEN:=FightBalance.REGEN
var hp:=MAX_HP
var hp_cap:=MAX_HP
var stamina:=MAX_STAMINA
var flasks:=FightBalance.FLASKS
var state:="idle"
var action:=""
var t:=0.0
var duration:=0.0
var yaw:=PI
var rig:FighterRig
var target:Node3D
var move_input:=Vector2.ZERO
var move_dir:=Vector3.ZERO
var dodge_dir:=Vector3.ZERO
var dodge_held:=false
var dodge_hold:=0.0
var sprinting:=false
var guarding:=false
var invulnerable:=false
var lower_invulnerable:=false
var queue:=""
var queue_left:=0.0
var regen_delay:=0.0
var dd_timer:=0.0
var dd_damage:=0.0
var combo:=0
var charge_time:=0.0
var heavy_held:=false
var parry_held:=false
var charged:=false
var hit_done:=false
var healed:=false
var last_block:=10.0
var airborne:=false
var roll_duration:=.70
var roll_distance:=3.25
var last_blade:Array=[]
var foot_clock:=0.0
var footstep_index:=0
var damage_timer:=0.0
var bot_move:=Vector2.INF
var roll_evaded:=false
var controls_enabled:=true
var roll_events:={}
var body_shape:CollisionShape3D
var body_capsule:CapsuleShape3D
var attack_events:={}
var damage_grace:=0.0
var hurt_dir:=Vector3.ZERO
var hurt_speed:=0.0
var hurt_cancel:=.32
var guard_kick:=0.0
var attack_yaw:=0.0
var air_velocity:=Vector3.ZERO

func _ready() -> void:
	G.player=self
	collision_layer=2;collision_mask=1
	body_shape=CollisionShape3D.new();body_capsule=CapsuleShape3D.new();body_capsule.radius=.31;body_capsule.height=1.60;body_shape.shape=body_capsule;body_shape.position.y=.80;add_child(body_shape)
	floor_snap_length=.30
	rig=FighterRig.new();add_child(rig);rig.setup("knight")
	last_blade=rig.blade()

func _unhandled_input(e:InputEvent) -> void:
	if not G.playing or not controls_enabled or state=="dead" or get_tree().paused:return
	if e.is_action_pressed("dodge"):
		dodge_held=true;dodge_hold=0
	elif e.is_action_released("dodge"):
		if dodge_held and dodge_hold<.26:_queue("dodge")
		dodge_held=false;sprinting=false
	if e.is_action_pressed("light"): _queue("light")
	if e.is_action_pressed("heavy"):
		if not heavy_held:_queue("heavy")
		heavy_held=true
	if e.is_action_released("heavy"):heavy_held=false
	if e.is_action_pressed("heal"):_queue("heal")
	if e.is_action_pressed("jump"):_queue("jump")
	if e.is_action_pressed("parry"):
		if not parry_held:_queue("parry")
		parry_held=true
	if e.is_action_released("parry"):parry_held=false
	if e.is_action_pressed("lock"):toggle_lock()

func _queue(cmd:String) -> void:
	queue=cmd;queue_left=.40

func toggle_lock() -> void:
	if target:target=null
	elif G.boss and G.boss.alive() and global_position.distance_to(G.boss.global_position)<36:target=G.boss
	if G.audio:G.audio.play("menu",global_position,-9)

func _physics_process(dt:float) -> void:
	if not G.playing or not controls_enabled:
		rig.rotation.y=yaw;rig.pose("idle",0,dt,0,Vector3.ZERO)
		return
	if G.freeze>0:return
	damage_grace=maxf(0,damage_grace-dt);guard_kick=maxf(0,guard_kick-dt*5)
	queue_left-=dt
	if queue_left<=0:queue=""
	regen_delay=maxf(0,regen_delay-dt);last_block+=dt;damage_timer+=dt
	if dodge_held:dodge_hold+=dt
	if target and (not is_instance_valid(target) or not target.alive()):target=null
	var inp:=Input.get_vector("left","right","back","forward") if bot_move==Vector2.INF else bot_move
	move_input=inp
	var cy:float=G.camera.yaw if G.camera else 0
	move_dir=Vector3(-sin(cy),0,-cos(cy))*inp.y+Vector3(cos(cy),0,-sin(cy))*inp.x
	guarding=Input.is_action_pressed("guard") and state in ["idle","move"] and stamina>0
	if dd_timer>0:
		dd_timer-=dt;hp=maxf(1 if G.training else 0,hp-dd_damage*dt)
		if hp<=0 and state!="dead":_die()
	else:
		hp_cap=minf(MAX_HP,hp_cap+90*dt)
	if G.training and damage_timer>2.0:
		hp=minf(MAX_HP,hp+400*dt);hp_cap=MAX_HP;dd_timer=0
	if regen_delay<=0 and state in ["idle","move"] and not sprinting:
		stamina=minf(MAX_STAMINA,stamina+REGEN*dt*(.35 if guarding else 1.0))
	var anim:="idle"
	var anim_t:=t
	var stride:=0.0
	invulnerable=false;lower_invulnerable=false
	if state in ["idle","move"]:
		if queue!="" and _command(queue):queue=""
		if state in ["idle","move"]:
			sprinting=(Input.is_action_pressed("sprint") or (dodge_held and dodge_hold>=.26)) and inp.length()>.1 and stamina>0 and not guarding
			var speed:=SPRINT if sprinting else (1.6 if guarding else RUN)
			if target and not sprinting:speed*=.88
			if sprinting:spend(FightBalance.SPRINT_DRAIN*dt)
			var desired:=move_dir.normalized()*speed*inp.length()
			var acceleration:=FightBalance.ACCEL if desired.length()>Vector2(velocity.x,velocity.z).length() else FightBalance.BRAKE
			var flat_velocity:=Vector3(velocity.x,0,velocity.z).move_toward(desired,acceleration*dt)
			velocity.x=flat_velocity.x+hurt_dir.x*guard_kick;velocity.z=flat_velocity.z+hurt_dir.z*guard_kick
			if target and not sprinting:
				var v:=G.flat(target.global_position-global_position);yaw=rotate_toward(yaw,atan2(v.x,v.z),7.0*dt)
			elif move_dir.length()>.1:yaw=rotate_toward(yaw,atan2(move_dir.x,move_dir.z),8.0*dt)
			stride=Vector2(velocity.x,velocity.z).length();anim="guard" if guarding else "move"
	else:
		t+=dt;anim_t=t
		velocity.x=move_toward(velocity.x,0,35*dt);velocity.z=move_toward(velocity.z,0,35*dt)
		match state:
			"roll":
				var f:=clampf(t/roll_duration,0,1)
				var speed:=roll_distance*(RollMotion.travel(f)-RollMotion.travel((t-dt)/roll_duration))/dt
				velocity.x=dodge_dir.x*speed;velocity.z=dodge_dir.z*speed
				var roll_frame:=floori(t*60.0+.0001)
				invulnerable=roll_frame>=2 and roll_frame<28
				if int(G.settings.load)==2:invulnerable=roll_frame>=2 and roll_frame<26
				anim="roll";anim_t=t*.70/roll_duration
				_roll_contacts(f)
				if queue=="light" and t>=roll_duration-.06:
					_attack("roll_attack");queue=""
				elif t>=roll_duration:_finish()
			"backstep":
				var back:=Vector3(-sin(yaw),0,-cos(yaw))
				velocity.x=back.x*4.0*(1-t/.5);velocity.z=back.z*4.0*(1-t/.5);anim="backstep"
				if t>=.50:_finish()
			"attack":
				_advance_attack(dt);anim=action;anim_t=t
			"heal":
				anim="heal"
				velocity.x=move_dir.x*.55;velocity.z=move_dir.z*.55
				if t>=FightBalance.FLASK_USE and not healed:
					healed=true;hp=minf(hp_cap,hp+FightBalance.FLASK_HEAL)
					if G.fx:G.fx.heal(global_position)
					if G.audio:G.audio.play("flask",global_position,-6)
				if t>=FightBalance.FLASK_RECOVER:_finish()
			"parry":
				anim="parry"
				if t>=.56:_finish()
			"hurt":
				anim="hurt"
				velocity.x=hurt_dir.x*hurt_speed*exp(-12*t);velocity.z=hurt_dir.z*hurt_speed*exp(-12*t)
				if queue=="dodge" and t>=hurt_cancel and _command("dodge"):queue=""
				elif t>=duration:_finish()
			"jump":
				anim="jump";lower_invulnerable=t>.08 and velocity.y>-.5
				velocity.x=dodge_dir.x*3.8;velocity.z=dodge_dir.z*3.8
				if queue in ["light","heavy"] and t>.10:
					_attack("jump_attack");queue=""
				elif is_on_floor() and t>.20:_finish()
			"critical":
				anim="heavy";invulnerable=true
				if t>.62 and not hit_done:
					hit_done=true
					G.boss.take_damage(FightBalance.CRITICAL_DAMAGE,0,global_position+Vector3.UP,"critical")
					G.impact(.12)
				if t>1.8:_finish()
			"dead":anim="dead"
	if not is_on_floor():velocity.y-=25*dt
	elif state!="jump":velocity.y=-2
	rig.rotation.y=yaw
	var crouch:=smoothstep(.03,.16,t/roll_duration)*(1-smoothstep(.76,.98,t/roll_duration)) if state=="roll" else 0.0
	body_capsule.height=lerpf(1.60,.80,crouch);body_shape.position.y=body_capsule.height*.5
	move_and_slide()
	if G.arena:
		var flat:=Vector2(global_position.x,global_position.z)
		if flat.length()>18.3:
			flat=flat.normalized()*18.3;global_position.x=flat.x;global_position.z=flat.y
	if G.boss and G.boss.alive() and not invulnerable and state!="critical":
		var sep:=G.flat(global_position-G.boss.global_position)
		if sep.length()<.94 and sep.length()>.01:global_position+=sep.normalized()*(.94-sep.length())*.45
	if state=="attack":anim=action;anim_t=t
	elif state=="roll" and anim!="roll":anim="roll";anim_t=t*.70/roll_duration
	elif state=="hurt":anim="hurt";anim_t=t
	rig.pose(anim,anim_t,dt,stride,move_dir.rotated(Vector3.UP,-yaw),combo)
	var blade:=rig.blade()
	if state=="attack":_hit(blade)
	if G.fx:G.fx.trail("player",blade,state=="attack" and KnightMoves.active(action,combo,t),Color(.65,.82,1,.24))
	last_blade=blade
	var step_index:=int(rig.gait/PI)
	if stride>1.2 and is_on_floor() and step_index!=footstep_index:
		footstep_index=step_index
		var side:="l" if step_index%2==0 else "r"
		var contact:Vector3=rig.motion.to_global(rig.feet.get(side,Vector3.ZERO))
		if G.audio:
			G.audio.play("step",contact,-22 if not sprinting else -19,randf_range(.92,1.08))
			G.audio.play("boot_land",contact,-24 if not sprinting else -20)
		if sprinting and G.fx:G.fx.ground_contact(contact,move_dir,.20)

func _command(cmd:String) -> bool:
	if cmd=="dodge":
		if not is_on_floor() or stamina<ROLL_COST:return false
		spend(ROLL_COST);sprinting=false;roll_evaded=false;G.stats.rolls+=1
		if move_dir.length()<.1:_begin("backstep");return true
		dodge_dir=move_dir.normalized()
		roll_duration=[.70,.70,.93][int(G.settings.load)]
		roll_distance=[4.10,3.25,2.65][int(G.settings.load)]
		rig.roll_direction=dodge_dir.rotated(Vector3.UP,-yaw)
		roll_events.clear()
		_begin("roll")
		if G.audio:G.audio.play("armor_takeoff",global_position,-13)
		return true
	if cmd in ["light","heavy"]:
		if cmd=="light" and G.boss and G.boss.critical_ready() and global_position.distance_to(G.boss.global_position)<3.0 and Vector3(sin(G.boss.yaw),0,cos(G.boss.yaw)).dot(G.flat(global_position-G.boss.global_position).normalized())>0.05:
			var toward:=G.flat(G.boss.lock_point()-global_position).normalized()
			yaw=atan2(toward.x,toward.z)
			G.boss.accept_critical();_begin("critical");hit_done=false;return true
		return _attack("counter" if cmd=="heavy" and last_block<.8 else cmd)
	if cmd=="heal":
		if flasks<=0 or hp>=hp_cap-.5:return true
		if not G.training:flasks-=1
		_begin("heal");healed=false;return true
	if cmd=="jump":
		if not is_on_floor() or stamina<12:return false
		spend(12)
		dodge_dir=move_dir.normalized();velocity.y=6.2;_begin("jump");return true
	if cmd=="parry":
		if stamina<16:return false
		spend(16);_begin("parry");return true
	return false

func _begin(s:String) -> void:
	state=s;t=0;invulnerable=false;guarding=false;sprinting=false

func _finish() -> void:
	state="idle";action="";t=0;invulnerable=false

func _attack(which:String,chain:=0) -> bool:
	var m:Dictionary=KnightMoves.data(which,chain)
	if stamina<float(m.cost):return false
	air_velocity=Vector3(velocity.x,0,velocity.z)
	_begin("attack");action=which;combo=chain;hit_done=false;charged=false;charge_time=0;attack_events.clear();attack_yaw=yaw
	spend(m.cost)
	return true

func _advance_attack(dt:float) -> void:
	var m:Dictionary=KnightMoves.data(action,combo)
	var previous:=t-dt
	if action=="heavy" and heavy_held and t>=.50 and charge_time<.85:
		t=maxf(.50,previous);charge_time+=dt
		if charge_time>=FightBalance.CHARGE_TIME and not charged:
			if stamina>=FightBalance.CHARGE_COST:spend(FightBalance.CHARGE_COST);charged=true
			else:charge_time=.85
		if charged and G.fx:G.fx.charge(rig.blade()[0])
	if t<float(m.wind)*.68:
		var direction:=G.flat(target.global_position-global_position) if target else move_dir
		if direction.length()>.1:yaw=rotate_toward(yaw,atan2(direction.x,direction.z),5.5*dt)
		attack_yaw=yaw
	var d:Array=m.drive
	var progress:=BeastMoves.smooth_motion((t-float(d[0]))/(float(d[1])-float(d[0])))-BeastMoves.smooth_motion((previous-float(d[0]))/(float(d[1])-float(d[0])))
	var speed:=float(m.travel)*progress/dt
	velocity.x=sin(attack_yaw)*speed;velocity.z=cos(attack_yaw)*speed
	if action=="jump_attack" and not is_on_floor():velocity.x=air_velocity.x;velocity.z=air_velocity.z
	if t>=float(m.wind)-.04 and not attack_events.has("swing"):
		attack_events.swing=true
		if G.audio:G.audio.play("swing",rig.blade()[0],-5,.74 if action in ["heavy","counter","jump_attack"] else .92)
	if queue=="dodge" and t>=float(m.dodge):
		if _command("dodge"):queue=""
	elif queue in ["light","heavy"] and t>=float(m.chain):
		var chain:=combo+1 if action=="light" and queue=="light" else 0
		if chain<3 and _attack(queue,chain):queue=""
	if state=="attack" and t>=float(m.length):_finish()

func spend(amount:float) -> void:
	stamina=maxf(0,stamina-amount);regen_delay=FightBalance.REGEN_DELAY
	if stamina<=0:regen_delay=.90

func _hit(blade:Array) -> void:
	if hit_done or not G.boss or not G.boss.alive():return
	var m:Dictionary=KnightMoves.data(action,combo)
	var damage:float=m.damage;var stance:float=m.stance
	if charged:damage=610.0;stance=56.0
	if not KnightMoves.active(action,combo,t):return
	if CombatMath.blade_hits(last_blade,blade,G.boss,.13):
		hit_done=true;G.stats.hits+=1;G.stats.damage+=damage
		G.boss.take_damage(damage,stance,blade[1],action)
		G.impact(.035 if damage<350 else (.075 if charged else .055))
		if G.camera:G.camera.hit_recoil(-Vector3(sin(yaw),0,cos(yaw)),.38 if damage<350 else .85)
		if G.audio and damage>=350:G.audio.play("body_contact",blade[1],-15,.70)

func hurt_segments() -> Array:
	var low:=global_position+Vector3.UP*.32
	var high:=global_position+Vector3.UP*1.52
	if state=="roll" and t/roll_duration>.14 and t/roll_duration<.76:
		low=global_position+Vector3.UP*.22;high=global_position+Vector3.UP*.75
	return [[low,high,.30]]

func _roll_contacts(f:float) -> void:
	if f>=.27 and not roll_events.has("shoulder"):
		roll_events.shoulder=true
		if G.fx:G.fx.ground_contact(global_position+dodge_dir*.23,dodge_dir,.55)
		if G.audio:G.audio.play("body_contact",global_position,-12,.95 if int(G.settings.load)<2 else .78)
	if f>=.72 and not roll_events.has("plant"):
		roll_events.plant=true
		if G.fx:G.fx.ground_contact(global_position+dodge_dir*.13,-dodge_dir,.35)
		if G.audio:G.audio.play("boot_land",global_position,-13)
		if G.camera:G.camera.landing(.35 if int(G.settings.load)<2 else .65)

func receive_hit(damage:float, source:Vector3, posture:=60.0, cursed:=false, parryable:=false, low:=false) -> bool:
	if state=="dead":return false
	if damage_grace>0:return false
	if invulnerable or (low and lower_invulnerable):
		if not roll_evaded:
			roll_evaded=true;G.stats.evades+=1
		return false
	var from:=G.flat(source-global_position).normalized()
	hurt_dir=-from
	var frontal:=Vector3(sin(yaw),0,cos(yaw)).dot(from)>.15
	if state=="parry" and t>=.08 and t<.30 and parryable and frontal:
		G.boss.parried()
		if G.fx:G.fx.burst(rig.blade()[0],Color(1,.78,.3),28,4)
		if G.audio:G.audio.play("parry",global_position,-1)
		G.impact(.10)
		return true
	if guarding and frontal:
		stamina=maxf(0,stamina-posture);regen_delay=.80;last_block=0;damage*=.28 if cursed else .20;guard_kick=.65
		rig.impact(.025,from)
		if G.audio:G.audio.play("guard",global_position,-6)
		if G.fx:G.fx.burst(global_position+Vector3.UP*1.2,Color(1,.7,.3),15,3)
		if stamina<=0:_begin("hurt");duration=1.10;hurt_cancel=.84;hurt_speed=3.0
	else:
		var armored:=state=="attack" and charged and t>=.60 and t<=.89 and posture<100
		if not armored:
			_begin("hurt");duration=.58 if posture<100 else .92;hurt_cancel=.32 if posture<100 else .48
			hurt_speed=3.0 if posture<100 else 5.1
		rig.impact(.055 if posture<100 else .10,from)
		if G.audio:G.audio.play("hit",global_position,-5)
		if G.fx:G.fx.burst(global_position+Vector3.UP,Color(.65,.06,.04),12,2)
	hp-=damage;damage_timer=0;G.stats.taken+=damage
	damage_grace=FightBalance.HIT_GRACE
	if G.training:hp=maxf(1,hp)
	if cursed:
		hp_cap=MAX_HP*.90;hp=minf(hp,hp_cap);dd_timer=FightBalance.CURSE_SECONDS;dd_damage=FightBalance.CURSE_DPS
	if G.camera:G.camera.hit_recoil(-from,.62 if posture<100 else 1.0)
	G.impact(.04 if posture<100 else .065)
	if hp<=0:
		_die()
	return true

func _die() -> void:
	hp=0;_begin("dead");target=null;G.player_dead.emit()

func alive() -> bool:return state!="dead"

func reset(at:Vector3) -> void:
	global_position=at;velocity=Vector3.ZERO;yaw=PI
	hp=MAX_HP;hp_cap=MAX_HP;stamina=MAX_STAMINA;flasks=FightBalance.FLASKS;dd_timer=0;dd_damage=0
	state="idle";action="";t=0;queue="";queue_left=0;target=null;dodge_held=false;heavy_held=false
	invulnerable=false;regen_delay=0;sprinting=false;charge_time=0;last_block=10
	damage_grace=0;hurt_speed=0;hurt_dir=Vector3.ZERO;guard_kick=0;hurt_cancel=.32;air_velocity=Vector3.ZERO;attack_events.clear()
	roll_events.clear();body_capsule.height=1.60;body_shape.position.y=.80
	rig.initialized=false
