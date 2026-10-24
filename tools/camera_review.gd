extends "res://tools/motion_reel.gd"
class Actor:
	extends Node3D
	var target:Node3D
	var sprinting:=false
	var phase:=1
	var rig:FighterRig
	func lock_point() -> Vector3:return rig.target_point()+Vector3.UP*.25
func _ready() -> void:
	set_process(false);run.call_deferred()
func run() -> void:
	G.mobile=true;G.settings.quality=1;G.settings.shake=false;_world()
	var hero:=Actor.new();hero.position.y=.05;add_child(hero);hero.rig=FighterRig.new();hero.add_child(hero.rig);hero.rig.setup("knight");hero.rig.rotation.y=PI
	var beast:=Actor.new();add_child(beast);beast.rig=FighterRig.new();beast.rig.scale=Vector3.ONE*1.20;beast.add_child(beast.rig);beast.rig.setup("boss")
	hero.target=beast;G.player=hero;G.boss=beast
	var controller=load("res://scripts/camera.gd").new();add_child(controller);controller.set_physics_process(false);controller.cinematic=false
	for sample in [{"id":"before","distance":5.0,"position":Vector3(0,.05,-3.5),"action":"idle","time":0.0},{"id":"after","distance":4.2,"position":Vector3(0,.05,-3.5),"action":"idle","time":0.0},{"id":"overhead","distance":4.2,"position":Vector3(0,.05,-2.6),"action":"overhead","time":.82},{"id":"air","distance":4.2,"position":Vector3(0,2.55,-2.6),"action":"air_blades","time":1.1}]:
		beast.position=sample.position;beast.rig.initialized=false;hero.rig.initialized=false
		for i in 30:
			hero.rig.pose("idle",0,1.0/60,0,Vector3.ZERO);beast.rig.pose(sample.action,sample.time,1.0/60,0,Vector3.ZERO)
		controller.distance=sample.distance;controller.reset()
		for i in 180:controller._physics_process(1.0/60)
		var points:Array=beast.rig.blade()
		points.append(hero.global_position+Vector3.UP*.03)
		points.append(hero.global_position+Vector3.UP*1.95)
		points.append(beast.rig.motion.global_transform*beast.rig.globals.head.origin+Vector3.UP*.35)
		var visible:=true
		var bounds:=[]
		for point in points:
			var uv:Vector2=controller.cam.unproject_position(point)/get_viewport().get_visible_rect().size
			bounds.append([uv.x,uv.y])
			visible=visible and not controller.cam.is_position_behind(point) and uv.x>.02 and uv.x<.98 and uv.y>.02 and uv.y<.98
		print("CAMERA RIG ","PASS " if visible else "FAIL ",sample.id," ",bounds)
		if not visible:get_tree().quit(1);return
		label.text="CAMERA / %s / %.1fm"%[String(sample.id).to_upper(),sample.distance]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/camera_%s.png"%sample.id)
		print("CAMERA CAPTURE ",sample.id)
	get_tree().quit()
