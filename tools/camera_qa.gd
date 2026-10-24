extends Node3D
class Actor:
	extends Node3D
	var target:Node3D
	var sprinting:=false
	var phase:=1
	var state:="idle"
	var lock_height:=1.45
	func lock_point() -> Vector3:return global_position+Vector3.UP*lock_height
	func alive() -> bool:return true
var checks:=[]
func check(label:String,ok:bool,detail:Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail});print("CAMERA ","PASS " if ok else "FAIL ",label," ",detail)
func settle(c,frames:=180) -> void:
	for i in frames:c._physics_process(1.0/60)
func normalized(c,point:Vector3) -> Vector2:
	return c.cam.unproject_position(point)/get_viewport().get_visible_rect().size
func _ready() -> void:run.call_deferred()
func run() -> void:
	G.settings.shake=false
	var player:=Actor.new();add_child(player);player.position.y=.05;G.player=player
	var boss:=Actor.new();add_child(boss);boss.position=Vector3(0,.05,-3.5);G.boss=boss
	var c=load("res://scripts/camera.gd").new();add_child(c);c.set_physics_process(false);c.cinematic=false
	player.target=null;c.distance=5.0;c.reset();settle(c)
	var before:float=absf(normalized(c,Vector3(0,.08,0)).y-normalized(c,Vector3(0,1.95,0)).y)
	c.distance=c.FOLLOW_DISTANCE;c.reset();settle(c)
	var after:float=absf(normalized(c,Vector3(0,.08,0)).y-normalized(c,Vector3(0,1.95,0)).y)
	check("free camera is moderately closer",c.smoothed_zoom<4.3 and after/before>1.12 and after/before<1.26,{"distance":c.smoothed_zoom,"character_scale_ratio":after/before})
	player.target=boss
	for spec in [{"id":"normal","position":Vector3(0,.05,-3.5),"top":2.8},{"id":"close","position":Vector3(.6,.05,-1.9),"top":2.8},{"id":"leap","position":Vector3(0,2.7,-3),"top":2.8},{"id":"overhead","position":Vector3(1.6,3.0,-1),"top":2.8}]:
		boss.position=spec.position;c.reset();settle(c)
		var hero_bottom:=normalized(c,Vector3(0,.08,0));var hero_top:=normalized(c,Vector3(0,1.95,0))
		var beast_top:=normalized(c,boss.position+Vector3.UP*float(spec.top));var beast_bottom:=normalized(c,boss.position+Vector3.UP*.10)
		var visible:=true
		for point in [hero_bottom,hero_top,beast_top,beast_bottom]:visible=visible and point.x>.025 and point.x<.975 and point.y>.025 and point.y<.975
		check("landscape framing "+String(spec.id),visible,{"hero_feet":[hero_bottom.x,hero_bottom.y],"hero_head":[hero_top.x,hero_top.y],"beast_head":[beast_top.x,beast_top.y],"beast_feet":[beast_bottom.x,beast_bottom.y],"distance":c.smoothed_zoom})
	player.target=null;c.reset();settle(c)
	var wall:=StaticBody3D.new();wall.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(6,5,.25);shape.shape=box;wall.add_child(shape);add_child(wall);wall.position=Vector3(0,2,2.65)
	await get_tree().physics_frame;await get_tree().physics_frame
	settle(c,3);var wall_distance:float=c.collision_distance
	check("wall shortens the boom before clipping",c.cam.global_position.z<2.53 and wall_distance>1,wall_distance)
	wall.queue_free();await get_tree().physics_frame;await get_tree().physics_frame
	var biggest:=0.0;var last:Vector3=c.cam.global_position
	for i in 60:
		c._physics_process(1.0/60);biggest=maxf(biggest,c.cam.global_position.distance_to(last));last=c.cam.global_position
	check("camera returns from a wall smoothly",biggest<.27 and c.collision_distance>4.1,{"max_frame_step":biggest,"distance":c.collision_distance})
	var failures:=checks.filter(func(item:Dictionary) -> bool:return not item.ok).size()
	var file:=FileAccess.open("res://artifacts/camera_verification.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"viewport":get_viewport().get_visible_rect().size}));file.close()
	get_tree().quit(1 if failures else 0)
