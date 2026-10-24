extends Node
## The browser feeds the same InputEvents as a controller. Physics and roll curves
## are shared with the desktop game; the DOM only supplies controls and the HUD.
var browser
var callback
var held:={}
var timer:=0.0
const ACTIONS=["light","heavy","dodge","guard","heal","jump","parry","lock","sprint"]

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	G.ui.visible=false
	browser=JavaScriptBridge.get_interface("window")
	callback=JavaScriptBridge.create_callback(_message)
	browser.BlackbladeNative=callback
	if browser.BlackbladeUI:browser.BlackbladeUI.ready()
	_send_state()

func _event(action:String,pressed:bool) -> void:
	var event:=InputEventAction.new();event.action=action;event.pressed=pressed
	Input.parse_input_event(event)

func _release_all() -> void:
	G.player.dodge_held=false;G.player.heavy_held=false
	G.player.queue="";G.player.queue_left=0
	for action in held:_event(action,false)
	held.clear()
	G.player.bot_move=Vector2.INF
	G.player.heavy_held=false;G.player.dodge_held=false;G.player.sprinting=false
	G.camera.mouse_delta=Vector2.ZERO

func _message(args:Array) -> void:
	if args.is_empty() or not args[0] is String:return
	var data=JSON.parse_string(args[0])
	if not data is Dictionary:return
	var type:String=data.get("type","")
	match type:
		"action":
			var action:String=data.get("action","")
			if not action in ACTIONS:return
			var pressed:bool=data.get("pressed",false)
			if pressed:
				if get_tree().paused or G.main.phase!="fight" or held.has(action):return
				held[action]=true
			elif not held.has(action):return
			else:held.erase(action)
			_event(action,pressed)
		"move":
			if get_tree().paused:return
			if data.get("active",false):
				var v:=Vector2(float(data.get("x",0)),-float(data.get("y",0)))
				if v.is_finite():G.player.bot_move=v.limit_length(1)
			else:G.player.bot_move=Vector2.INF
		"look":
			if get_tree().paused or G.main.phase!="fight":return
			var v:=Vector2(float(data.get("x",0)),float(data.get("y",0)))
			if v.is_finite():G.camera.mouse_delta+=v.limit_length(120)
		"start":
			_release_all();G.main.start(bool(data.get("training",false)))
		"retry":
			_release_all();G.main.start(G.training,true)
		"title":
			_release_all();G.main.to_title()
		"pause":
			_release_all()
			if get_tree().paused:G.ui.close_pause()
			elif G.main.phase=="fight":G.ui.open_pause()
		"blur":
			_release_all()
			if G.main.phase=="fight" and not get_tree().paused:G.ui.open_pause()
		"cancel":_release_all()
		"qa_dummy":
			# Repeatable training target for input tests; normal play has no flag.
			if "--qa-controls" in OS.get_cmdline_user_args() and G.training and G.main.phase=="fight":
				G.boss.ai_enabled=false;G.boss.state="idle";G.boss.attack="";G.boss.t=0
				G.boss.velocity=Vector3.ZERO;G.boss.global_position=Vector3(0,.05,-12)
		"phase":
			if G.training and G.main.phase=="fight":
				G.boss.set_training_phase();G.arena.rage(G.boss.phase==2);G.fx.reset()
		"setting":
			var key:String=data.get("key","")
			if key in ["volume","music"]:G.settings[key]=clampf(float(data.get("value",0)),0,1)
			elif key=="shake":G.settings.shake=bool(data.get("value",true))
			elif key=="quality":G.settings.quality=clampi(int(data.get("value",1)),0,2)
			else:return
			G.save()
	_send_state()

func _process(dt:float) -> void:
	timer+=dt
	if timer>=.10:timer=0;_send_state()

func _send_state() -> void:
	if not browser or not browser.BlackbladeUI:return
	var p=G.player;var b=G.boss
	var data:={"phase":G.main.phase,"paused":get_tree().paused,"training":G.training,
		"hp":p.hp,"hpCap":p.hp_cap,"maxHP":p.MAX_HP,"stamina":p.stamina,"maxStamina":p.MAX_STAMINA,
		"flasks":p.flasks,"bossHP":b.hp,"maxBossHP":b.MAX_HP,"bossPhase":b.phase,
		"stance":b.posture,"maxStance":b.STANCE,"locked":p.target!=null,
		"playerState":p.state,"action":p.action,"playerX":p.position.x,"playerZ":p.position.z,
		"playerMove":KnightMoves.key(p.action,p.combo) if p.state=="attack" else "",
		"charge":p.charge_time/FightBalance.CHARGE_TIME,"charged":p.charged,"counter":p.last_block<.8,
		"rolls":G.stats.rolls,"evades":G.stats.evades,"hits":G.stats.hits,"damage":G.stats.damage,
		"elapsed":G.elapsed,"fps":Engine.get_frames_per_second(),"curse":p.dd_timer,
		"volume":G.settings.volume,"music":G.settings.music,"shake":G.settings.shake,
		"quality":G.settings.quality,"renderScale":get_viewport().scaling_3d_scale,"msaa":get_viewport().msaa_3d,
		"shadows":G.arena.moon.shadow_enabled,"bossX":b.position.x,"bossZ":b.position.z,"bossState":b.state,"bossAttack":b.attack,
		"bossAI":b.ai_enabled}
	if "--qa-controls" in OS.get_cmdline_user_args():
		data.rollLocked=p.rig.roll_locked;data.rollLocalX=p.rig.roll_direction.x;data.rollLocalZ=p.rig.roll_direction.z
	browser.BlackbladeUI.update(JSON.stringify(data))
