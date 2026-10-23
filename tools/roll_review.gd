extends Node
var main:Node
var frames:=0
var sample_id:=0
const PHASES=[.0,.10,.20,.30,.40,.50,.60,.70,.80,.90,.999]
var active_phase:=0.0

func _ready() -> void:
	main=get_parent()

func _process(_dt:float) -> void:
	frames+=1
	if frames%10==1:print("REVIEW FRAME ",frames)
	if frames==2:
		main.start(true,true);main.ui.visible=false
		main.boss.set_physics_process(false);main.boss.visible=false
		main.player.set_physics_process(false);main.player.reset(Vector3(0,.05,0));main.player.rig.rotation.y=0
		main.player.rig.roll_direction=Vector3(0,0,1)
		main.camera.cinematic=true
		main.camera.cine_position=Vector3(4.0,1.65,2.2);main.camera.cine_target=Vector3(0,.85,0)
	if frames<20:return
	if frames%4==0:
		if sample_id>=PHASES.size():get_tree().quit();return
		active_phase=PHASES[sample_id]
	main.player.rig.pose("roll",active_phase*.70,1.0/60.0,0,Vector3.ZERO)
	if frames%4==3:
		var path:="res://artifacts/roll_pose_%02d.png"%sample_id
		get_viewport().get_texture().get_image().save_png(path)
		print("ROLL REVIEW ",sample_id," phase ",active_phase," clearance ",main.player.rig.roll_ground_clearance)
		sample_id+=1
