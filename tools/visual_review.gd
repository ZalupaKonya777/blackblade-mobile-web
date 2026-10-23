extends Node
## Fixed camera/poses for reviewing the actual mobile materials on a GPU.
## This does not replace the movement and input checks in the browser.
var main:Node
var frame:=0
var shot:=0
var report:={"shots":[],"materials":[]}
const SHOTS=["boss_idle","boss_stride","boss_sweep","boss_leap","knight_roll"]

func _ready() -> void:
	main=get_parent();main.start(true,true);main.set_process(false)
	for tween in get_tree().get_processed_tweens():tween.kill()
	main.boss.set_physics_process(false);main.player.set_physics_process(false)
	main.camera.set_physics_process(false);main.ui.visible=false
	G.playing=false;G.settings.quality=1;G.changed.emit()
	for rig in [main.player.rig,main.boss.rig]:
		var entry:={"kind":rig.kind,"materials":[]}
		for mat in rig.body_materials:
			var maps:={}
			for key in ["surface","normal_map","armor"]:
				var texture:Texture2D=mat.get_shader_parameter(key)
				maps[key]={"width":texture.get_width(),"height":texture.get_height(),"mipmaps":texture.get_image().has_mipmaps()}
			entry.materials.append(maps)
		report.materials.append(entry)
	report.shadows=main.arena.moon.shadow_enabled
	report.msaa=get_viewport().msaa_3d;report.render_scale=get_viewport().scaling_3d_scale
	report.reflections=main.arena.env.reflected_light_source
	report.renderer=RenderingServer.get_video_adapter_name()
	_prepare()

func _prepare() -> void:
	main.player.position=Vector3(-2.1,.05,1.8);main.player.yaw=PI;main.player.rig.rotation.y=PI
	main.boss.position=Vector3(0,.05,-.8);main.boss.yaw=0;main.boss.rig.rotation.y=0
	main.player.rig.initialized=false;main.boss.rig.initialized=false
	var id:String=SHOTS[shot]
	var action:="idle";var t:=0.0;var speed:=0.0
	if id=="boss_stride":action="move";t=.35;speed=3.6
	if id=="boss_sweep":action="sweep";t=.72
	if id=="boss_leap":action="leap";t=.82;main.boss.position.y=1.8
	for i in 24:
		main.boss.rig.pose(action,t,1.0/60.0,speed,Vector3(0,0,1))
		main.player.rig.pose("idle",0,1.0/60.0,0,Vector3.ZERO)
	var cam:Camera3D=main.camera.cam;cam.fov=48
	cam.global_position=Vector3(4.8,2.6,4.6);cam.look_at(Vector3(-.15,1.5,-.4))
	if id=="boss_leap":
		cam.global_position=Vector3(5.4,3.3,7.2);cam.look_at(Vector3(0,2.3,-.6));cam.fov=54
	if id=="knight_roll":
		main.boss.visible=false;main.player.position=Vector3(0,.05,0)
		main.player.rig.roll_direction=Vector3.FORWARD
		main.player.rig.initialized=false
		for i in 12:main.player.rig.pose("roll",.32,1.0/60.0,0,Vector3.ZERO)
		cam.global_position=Vector3(3.4,1.9,2.8);cam.look_at(Vector3(0,.6,0));cam.fov=42
	print("VISUAL REVIEW ",id)

func _process(_dt:float) -> void:
	frame+=1
	if frame%2!=0:return
	var id:String=SHOTS[shot]
	var img:=get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/visual_%s.png"%id)
	report.shots.append({"id":id,"width":img.get_width(),"height":img.get_height()})
	shot+=1
	if shot>=SHOTS.size():
		var file:=FileAccess.open("res://artifacts/visual_review.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "));file.close();get_tree().quit()
	else:_prepare()
