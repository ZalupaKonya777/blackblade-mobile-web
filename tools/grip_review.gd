extends Node3D
var rig:FighterRig
var cam:Camera3D
var frame:=0
var shot:=0
var kind:="knight"
var views:=["hand","full","cut"]
func _ready() -> void:
	if "--boss" in OS.get_cmdline_user_args():kind="boss"
	var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.12,.14,.17)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.75,.81,.9);env.ambient_light_energy=.65;world.environment=env;add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-42,-32,0);light.light_energy=1.1;add_child(light)
	var rim:=DirectionalLight3D.new();rim.rotation_degrees=Vector3(-22,135,0);rim.light_energy=.5;rim.light_color=Color(1,.74,.48);add_child(rim)
	rig=FighterRig.new();add_child(rig);rig.setup(kind);rig.secondary_motion=false
	cam=Camera3D.new();add_child(cam);cam.current=true;cam.near=.015
	prepare()
func prepare() -> void:
	rig.initialized=false
	for i in 24:rig.pose("sweep" if kind=="boss" and shot==2 else ("light" if shot==2 else "idle"),.72 if kind=="boss" else .42,1.0/60,0,Vector3.ZERO)
	if "--rest" in OS.get_cmdline_user_args():
		rig.skel.reset_bone_poses();rig.weapon.visible=false;views=["rest"]
		cam.global_position=Vector3(5,3.0,6);cam.look_at(Vector3(0,2.0,0));cam.fov=42;return
	var grip:=rig.motion.to_global(rig.grip)
	cam.fov=40
	if shot==0:
		cam.global_position=grip+Vector3(-.40,.26,.38)*(2.0 if kind=="boss" else 1.0);cam.look_at(grip)
	else:
		cam.global_position=Vector3(4,2.5,4)*(1.3 if kind=="boss" else .7);cam.look_at(Vector3(0,.9 if kind=="knight" else 1.4,.25))
func _process(_dt:float) -> void:
	frame+=1
	if frame%3!=0:return
	if DisplayServer.get_name()!="headless":get_viewport().get_texture().get_image().save_png("res://artifacts/grip_%s_%s.png"%[kind,views[shot]])
	print("GRIP REVIEW ",kind," ",views[shot]," socket ",rig.grip)
	shot+=1
	if shot>=views.size():get_tree().quit()
	else:prepare()
