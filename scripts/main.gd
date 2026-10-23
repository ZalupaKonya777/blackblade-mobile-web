extends Node3D

var phase:="title"
var phase_t:=0.0
var ui:CanvasLayer
var camera:Node3D
var player:PlayerUnit
var boss:EclipseBeast
var arena:Node3D
var test_mode:=false

func _ready() -> void:
	randomize();G.main=self
	arena=load("res://scripts/arena.gd").new();add_child(arena)
	var fx=load("res://scripts/fx.gd").new();add_child(fx)
	var audio=load("res://scripts/audio.gd").new();add_child(audio)
	player=PlayerUnit.new();player.position=Vector3(0,.04,7);add_child(player)
	boss=EclipseBeast.new();boss.position=Vector3(0,.04,-5);add_child(boss)
	var presentation=load("res://scripts/presentation.gd").new();add_child(presentation)
	camera=load("res://scripts/camera.gd").new();add_child(camera)
	camera.cam.global_position=Vector3(4,2.7,1.7)
	camera.cine_position=Vector3(4,2.7,1.7);camera.cine_target=Vector3(-1.5,1.45,-5)
	ui=load("res://scripts/interface.gd").new();add_child(ui)
	if OS.has_feature("web"):
		var bridge=load("res://scripts/mobile_bridge.gd").new();add_child(bridge)
	G.player_dead.connect(_dead);G.beast_dead.connect(_won);G.new_phase.connect(_phase_two)
	if "--verify" in OS.get_cmdline_user_args():
		test_mode=true
		var test=load("res://tools/verify.gd").new();add_child(test);test.run.call_deferred(self)
	if "--beast-verify" in OS.get_cmdline_user_args():
		test_mode=true
		var test=load("res://tools/beast_verify.gd").new();add_child(test);test.run.call_deferred(self)
	if "--showcase" in OS.get_cmdline_user_args():
		var reel=load("res://tools/showcase.gd").new();add_child(reel)
	if "--capture" in OS.get_cmdline_user_args():
		var capture=load("res://tools/capture.gd").new();add_child(capture)
	if "--visual-review" in OS.get_cmdline_user_args():
		var review=load("res://tools/visual_review.gd").new();add_child(review)
	if "--pose-dump" in OS.get_cmdline_user_args():
		var review=load("res://tools/pose_dump.gd").new();add_child(review)
	if "--skin-audit" in OS.get_cmdline_user_args():
		var review=load("res://tools/skin_audit.gd").new();add_child(review)
	if "--roll-review" in OS.get_cmdline_user_args():
		var review=load("res://tools/roll_review.gd").new();add_child(review)
	if "--polish-showcase" in OS.get_cmdline_user_args():
		var reel=load("res://tools/polish_showcase.gd").new();add_child(reel)
	if "--beast-showcase" in OS.get_cmdline_user_args():
		var reel=load("res://tools/beast_showcase.gd").new();add_child(reel)
	if "--weight-showcase" in OS.get_cmdline_user_args():
		var reel=load("res://tools/weight_showcase.gd").new();add_child(reel)

func start(training:bool,retry:=false) -> void:
	get_tree().paused=false;G.freeze=0;G.training=training;G.playing=true;G.reset_stats()
	if retry:G.attempt+=1
	G.fx.reset();arena.rage(false)
	player.reset(Vector3(0,.05,6));player.controls_enabled=retry;boss.reset(Vector3(0,.05,-5));camera.reset()
	ui.begin();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if G.mobile else Input.MOUSE_MODE_CAPTURED
	G.audio.fight(true)
	phase_t=0
	if retry:
		phase="fight";boss.state="idle";boss.wait=.9;camera.cinematic=false;player.target=boss
	else:
		phase="intro";boss.state="intro";boss.t=0;camera.cinematic=true
		camera.cine_position=Vector3(4,2.5,.8);camera.cine_target=Vector3(0,1.55,-5)
		ui.notify("АСТАР", "Зверь забытого храма")
	if training:ui.notify("ТРЕНИРОВКА", "Можно отрабатывать тайминги. Здоровье восстанавливается, босс бессмертен.")

func _process(dt:float) -> void:
	phase_t+=dt
	if phase=="title":
		camera.cine_position=Vector3(4+sin(phase_t*.13)*.65,2.6+sin(phase_t*.2)*.10,1.7)
	elif phase=="intro":
		player.velocity=Vector3.ZERO
		if phase_t>2.5:
			phase="fight";phase_t=0;camera.cinematic=false;player.target=boss;player.controls_enabled=true;G.elapsed=0
	elif phase in ["dead","won"]:
		if phase_t>1.0 and ui.mode!="result":ui.result(phase=="won")

func _dead() -> void:
	phase="dead";phase_t=0;G.audio.fight(false);G.audio.play("death",player.global_position,-1)

func _won() -> void:
	phase="won";phase_t=0;G.audio.fight(false);G.audio.play("win",player.global_position,-1)

func _phase_two() -> void:
	ui.notify("ЧЁРНЫЙ КЛИНОК", "Предначертанная смерть")

func to_title() -> void:
	get_tree().paused=false;G.playing=false;G.freeze=0;phase="title";phase_t=0
	G.audio.fight(false);G.fx.reset();arena.rage(false)
	player.reset(Vector3(0,.05,7));boss.reset(Vector3(0,.05,-5));camera.cinematic=true
	camera.cine_target=Vector3(-1.5,1.45,-5);ui.show_title()

func _unhandled_input(e:InputEvent) -> void:
	if e.is_action_pressed("interact") and G.training and phase=="fight":
		boss.set_training_phase()
		arena.rage(boss.phase==2);G.fx.reset()
		ui.notify("ФАЗА II" if boss.phase==2 else "ФАЗА I", "Тренировка: E / Y переключает фазу")
