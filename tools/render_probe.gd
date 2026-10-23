extends Node3D
var frames:=0
func _ready() -> void:
	var e:=WorldEnvironment.new();e.environment=Environment.new();e.environment.background_mode=Environment.BG_COLOR;e.environment.background_color=Color(.12,.15,.21);e.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.environment.ambient_light_color=Color(.7,.75,.8);e.environment.ambient_light_energy=.8;add_child(e)
	var cam:=Camera3D.new();add_child(cam);cam.position=Vector3(4,2.6,5);cam.look_at(Vector3(0,1.4,0));cam.current=true
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-20,0);sun.light_energy=1.3;add_child(sun)
	var mode:="box"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe="):mode=a.split("=")[1]
	if mode=="rig":
		var rig:=FighterRig.new();add_child(rig);rig.setup("boss")
	elif mode=="arena":
		var arena=load("res://scripts/arena.gd").new();add_child(arena)
	else:
		var mi:=MeshInstance3D.new();mi.mesh=BoxMesh.new();mi.position.y=1;add_child(mi)
	print("PROBE READY ",mode)
func _process(_dt:float) -> void:
	frames+=1
	print("PROBE FRAME ",frames)
	if frames==8:
		get_viewport().get_texture().get_image().save_png("res://artifacts/render_probe.png");get_tree().quit()
