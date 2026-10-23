extends Node
var frames:=0
var main:Node
var shot:="title"
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	main=get_tree().current_scene
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):shot=a.split("=")[1]
func _process(_dt:float) -> void:
	frames+=1
	if frames%10==1:print("CAPTURE FRAME ",frames)
	if frames==3 and shot!="title":
		main.start(false,true)
		main.boss.ai_enabled=false
		main.player.bot_move=Vector2.ZERO
		main.player.global_position=Vector3(0,.05,2)
		main.boss.global_position=Vector3(0,.05,-2)
		if shot=="pause":main.ui.open_pause()
		if shot=="boss":
			main.camera.cinematic=true;main.camera.cine_position=Vector3(3.5,2.1,2);main.camera.cine_target=Vector3(0,1.5,-2)
		if shot=="phase2":main.boss.phase=2;main.arena.rage(true)
		if shot=="roll":
			main.camera.cinematic=true;main.camera.cine_position=Vector3(5,2,2);main.camera.cine_target=Vector3(0,.8,2)
	if frames==10 and shot=="roll":
		main.player.move_dir=Vector3(0,0,-1);main.player._command("dodge")
	if frames==20 or (shot=="roll" and frames==28):
		var img:=get_viewport().get_texture().get_image();img.save_png("res://artifacts/"+shot+".png")
		print("CAPTURE ",shot," fps ",Engine.get_frames_per_second())
		get_tree().quit()
